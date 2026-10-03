package eu.kanade.tachiyomi.ui.vr

// KMK -->
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.core.graphics.drawable.toBitmap
import androidx.lifecycle.lifecycleScope
import coil3.asDrawable
import coil3.imageLoader
import coil3.request.ImageRequest
import coil3.request.allowHardware
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.ui.reader.ReaderViewModel
import eu.kanade.tachiyomi.ui.reader.setting.ReadingMode
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import mihon.app.di.appGraph
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONArray
import org.json.JSONObject
import tachiyomi.domain.manga.model.asMangaCover
import tachiyomi.i18n.kmk.KMR
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class HouriVrBridge(godot: Godot, private val host: VrActivity) : GodotPlugin(godot) {
    private val graph = host.appGraph
    private val session = File(host.cacheDir, "vr/${UUID.randomUUID()}").apply { mkdirs() }
    private val pageJobs = ConcurrentHashMap<String, Job>()
    private val navigation = Mutex()
    private var reader: ReaderViewModel? = null

    @Volatile private var token = ""

    override fun getPluginName() = "HouriVR"

    override fun getPluginSignals() = setOf(SignalInfo("response", String::class.java))

    @UsedByGodot
    fun labels(): String = JSONObject(
        mapOf(
            "Library" to KMR.strings.vr_library,
            "Center" to KMR.strings.vr_center,
            "Black" to KMR.strings.vr_black,
            "See through" to KMR.strings.vr_passthrough,
            "LTR / RTL" to KMR.strings.vr_direction,
            "Exit VR" to KMR.strings.vr_exit,
            "Size" to KMR.strings.vr_size,
            "Distance" to KMR.strings.vr_distance,
            "Tilt" to KMR.strings.vr_tilt,
            "Close" to KMR.strings.vr_close,
            "Loading library…" to KMR.strings.vr_loading,
            "Search library / chapters" to KMR.strings.vr_search,
            "All categories" to KMR.strings.vr_categories,
            "Pages" to KMR.strings.vr_pages,
            "entries" to KMR.strings.vr_entries,
            "screen" to KMR.strings.vr_screen,
            "Unable to load content" to KMR.strings.vr_content_error,
            "Unable to decode page" to KMR.strings.vr_page_error,
            "Waiting for pages, or chapter boundary" to KMR.strings.vr_waiting,
            "Passthrough unavailable; using black" to KMR.strings.vr_passthrough_unavailable,
        ).mapValues { (_, resource) -> resource.getString(host) },
    ).toString()

    @UsedByGodot
    fun request(payload: String) {
        // Acquire navigation in call order before dispatching work, including the final save before exit.
        host.lifecycleScope.launch(start = CoroutineStart.UNDISPATCHED) {
            try {
                val request = JSONObject(payload)
                if (request.getString("action") in listOf("open", "progress", "next_chapter", "previous_chapter", "exit")) {
                    navigation.withLock { withContext(Dispatchers.IO) { handleRequest(request) } }
                } else {
                    withContext(Dispatchers.IO) { handleRequest(request) }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                send(JSONObject().put("kind", "error").put("message", error.message ?: error.javaClass.simpleName))
            }
        }
    }

    private suspend fun handleRequest(request: JSONObject) {
        when (request.getString("action")) {
            "library" -> library()
            "chapters" -> chapters(request.getString("manga").toLong())
            "cover" -> cover(request.getString("manga").toLong())
            "open" -> open(request.getString("manga").toLong(), request.getString("chapter").toLong())
            "page" -> page(request.getString("token"), request.getInt("index"))
            "progress" -> progress(request.getString("token"), request.getInt("index"))
            "next_chapter", "previous_chapter" -> reader?.let {
                val before = it.currentChapter?.id
                it.awaitPendingPageSaves()
                if (request.getString("action") == "next_chapter") it.loadNextChapter() else it.loadPreviousChapter()
                if (it.currentChapter?.id != before) publishChapter(it)
            }
            "exit" -> {
                reader?.awaitPendingPageSaves()
                host.exitVr()
            }
        }
    }

    private fun send(data: JSONObject) = emitSignal("response", data.toString())

    private suspend fun library() {
        val entries = graph.getLibraryManga.await().sortedBy { it.manga.title.lowercase() }
        val items = JSONArray()
        entries.forEach {
            items.put(
                JSONObject().put("id", it.id.toString()).put("title", it.manga.title)
                    .put("unread", it.unreadCount).put("categories", JSONArray(it.categories.map(Long::toString))),
            )
        }
        val categories = JSONArray()
        graph.getCategories.await().forEach {
            categories.put(JSONObject().put("id", it.id.toString()).put("title", it.name))
        }
        send(JSONObject().put("kind", "library").put("items", items).put("categories", categories))
    }

    private suspend fun cover(mangaId: Long) {
        val manga = graph.getManga.await(mangaId) ?: return
        val request = ImageRequest.Builder(host).data(manga.asMangaCover()).size(384, 512).allowHardware(false).build()
        val drawable = host.imageLoader.execute(request).image?.asDrawable(host.resources) ?: return
        val bitmap = drawable.toBitmap()
        val file = File(session, "cover-$mangaId.png")
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        send(JSONObject().put("kind", "cover").put("manga", mangaId.toString()).put("path", file.absolutePath))
        session.listFiles()?.filter { it.name.startsWith("cover-") }?.sortedByDescending { it.lastModified() }
            ?.drop(24)?.forEach { it.delete() }
    }

    private suspend fun chapters(mangaId: Long) {
        val items = JSONArray()
        graph.getChaptersByMangaId.await(mangaId).sortedByDescending { it.sourceOrder }.forEach {
            items.put(JSONObject().put("id", it.id.toString()).put("title", it.name).put("read", it.read))
        }
        send(JSONObject().put("kind", "chapters").put("manga", mangaId.toString()).put("items", items))
    }

    private suspend fun open(mangaId: Long, chapterId: Long) {
        val manga = graph.getManga.await(mangaId) ?: error("Manga no longer exists")
        val chapter = graph.getChapter.await(chapterId) ?: error("Chapter no longer exists")
        require(chapter.mangaId == manga.id) { "Chapter does not belong to this manga" }
        pageJobs.values.forEach { it.cancel() }
        pageJobs.clear()
        reader?.awaitPendingPageSaves()
        val model = withContext(Dispatchers.Main) { host.reader(mangaId) }
        if (model.manga == null) {
            model.init(mangaId, chapterId, null).getOrThrow()
        } else if (model.currentChapter?.id != chapterId) {
            model.loadNewChapterFromDialog(chapter)
            withTimeout(60_000) { model.state.first { it.currentChapter?.chapter?.id == chapterId } }
        }
        reader = model
        publishChapter(model)
    }

    private suspend fun publishChapter(model: ReaderViewModel) {
        val chapter = model.state.value.currentChapter ?: error("Chapter failed to load")
        val pages = chapter.pages ?: error("Chapter has no pages")
        token = UUID.randomUUID().toString()
        pageJobs.values.toList().forEach { it.cancelAndJoin() }
        pageJobs.clear()
        session.listFiles()?.filterNot { it.name.startsWith("cover-") }?.forEach { it.delete() }
        send(
            JSONObject().put("kind", "chapter").put("token", token).put("count", pages.size)
                .put("start", chapter.requestedPage.coerceIn(0, pages.lastIndex))
                .put("rtl", ReadingMode.fromPreference(model.getMangaReadingMode()) == ReadingMode.RIGHT_TO_LEFT)
                .put("title", "${model.manga?.title} · ${chapter.chapter.name}"),
        )
    }

    private suspend fun page(requestToken: String, index: Int) {
        if (requestToken != token) return
        val chapter = reader?.state?.value?.currentChapter ?: return
        val pages = chapter.pages ?: return
        val page = pages.getOrNull(index) ?: return
        val loader = chapter.pageLoader ?: return
        val key = "$requestToken-$index"
        if (pageJobs.containsKey(key)) return
        coroutineScope {
            val job = launch(start = CoroutineStart.LAZY) {
                val file = File(session, "$key.png")
                if (!file.isFile) {
                    val load = launch { loader.loadPage(page) }
                    try {
                        val state = withTimeout(60_000) { page.statusFlow.first { it == Page.State.Ready || it is Page.State.Error } }
                        check(state == Page.State.Ready) { "Page ${index + 1} failed to load" }
                        val stream = page.stream ?: error("Page image is unavailable")
                        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                        stream().use { BitmapFactory.decodeStream(it, null, bounds) }
                        var sample = 1
                        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 4096) sample *= 2
                        val options = BitmapFactory.Options().apply { inSampleSize = sample }
                        val bitmap = stream().use { BitmapFactory.decodeStream(it, null, options) } ?: error("Unsupported page image")
                        try {
                            file.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
                        } finally {
                            bitmap.recycle()
                        }
                    } finally {
                        load.cancelAndJoin()
                    }
                }
                if (requestToken == token) {
                    send(JSONObject().put("kind", "page").put("token", token).put("index", index).put("path", file.absolutePath))
                }
            }
            if (pageJobs.putIfAbsent(key, job) != null) {
                job.cancel()
                return@coroutineScope
            }
            job.start()
            try {
                job.join()
            } finally {
                pageJobs.remove(key, job)
            }
        }
    }

    private suspend fun progress(requestToken: String, index: Int) {
        if (requestToken != token) return
        val model = reader ?: return
        val chapter = model.state.value.currentChapter ?: return
        val page = chapter.pages?.getOrNull(index) ?: return
        withContext(Dispatchers.Main) {
            if (requestToken == token) model.onPageSelected(page, chapter.displayNumber(page).toString(), false)
        }
        model.awaitPendingPageSaves()
        // Disk cache is bounded to neighboring spreads; original images remain in Houri's caches.
        session.listFiles()?.filter { it.name.startsWith(requestToken) }?.forEach {
            val cached = it.name.removePrefix("$requestToken-").substringBefore('.').toIntOrNull()
            if (cached != null && kotlin.math.abs(cached - index) > 6 && !pageJobs.containsKey(it.nameWithoutExtension)) it.delete()
        }
    }

    fun close() {
        pageJobs.values.forEach { it.cancel() }
        pageJobs.clear()
        session.deleteRecursively()
    }

    suspend fun flushProgress() = navigation.withLock { reader?.awaitPendingPageSaves() }
}
// KMK <--
