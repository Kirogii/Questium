package tachiyomi.domain.chapter.interactor

import dev.zacsweers.metro.Inject
import tachiyomi.domain.chapter.model.Chapter
import tachiyomi.domain.chapter.service.isChapterBlacklisted
import tachiyomi.domain.manga.interactor.GetManga

/**
 * Drops the chapters a manga's [tachiyomi.domain.manga.model.Manga.blacklistedChapters] covers.
 *
 * Blacklisting is per series and keyed by scanlator, so it cannot be expressed in the chapter
 * queries the way excluded scanlators and bookmark filters are - it needs the manga row. Callers
 * that already hold a [tachiyomi.domain.manga.model.Manga] should call
 * [isChapterBlacklisted] directly rather than paying for the lookup here.
 *
 * Only for surfaces where a blacklisted chapter genuinely must not appear. Anything that needs
 * the whole truth must skip this: chapter sync, backup restore, migration, and the screen that
 * lets a user lift a blacklist all have to see blacklisted chapters.
 */
@Inject
class FilterBlacklistedChapters(
    private val getManga: GetManga,
) {

    /** [chapters] minus the blacklisted ones. */
    suspend fun await(mangaId: Long, chapters: List<Chapter>): List<Chapter> {
        if (chapters.isEmpty()) return chapters
        val blacklist = getManga.await(mangaId)?.blacklistedChapters.orEmpty()
        if (blacklist.isEmpty()) return chapters
        return chapters.filterNot { isChapterBlacklisted(it, blacklist) }
    }
}
