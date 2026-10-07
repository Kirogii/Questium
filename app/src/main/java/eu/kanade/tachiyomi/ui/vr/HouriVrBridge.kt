package eu.kanade.tachiyomi.ui.vr

// KMK -->
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Rect
import android.text.Editable
import android.text.TextWatcher
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import androidx.core.graphics.drawable.toBitmap
import androidx.lifecycle.lifecycleScope
import coil3.asDrawable
import coil3.imageLoader
import coil3.request.ImageRequest
import coil3.request.allowHardware
import eu.kanade.tachiyomi.source.CatalogueSource
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
import mihon.domain.manga.model.toDomainManga
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
    private val readers = ConcurrentHashMap<String, ReaderViewModel>()
    private var keyboardInput: EditText? = null

    @Volatile private var token = ""

    override fun getPluginName() = "HouriVR"

    override fun getPluginSignals() = setOf(SignalInfo("response", String::class.java))

    @UsedByGodot
    fun showKeyboard(text: String, field: String) {
        host.runOnUiThread {
            keyboardInput?.let { (it.parent as? ViewGroup)?.removeView(it) }
            val input = EditText(host).apply {
                setSingleLine(true)
                inputType = android.text.InputType.TYPE_CLASS_TEXT
                imeOptions = EditorInfo.IME_ACTION_SEARCH or EditorInfo.IME_FLAG_NO_EXTRACT_UI
                setText(text)
                setSelection(text.length)
                alpha = 0f
            }
            keyboardInput = input
            val root = host.window.decorView as ViewGroup
            root.addView(input, FrameLayout.LayoutParams(1, 1))
            input.addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                    send(JSONObject().put("kind", "keyboard_text").put("text", s.toString()).put("field", field))
                }
                override fun afterTextChanged(s: Editable?) = Unit
            })
            input.setOnEditorActionListener { _, _, _ ->
                send(JSONObject().put("kind", "keyboard_text").put("text", input.text.toString()).put("submitted", true).put("field", field))
                (host.getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as InputMethodManager)
                    .hideSoftInputFromWindow(input.windowToken, 0)
                root.removeView(input)
                keyboardInput = null
                true
            }
            input.requestFocus()
            input.post {
                (host.getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as InputMethodManager)
                    .showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
            }
        }
    }

    @UsedByGodot
    fun labels(): String = JSONObject(
        mapOf(
            "Force two pages" to KMR.strings.vr_force_spread,
            "Force long scroll" to KMR.strings.vr_force_scroll,
            "Choose Source" to KMR.strings.vr_source_choose,
            "Add Repository" to KMR.strings.vr_repository_add,
            "Repository URL" to KMR.strings.vr_repository_url,
            "Paste the extension repository URL." to KMR.strings.vr_repository_help,
            "Installed repositories" to KMR.strings.vr_repository_installed,
            "No repositories added." to KMR.strings.vr_repository_empty,
            "Enter a repository URL." to KMR.strings.vr_repository_required,
            "Adding repository…" to KMR.strings.vr_repository_adding,
            "Repository added." to KMR.strings.vr_repository_added,
            "Unable to add repository." to KMR.strings.vr_repository_failed,
            "Source languages" to KMR.strings.vr_source_languages,
            "Multilingual" to KMR.strings.vr_source_multilingual,
            "Search sources" to KMR.strings.vr_source_search,
            "🛍 Install more extension sources" to KMR.strings.vr_source_install_more,
            "No extensions available from configured repositories." to KMR.strings.vr_extensions_empty,
            "Installing extension…" to KMR.strings.vr_extension_installing,
            "Extension installed" to KMR.strings.vr_extension_installed,
            "Extension installation failed" to KMR.strings.vr_extension_failed,
            "Today" to KMR.strings.vr_frosted_today,
            "Yesterday" to KMR.strings.vr_frosted_yesterday,
            "Earlier" to KMR.strings.vr_frosted_earlier,
            "Your Books" to KMR.strings.vr_frosted_your_books,
            "Recently Deleted" to KMR.strings.vr_frosted_deleted,
            "Remove from Library" to KMR.strings.vr_frosted_remove,
            "Home" to KMR.strings.vr_frosted_0,
            "Source Search" to KMR.strings.vr_frosted_1,
            "Reader" to KMR.strings.vr_frosted_2,
            "All Books" to KMR.strings.vr_frosted_3,
            "All books" to KMR.strings.vr_frosted_4,
            "Recents" to KMR.strings.vr_frosted_5,
            "Favorites" to KMR.strings.vr_frosted_6,
            "Recenter" to KMR.strings.vr_frosted_7,
            "Book Settings" to KMR.strings.vr_frosted_8,
            "Books" to KMR.strings.vr_frosted_9,
            "Your manga library" to KMR.strings.vr_frosted_10,
            "Search your books" to KMR.strings.vr_frosted_11,
            "Search books in this source" to KMR.strings.vr_frosted_12,
            "Keyboard" to KMR.strings.vr_frosted_13,
            "Search" to KMR.strings.vr_frosted_14,
            "Previous" to KMR.strings.vr_frosted_15,
            "Next" to KMR.strings.vr_frosted_16,
            "Save to Library" to KMR.strings.vr_frosted_17,
            "Saved to Library" to KMR.strings.vr_frosted_18,
            "Read" to KMR.strings.vr_frosted_19,
            "Resume" to KMR.strings.vr_frosted_20,
            "Info" to KMR.strings.vr_frosted_21,
            "Book Info" to KMR.strings.vr_frosted_22,
            "Find a chapter" to KMR.strings.vr_frosted_23,
            "Chapters" to KMR.strings.vr_frosted_24,
            "Space" to KMR.strings.vr_frosted_25,
            "Backspace" to KMR.strings.vr_frosted_26,
            "Loading…" to KMR.strings.vr_frosted_27,
            "Loading library…" to KMR.strings.vr_frosted_28,
            "Loading book details…" to KMR.strings.vr_frosted_29,
            "Searching…" to KMR.strings.vr_frosted_30,
            "Choose a book and tap Read to open the Reader." to KMR.strings.vr_frosted_31,
            "No books found. Choose a source and search." to KMR.strings.vr_frosted_32,
            "Your library is empty. Find books in Source Search and save them here." to KMR.strings.vr_frosted_33,
            "No installed sources. Install a source extension to search." to KMR.strings.vr_frosted_34,
            "Next page" to KMR.strings.vr_controls_next,
            "Previous page" to KMR.strings.vr_controls_previous,
            "Interact" to KMR.strings.vr_controls_interact,
            "Grab" to KMR.strings.vr_controls_grab,
            "Book Options" to KMR.strings.vr_controls_book_options,
            "Switch hands" to KMR.strings.vr_controls_switch_hands,
            "None" to KMR.strings.vr_controls_none,
            "Options" to KMR.strings.vr_controls_options,
            "Close Book" to KMR.strings.vr_controls_close_book,
            "Edit Settings" to KMR.strings.vr_controls_edit_settings,
            "Reader Settings" to KMR.strings.vr_controls_reader_settings,
            "Controller configuration" to KMR.strings.vr_controls_configuration,
            "Pointer hand" to KMR.strings.vr_controls_pointer_hand,
            "Haptic feedback" to KMR.strings.vr_controls_haptics,
            "Hand tracking: pinch to select; grab page bars to flip" to KMR.strings.vr_controls_hand_help,
            "Quest 3 / 3S Controllers" to KMR.strings.vr_controls_quest_controllers,
            "Reset controls" to KMR.strings.vr_controls_reset,
            "Back" to KMR.strings.vr_controls_back,
            "Trigger" to KMR.strings.vr_controls_trigger,
            "Grip" to KMR.strings.vr_controls_grip,
            "Stick click" to KMR.strings.vr_controls_stick_click,
            "Menu" to KMR.strings.vr_controls_menu,
            "left" to KMR.strings.vr_controls_left,
            "right" to KMR.strings.vr_controls_right,
            "Meta button: system menu" to KMR.strings.vr_controls_meta_menu,
            "Stick: left/right pages; left up/down distance; right up/down size" to KMR.strings.vr_controls_stick_help,
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
                if (request.getString("action") in listOf("open", "close_book", "progress", "next_chapter", "previous_chapter", "exit")) {
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
            "sources" -> sources()
            "extensions" -> extensions()
            "repositories" -> repositories()
            "add_repository" -> addRepository(request.getString("url"))
            "install_extension" -> {
                val extension = graph.extensionManager.availableExtensionsFlow.value
                    .firstOrNull { it.pkgName == request.getString("package") } ?: error("Extension is unavailable")
                graph.extensionManager.installExtension(extension).collect {
                    send(
                        JSONObject().put("kind", "install_status").put(
                            "message",
                            when (it) {
                                eu.kanade.tachiyomi.extension.model.InstallStep.Installed -> "Extension installed"
                                eu.kanade.tachiyomi.extension.model.InstallStep.Error -> "Extension installation failed"
                                else -> "Installing extension…"
                            },
                        ),
                    )
                }
                sources()
            }
            "source_search" -> sourceSearch(request)
            "details" -> details(request.getString("manga").toLong())
            "favorite" -> {
                val mangaId = request.getString("manga").toLong()
                graph.updateManga.awaitUpdateFavorite(mangaId, request.getBoolean("enabled"))
                details(mangaId)
            }
            "close_book" -> {
                val closed = request.getString("token")
                readers.remove(closed)?.awaitPendingPageSaves()
                pageJobs.filterKeys { it.startsWith(closed) }.values.toList().forEach { it.cancelAndJoin() }
                session.listFiles()?.filter { it.name.startsWith(closed) }?.forEach { it.delete() }
            }
            "library" -> library()
            "chapters" -> chapters(request.getString("manga").toLong())
            "cover" -> cover(request.getString("manga").toLong())
            "open" -> open(request.getString("manga").toLong(), request.getString("chapter").toLong())
            "page" -> page(request.getString("token"), request.getInt("index"))
            "progress" -> progress(request.getString("token"), request.getInt("index"))
            "next_chapter", "previous_chapter" -> readers[request.optString("token", token)]?.let {
                val before = it.currentChapter?.id
                it.awaitPendingPageSaves()
                if (request.getString("action") == "next_chapter") it.loadNextChapter() else it.loadPreviousChapter()
                if (it.currentChapter?.id != before) publishChapter(it, request.optString("token"))
            }
            "exit" -> {
                readers.values.toSet().forEach { it.awaitPendingPageSaves() }
                host.exitVr()
            }
        }
    }

    private fun send(data: JSONObject) = emitSignal("response", data.toString())

    private suspend fun repositories() {
        val items = JSONArray()
        graph.getExtensionStores.get().forEach {
            items.put(JSONObject().put("title", it.name).put("url", it.indexUrl))
        }
        send(JSONObject().put("kind", "repositories").put("items", items))
    }

    private suspend fun addRepository(url: String) {
        val result = kotlinx.coroutines.withTimeoutOrNull(30_000) { graph.addExtensionStore(url.trim()) }
            ?: Result.failure(IllegalStateException("Unable to add repository."))
        send(
            JSONObject().put("kind", "repository_status").put("success", result.isSuccess)
                .put("message", if (result.isSuccess) "Repository added." else result.exceptionOrNull()?.message ?: "Unable to add repository."),
        )
        if (result.isSuccess) {
            repositories()
            extensions()
        }
    }

    private suspend fun sources() {
        graph.sourceManager.isInitialized.first { it }
        val items = JSONArray()
        graph.sourceManager.getVisibleSources().filterIsInstance<CatalogueSource>().sortedBy { it.name }.forEach {
            val icon = graph.extensionManager.getAppIconForSource(it.id)
            val iconFile = File(session, "source-${it.id}.png")
            icon?.toBitmap(64, 64)?.let { bitmap ->
                iconFile.outputStream().use { stream -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream) }
            }
            items.put(
                JSONObject().put("id", it.id.toString()).put("title", "${it.name} · ${it.lang}").put("lang", it.lang)
                    .put("icon", if (iconFile.exists()) iconFile.absolutePath else ""),
            )
        }
        send(JSONObject().put("kind", "sources").put("items", items))
    }

    private suspend fun extensions() {
        graph.extensionManager.findAvailableExtensions()
        val items = JSONArray()
        val available = kotlinx.coroutines.withTimeoutOrNull(10_000) {
            graph.extensionManager.availableExtensionsFlow.first { it.isNotEmpty() }
        }.orEmpty()
        available.sortedBy { it.name }.forEach {
            items.put(JSONObject().put("id", it.pkgName).put("title", "${it.name} · ${it.lang}").put("lang", it.lang))
        }
        send(JSONObject().put("kind", "extensions").put("items", items))
    }

    private suspend fun sourceSearch(request: JSONObject) {
        val source = graph.sourceManager.get(request.getString("source").toLong()) as? CatalogueSource
            ?: error("Source is unavailable")
        val query = request.optString("query")
        val page = request.optInt("page", 1).coerceAtLeast(1)
        val result = if (query.isBlank()) source.getPopularManga(page) else source.getSearchManga(page, query, source.getFilterList())
        val items = JSONArray()
        graph.networkToLocalManga(result.mangas.map { it.toDomainManga(source.id) }).forEach {
            items.put(JSONObject().put("id", it.id.toString()).put("title", it.title))
        }
        send(
            JSONObject().put("kind", "source_results").put("source", source.id.toString()).put("page", page)
                .put("more", result.hasNextPage).put("items", items),
        )
    }

    private suspend fun details(mangaId: Long) {
        var manga = graph.getManga.await(mangaId) ?: error("Manga no longer exists")
        graph.updateMangaFromRemote(manga, fetchDetails = true, fetchChapters = true).getOrThrow()
        manga = graph.getManga.await(mangaId) ?: return
        send(
            JSONObject().put("kind", "details").put("manga", mangaId.toString()).put("title", manga.title)
                .put("description", manga.description.orEmpty()).put("favorite", manga.favorite),
        )
        chapters(mangaId)
        cover(mangaId)
    }

    private suspend fun library() {
        val entries = graph.getLibraryManga.await().sortedBy { it.manga.title.lowercase() }
        val items = JSONArray()
        entries.forEach {
            items.put(
                JSONObject().put("id", it.id.toString()).put("title", it.manga.title)
                    .put("favorite", it.manga.favorite).put("last_read", it.lastRead)
                    .put("added", it.manga.dateAdded).put("chapters", it.totalChapters)
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
        val chapters = graph.getChaptersByMangaId.await(mangaId).sortedByDescending { it.sourceOrder }
        val history = graph.getHistory.await(mangaId)
        val resume = history.filter { it.readAt != null && chapters.any { chapter -> chapter.id == it.chapterId } }
            .maxByOrNull { it.readAt?.time ?: 0L }?.chapterId
            ?: chapters.firstOrNull { it.lastPageRead > 0 && !it.read }?.id
        val items = JSONArray()
        chapters.forEach {
            items.put(JSONObject().put("id", it.id.toString()).put("title", it.name).put("read", it.read))
        }
        send(
            JSONObject().put("kind", "chapters").put("manga", mangaId.toString())
                .put("resume", resume?.toString().orEmpty()).put("items", items),
        )
    }

    private suspend fun open(mangaId: Long, chapterId: Long) {
        val manga = graph.getManga.await(mangaId) ?: error("Manga no longer exists")
        val chapter = graph.getChapter.await(chapterId) ?: error("Chapter no longer exists")
        require(chapter.mangaId == manga.id) { "Chapter does not belong to this manga" }
        reader?.awaitPendingPageSaves()
        val model = withContext(Dispatchers.Main) { host.reader(mangaId, chapterId) }
        if (model.manga == null) {
            model.init(mangaId, chapterId, null).getOrThrow()
        } else if (model.currentChapter?.id != chapterId) {
            model.loadNewChapterFromDialog(chapter)
            withTimeout(60_000) { model.state.first { it.currentChapter?.chapter?.id == chapterId } }
        }
        reader = model
        publishChapter(model)
    }

    private suspend fun publishChapter(model: ReaderViewModel, replaces: String = "") {
        val chapter = model.state.value.currentChapter ?: error("Chapter failed to load")
        val pages = chapter.pages ?: error("Chapter has no pages")
        token = UUID.randomUUID().toString()
        readers[token] = model
        if (replaces.isNotEmpty()) readers.remove(replaces)
        send(
            JSONObject().put("kind", "chapter").put("token", token).put("count", pages.size)
                .put("start", chapter.requestedPage.coerceIn(0, pages.lastIndex))
                .put("rtl", ReadingMode.fromPreference(model.getMangaReadingMode()) == ReadingMode.RIGHT_TO_LEFT)
                .put("vertical", ReadingMode.fromPreference(model.getMangaReadingMode()) in listOf(ReadingMode.WEBTOON, ReadingMode.CONTINUOUS_VERTICAL))
                .put("replaces", replaces)
                .put("title", "${model.manga?.title} · ${chapter.chapter.name}"),
        )
    }

    private suspend fun page(requestToken: String, index: Int) {
        val chapter = readers[requestToken]?.state?.value?.currentChapter ?: return
        val pages = chapter.pages ?: return
        val page = pages.getOrNull(index) ?: return
        val loader = chapter.pageLoader ?: return
        val key = "$requestToken-$index"
        if (pageJobs.containsKey(key)) return
        coroutineScope {
            val job = launch(start = CoroutineStart.LAZY) {
                val file = File(session, "$key.png")
                val dimensions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                val metadata = File(session, "$key.json")
                var strips = JSONArray()
                if (!file.isFile) {
                    val load = launch { loader.loadPage(page) }
                    try {
                        val state = withTimeout(60_000) { page.statusFlow.first { it == Page.State.Ready || it is Page.State.Error } }
                        check(state == Page.State.Ready) { "Page ${index + 1} failed to load" }
                        val stream = page.stream ?: error("Page image is unavailable")
                        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                        stream().use { BitmapFactory.decodeStream(it, null, bounds) }
                        dimensions.outWidth = bounds.outWidth
                        dimensions.outHeight = bounds.outHeight
                        if (bounds.outHeight.toFloat() / bounds.outWidth.coerceAtLeast(1) > 2.2f) {
                            // Decode width-preserving strips instead of shrinking a tall
                            // chapter to fit one GPU texture and destroying legibility.
                            stream().use { input ->
                                val decoder = BitmapRegionDecoder.newInstance(input, false)
                                    ?: error("Unable to decode tall page")
                                try {
                                    var stripSample = 1
                                    while (bounds.outWidth / stripSample > 1440) stripSample *= 2
                                    val stripHeight = 3072 * stripSample
                                    for (top in 0 until bounds.outHeight step stripHeight) {
                                        val bottom = (top + stripHeight).coerceAtMost(bounds.outHeight)
                                        val stripFile = File(session, "$key-strip-$top.png")
                                        val strip = decoder.decodeRegion(Rect(0, top, bounds.outWidth, bottom), BitmapFactory.Options().apply { inSampleSize = stripSample })
                                            ?: error("Unable to decode page strip")
                                        try {
                                            stripFile.outputStream().use { check(strip.compress(Bitmap.CompressFormat.PNG, 100, it)) }
                                        } finally {
                                            strip.recycle()
                                        }
                                        strips.put(JSONObject().put("path", stripFile.absolutePath).put("top", top).put("height", bottom - top))
                                    }
                                } finally {
                                    decoder.recycle()
                                }
                            }
                        }
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
                    metadata.writeText(JSONObject().put("width", dimensions.outWidth).put("height", dimensions.outHeight).put("strips", strips).toString())
                } else if (metadata.isFile) {
                    val saved = JSONObject(metadata.readText())
                    dimensions.outWidth = saved.getInt("width")
                    dimensions.outHeight = saved.getInt("height")
                    strips = saved.getJSONArray("strips")
                }
                if (dimensions.outWidth <= 0) {
                    BitmapFactory.decodeFile(file.absolutePath, dimensions)
                }
                if (readers.containsKey(requestToken)) {
                    send(
                        JSONObject().put("kind", "page").put("token", requestToken).put("index", index).put("path", file.absolutePath)
                            .put("width", dimensions.outWidth).put("height", dimensions.outHeight).put("strips", strips),
                    )
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
        val model = readers[requestToken] ?: return
        val chapter = model.state.value.currentChapter ?: return
        val page = chapter.pages?.getOrNull(index) ?: return
        withContext(Dispatchers.Main) {
            if (readers.containsKey(requestToken)) model.onPageSelected(page, chapter.displayNumber(page).toString(), false)
        }
        model.awaitPendingPageSaves()
        // Disk cache is bounded to neighboring spreads; original images remain in Houri's caches.
        session.listFiles()?.filter { it.name.startsWith(requestToken) }?.forEach {
            val cached = it.name.removePrefix("$requestToken-").substringBefore('-').substringBefore('.').toIntOrNull()
            if (cached != null && kotlin.math.abs(cached - index) > 6 && !pageJobs.containsKey(it.nameWithoutExtension)) it.delete()
        }
    }

    fun close() {
        pageJobs.values.forEach { it.cancel() }
        pageJobs.clear()
        session.deleteRecursively()
    }

    suspend fun flushProgress() = navigation.withLock { readers.values.toSet().forEach { it.awaitPendingPageSaves() } }
}
// KMK <--
