package tachiyomi.data.manga

import android.content.Context
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.ContributesBinding
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import logcat.LogPriority
import mihon.core.concurrency.AppDispatchers
import mihon.core.concurrency.AppDispatchersHolder
import tachiyomi.core.common.util.system.logcat
import tachiyomi.data.Custom_manga_info
import tachiyomi.data.Database
import tachiyomi.data.DatabaseHandler
import tachiyomi.domain.manga.model.CustomMangaInfo
import tachiyomi.domain.manga.repository.CustomMangaRepository
import java.io.File

/**
 * Stores user-edited manga metadata in the `custom_manga_info` table.
 *
 * ## Why this is not a plain SQLDelight query
 *
 * [tachiyomi.domain.manga.model.Manga] snapshots its custom info in a `@Transient`
 * property initialiser so that every reader of a `Manga` - library paging, updates,
 * history, feeds, backups, Discord presence - sees the edited title without threading
 * a repository through all of them. That initialiser is synchronous and can run on the
 * db reader pool, the main thread, or inside a mapper, so reads have to be a plain map
 * lookup. This class therefore keeps a process-wide cache in front of the table: a write
 * updates the cache synchronously (so the edit is visible in the very next `Manga` the UI
 * builds) and is then flushed to SQLite in order by a single writer.
 *
 * ## Why writes are queued instead of executed inline
 *
 * Callers include `LibraryScreenModel.cleanTitles` / `resetInfo`, which write one row per
 * selected entry. The file-backed predecessor rewrote the entire JSON document on the
 * calling thread for each of those. A single-consumer channel keeps the writes strictly
 * ordered (last write wins, no interleaving between two edits of the same entry) and off
 * the caller's thread.
 *
 * ## Legacy import
 *
 * Before this existed, edits lived in `<external files>/edits.json` - outside the
 * database, so they were dropped on uninstall, missing from db exports, and invisible to
 * the backup integrity machinery. [migrateLegacyFile] imports that file once on first
 * construction - during `App.onCreate` - and *renames* it rather than deleting it, so an
 * import that could not be completed is retried on the next launch instead of silently
 * destroying the user's edits.
 */
