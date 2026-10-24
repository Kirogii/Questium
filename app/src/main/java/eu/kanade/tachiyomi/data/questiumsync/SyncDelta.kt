package eu.kanade.tachiyomi.data.questiumsync

// KMK -->
import eu.kanade.tachiyomi.data.backup.models.Backup
import eu.kanade.tachiyomi.data.backup.models.BackupChapter
import eu.kanade.tachiyomi.data.backup.models.BackupManga
import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class SyncTransfer(
    val revision: String,
    val base: String = "",
    val library: SyncLibrary,
    val deletedBooks: Set<String> = emptySet(),
    val deletedChapters: Map<String, Set<String>> = emptyMap(),
    val deletedHistory: Map<String, Set<String>> = emptyMap(),
)

@Serializable
data class SyncBaseline(val revision: String, val library: SyncLibrary)

@Serializable
data class SyncJournal(
    val incoming: SyncBaseline? = null,
    val outgoing: SyncBaseline? = null,
    val pending: SyncBaseline? = null,
) {
    fun applied(baseline: SyncBaseline): SyncJournal = copy(incoming = baseline, outgoing = baseline, pending = null)

    fun acknowledge(revision: String): SyncJournal =
        if (pending?.revision == revision) copy(outgoing = pending, pending = null) else this
}

/** Deltas replace changed progress, rather than merging it, so explicit reverts survive. */
object SyncDelta {
    fun mangaJson(manga: BackupManga): String = SyncWire.json.encodeToString(BackupManga.serializer(), manga)

    private fun clone(manga: BackupManga): BackupManga = SyncWire.json.decodeFromString(BackupManga.serializer(), mangaJson(manga))

    fun encode(current: SyncLibrary, previous: SyncBaseline?, revision: String = UUID.randomUUID().toString()): SyncTransfer {
        if (previous == null) return SyncTransfer(revision, library = current)
        val old = previous.library.backup.backupManga.associateBy(SyncMerge::key)
        val removedChapters = mutableMapOf<String, Set<String>>()
        val removedHistory = mutableMapOf<String, Set<String>>()
        val changed = current.backup.backupManga.mapNotNull { manga ->
            val key = SyncMerge.key(manga)
            val before = old[key] ?: return@mapNotNull manga
            if (mangaJson(before) == mangaJson(manga)) return@mapNotNull null
            val beforeChapters = before.chapters.associateBy { it.url }
            val beforeHistory = before.history.associateBy { it.url }
            val chapterUrls = manga.chapters.map { it.url }.toSet()
            val historyUrls = manga.history.map { it.url }.toSet()
            (beforeChapters.keys - chapterUrls).takeIf { it.isNotEmpty() }?.let { removedChapters[key] = it }
            (beforeHistory.keys - historyUrls).takeIf { it.isNotEmpty() }?.let { removedHistory[key] = it }
            clone(manga).apply {
                chapters = chapters.filter { chapter ->
                    val previousChapter = beforeChapters[chapter.url]
                    previousChapter == null || SyncWire.json.encodeToString(BackupChapter.serializer(), chapter) !=
                        SyncWire.json.encodeToString(BackupChapter.serializer(), previousChapter)
                }
                history = history.filter { it != beforeHistory[it.url] }
            }
        }
        return SyncTransfer(
            revision,
            previous.revision,
            current.copy(backup = Backup(changed, backupExtensionStores = current.backup.backupExtensionStores)),
            old.keys - current.backup.backupManga.map(SyncMerge::key).toSet(),
            removedChapters,
            removedHistory,
        )
    }

    fun decode(transfer: SyncTransfer, previous: SyncBaseline?): SyncBaseline {
        if (transfer.base.isEmpty()) return SyncBaseline(transfer.revision, transfer.library)
        require(previous?.revision == transfer.base) { "Sync baseline changed; a full snapshot is required" }
        val books = previous!!.library.backup.backupManga.associate { SyncMerge.key(it) to clone(it) }.toMutableMap()
        transfer.deletedBooks.forEach(books::remove)
        transfer.library.backup.backupManga.forEach { patch ->
            val key = SyncMerge.key(patch)
            val old = books[key]
            books[key] = clone(patch).apply {
                if (old != null) {
                    chapters = (
                        old.chapters.filterNot { it.url in transfer.deletedChapters[key].orEmpty() }.associateBy { it.url } +
                            chapters.associateBy { it.url }
                        ).values.toList()
                    history = (
                        old.history.filterNot { it.url in transfer.deletedHistory[key].orEmpty() }.associateBy { it.url } +
                            history.associateBy { it.url }
                        ).values.toList()
                }
            }
        }
        return SyncBaseline(transfer.revision, transfer.library.copy(backup = Backup(books.values.toList(), backupExtensionStores = transfer.library.backup.backupExtensionStores)))
    }
}
// KMK <--
