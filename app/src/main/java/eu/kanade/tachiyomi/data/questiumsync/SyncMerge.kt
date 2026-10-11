package eu.kanade.tachiyomi.data.questiumsync

// KMK -->
import eu.kanade.tachiyomi.data.backup.models.Backup
import eu.kanade.tachiyomi.data.backup.models.BackupChapter
import eu.kanade.tachiyomi.data.backup.models.BackupHistory
import eu.kanade.tachiyomi.data.backup.models.BackupManga
import kotlinx.serialization.Serializable

@Serializable
data class SyncLibrary(val backup: Backup, val epochs: Map<String, Long> = emptyMap(), val removed: Set<String> = emptySet())

@Serializable
data class ChapterProgress(val url: String, val read: Boolean, val page: Long)

@Serializable
data class ProgressChange(
    val id: String,
    val mangaKey: String,
    val title: String,
    val time: Long,
    val before: List<ChapterProgress>,
    val from: Float,
    val to: Float,
    val reverted: Boolean = false,
    val history: List<BackupHistory> = emptyList(),
)

/** Main-device metadata wins; a deliberate revert starts a new progress epoch. */
object SyncMerge {
    fun key(manga: BackupManga) = "${manga.source}|${manga.url}"

    fun progress(manga: BackupManga) = manga.chapters.map { ChapterProgress(it.url, it.read, it.lastPageRead) }

    fun latestHistory(manga: BackupManga) = manga.history.filter { it.lastRead > 0 }.maxByOrNull { it.lastRead }

    fun resume(manga: BackupManga): Float = manga.chapters.firstOrNull { it.url == latestHistory(manga)?.url }?.chapterNumber ?: highest(manga)

    private fun progressedChapters(manga: BackupManga): List<BackupChapter> {
        val visited = manga.history.filter { it.lastRead > 0 }.map { it.url }.toHashSet()
        return manga.chapters.filter { it.read || it.lastPageRead > 0 || it.url in visited }
    }

    fun highest(manga: BackupManga): Float = progressedChapters(manga)
        .maxOfOrNull { it.chapterNumber.takeIf(Float::isFinite) ?: 0f } ?: 0f

    fun advanced(before: List<ChapterProgress>, after: List<ChapterProgress>): Boolean {
        val previous = before.associateBy { it.url }
        return after.any { chapter ->
            val old = previous[chapter.url]
            (chapter.read && old?.read != true) || chapter.page > (old?.page ?: 0L)
        }
    }

    fun merge(main: SyncLibrary, others: List<SyncLibrary>): SyncLibrary {
        val mangaByKey = main.backup.backupManga.associate { key(it) to clone(it) }.toMutableMap()
        others.forEach { other ->
            other.backup.backupManga.forEach { incoming ->
                val key = key(incoming)
                if (key in main.removed) return@forEach
                val existing = mangaByKey[key]
                if (existing == null) {
                    // Category IDs belong to a database, so never import another device's IDs.
                    mangaByKey[key] = clone(incoming).apply {
                        categoryIds = emptyList()
                        categories = emptyList()
                    }
                } else if ((other.epochs[key] ?: 0L) == (main.epochs[key] ?: 0L)) {
                    existing.chapters = mergeChapters(existing.chapters, incoming.chapters)
                    existing.history = (existing.history + incoming.history).groupBy { it.url }
                        .values.map { versions -> versions.maxBy { it.lastRead } }
                }
            }
        }
        val original = main.backup.backupManga.associateBy(::key)
        mangaByKey.values.forEach { manga ->
            val before = original[key(manga)]
            if (before == null || advanced(progress(before), progress(manga)) || highest(manga) > highest(before)) {
                // A newer clock on an earlier chapter must not make Resume go backwards.
                val furthest = progressedChapters(manga).maxByOrNull { it.chapterNumber }
                if (furthest != null && latestHistory(manga)?.url != furthest.url) {
                    val time = maxOf(System.currentTimeMillis(), (manga.history.maxOfOrNull { it.lastRead } ?: 0L).coerceAtMost(Long.MAX_VALUE - 1) + 1)
                    val prior = manga.history.firstOrNull { it.url == furthest.url }
                    manga.history = manga.history.filterNot { it.url == furthest.url } + BackupHistory(furthest.url, time, prior?.readDuration ?: 0)
                }
            }
        }
        return SyncLibrary(
            main.backup.copy(
                backupManga = mangaByKey.values.toList(),
                backupSources = (main.backup.backupSources + others.flatMap { it.backup.backupSources }).distinctBy { it.sourceId },
                backupExtensionStores = (main.backup.backupExtensionStores + others.flatMap { it.backup.backupExtensionStores }).distinctBy { it.indexUrl },
            ),
            main.epochs,
            main.removed,
        )
    }

    private fun clone(manga: BackupManga): BackupManga = SyncWire.json.decodeFromString(
        BackupManga.serializer(),
        SyncWire.json.encodeToString(BackupManga.serializer(), manga),
    )

    private fun mergeChapters(main: List<BackupChapter>, incoming: List<BackupChapter>): List<BackupChapter> {
        val result = main.associateBy { it.url }.toMutableMap()
        incoming.forEach { chapter ->
            val existing = result[chapter.url]
            if (existing == null) {
                result[chapter.url] = SyncWire.json.decodeFromString(BackupChapter.serializer(), SyncWire.json.encodeToString(BackupChapter.serializer(), chapter))
            } else {
                existing.read = existing.read || chapter.read
                existing.lastPageRead = maxOf(existing.lastPageRead, chapter.lastPageRead)
            }
        }
        return result.values.toList()
    }
}
// KMK <--