@Inject
@SingleIn(AppScope::class)
@ContributesBinding(AppScope::class)
class CustomMangaRepositoryImpl(
    context: Context,
    private val handler: DatabaseHandler,
    database: Database,
    appDispatchers: AppDispatchers = AppDispatchersHolder.get(),
) : CustomMangaRepository {

    private val scope = CoroutineScope(SupervisorJob() + appDispatchers.io)

    /**
     * `<external files>` can be null while external storage is unmounted, in which case
     * there is simply no legacy file to import - the database is then the only source.
     */
    private val legacyFile: File? = context.getExternalFilesDir(null)?.let { File(it, LEGACY_FILE_NAME) }

    private val cache = MutableStateFlow(readCache(database))

    private val _changes = MutableSharedFlow<Unit>(
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    override val changes: SharedFlow<Unit> = _changes.asSharedFlow()

    /** Unbounded, single consumer: preserves write order without ever dropping an edit. */
    private val pendingWrites = Channel<CustomMangaInfo>(Channel.UNLIMITED)

    init {
        migrateLegacyFile(database)
        scope.launch {
            for (info in pendingWrites) {
                runCatching { persist(info) }.onFailure {
                    this@CustomMangaRepositoryImpl.logcat(LogPriority.ERROR, it) {
                        "Failed to save manga info edit for ${info.id}"
                    }
                }
            }
        }
    }

    override fun get(mangaId: Long): CustomMangaInfo? = cache.value[mangaId]

    override fun set(mangaInfo: CustomMangaInfo) {
        if (mangaInfo.isEmpty()) {
            cache.value = cache.value - mangaInfo.id
        } else {
            cache.value = cache.value + (mangaInfo.id to mangaInfo)
        }
        pendingWrites.trySend(mangaInfo)
        _changes.tryEmit(Unit)
    }

    private suspend fun persist(mangaInfo: CustomMangaInfo) {
        handler.await(inTransaction = true) {
            if (mangaInfo.isEmpty()) {
                custom_manga_infoQueries.deleteByMangaId(mangaInfo.id)
            } else {
                custom_manga_infoQueries.upsert(
                    mangaId = mangaInfo.id,
                    title = mangaInfo.title,
                    author = mangaInfo.author,
                    artist = mangaInfo.artist,
                    thumbnailUrl = mangaInfo.thumbnailUrl,
                    description = mangaInfo.description,
                    genre = mangaInfo.genre,
                    status = mangaInfo.status,
                )
            }
        }
    }

    /**
     * Reads the whole table straight off the driver rather than through [DatabaseHandler]:
     * the constructor cannot suspend and the cache has to be populated before the first
     * `Manga` is constructed.
     */
    private fun readCache(database: Database): Map<Long, CustomMangaInfo> = runCatching {
        database.custom_manga_infoQueries.selectAll()
            .executeAsList()
            .associate { row -> row.manga_id to row.toCustomMangaInfo() }
    }.onFailure {
        logcat(LogPriority.ERROR, it) { "Failed to load manga info edits" }
    }.getOrDefault(emptyMap())

    /**
     * Imports the pre-migration `edits.json` exactly once.
     *
     * Rows whose manga no longer exists are rejected by the foreign key, which is the
     * right outcome: an edit with no entry to attach to can only ever be wrong. Existing
     * rows win over file rows because a restored backup may already hold newer edits.
     * The file is only renamed away once every row has been offered to the database, and
     * that rename is what makes the import idempotent.
     */
    private fun migrateLegacyFile(database: Database) {
        val file = legacyFile?.takeIf { it.isFile } ?: return

        val legacy = runCatching {
            Json { ignoreUnknownKeys = true }.decodeFromString<LegacyMangaList>(
                file.bufferedReader().use { it.readText() },
            )
        }.onFailure {
            logcat(LogPriority.ERROR, it) { "Could not parse legacy manga info edits" }
        }.getOrNull()

        val rows = legacy?.mangas.orEmpty().mapNotNull { it.toCustomMangaInfoOrNull() }
        if (rows.isEmpty()) {
            // Nothing worth importing; still retire the file so it is not re-read forever.
            retireLegacyFile(file)
            return
        }

        // Bound to a local because the lambda receiver of transactionWithResult is the
        // transaction, not the queries object, so unqualified query names would not resolve.
        val queries = database.custom_manga_infoQueries
        runCatching {
            queries.transactionWithResult {
                rows.forEach { info ->
                    if (queries.selectByMangaId(info.id).executeAsOneOrNull() == null) {
                        queries.upsert(
                            mangaId = info.id,
                            title = info.title,
                            author = info.author,
                            artist = info.artist,
                            thumbnailUrl = info.thumbnailUrl,
                            description = info.description,
                            genre = info.genre,
                            status = info.status,
                        )
                    }
                }
            }
        }.onSuccess {
            cache.value = cache.value + rows.associateBy { it.id }
            retireLegacyFile(file)
            _changes.tryEmit(Unit)
        }.onFailure {
            // Leave the file in place so the import is retried on the next launch.
            logcat(LogPriority.ERROR, it) { "Failed to import legacy manga info edits" }
        }
    }

    private fun retireLegacyFile(file: File) {
        runCatching {
            file.renameTo(File(file.parentFile, "$LEGACY_FILE_NAME.imported"))
        }.onFailure {
            logcat(LogPriority.ERROR, it) { "Failed to retire legacy manga info edits" }
        }
    }

    /** True when the edit carries no deviation from the source, i.e. it should not exist. */
    private fun CustomMangaInfo.isEmpty(): Boolean =
        title == null &&
            author == null &&
            artist == null &&
            thumbnailUrl == null &&
            description == null &&
            genre == null &&
            status == null

    private companion object {
        const val LEGACY_FILE_NAME = "edits.json"
    }
}

internal fun Custom_manga_info.toCustomMangaInfo(): CustomMangaInfo = CustomMangaInfo(
    id = manga_id,
    title = title?.takeUnless { it.isBlank() },
    author = author?.takeUnless { it.isBlank() },
    artist = artist?.takeUnless { it.isBlank() },
    thumbnailUrl = thumbnail_url?.takeUnless { it.isBlank() },
    description = description?.takeUnless { it.isBlank() },
    genre = genre,
    status = status,
)

/**
 * The pre-migration `edits.json` payload.
 *
 * Blank strings and a zero status are how the file encoded "not set": the writer only
 * emitted nulls for absent fields, but a reader still has to tolerate a blank title (an
 * emptied edit dialog) and treat status 0 as "unchanged" because it is `SManga.UNKNOWN`.
 */
@Serializable
internal data class LegacyMangaList(
    val mangas: List<LegacyMangaJson>? = null,
)

@Serializable
internal data class LegacyMangaJson(
    val id: Long? = null,
    val title: String? = null,
    val author: String? = null,
    val artist: String? = null,
    val thumbnailUrl: String? = null,
    val description: String? = null,
    val genre: List<String>? = null,
    val status: Long? = null,
)

internal fun LegacyMangaJson.toCustomMangaInfoOrNull(): CustomMangaInfo? {
    val mangaId = id ?: return null
    return CustomMangaInfo(
        id = mangaId,
        title = title?.takeUnless { it.isBlank() },
        author = author?.takeUnless { it.isBlank() },
        artist = artist?.takeUnless { it.isBlank() },
        thumbnailUrl = thumbnailUrl?.takeUnless { it.isBlank() },
        description = description?.takeUnless { it.isBlank() },
        genre = genre,
        status = status?.takeUnless { it == 0L },
    )
}
