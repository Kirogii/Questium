package tachiyomi.domain.chapter.service

import tachiyomi.domain.chapter.model.Chapter
import kotlin.math.roundToInt

/**
 * Cap on the scanlator half of a blacklist key. The name comes from a source and a backup can
 * carry anything, so an unbounded one would let a corrupt or hostile list bloat the persisted
 * value and every comparison made against it.
 */
private const val MAX_KEY_SCANLATOR_LEN = 64

/**
 * Identifies one chapter of one scanlator inside [tachiyomi.domain.manga.model.Manga.blacklistedChapters],
 * as `"<chapterNumber>@<scanlator>"`.
 *
 * Lives in domain rather than alongside the merge helpers because the blacklist gates more than
 * the chapter list: it also has to be honoured by anything acting on a series' chapters, and
 * several of those are domain interactors.
 */
fun scanlatorBlacklistKey(chapterNumber: Double, scanlator: String?): String {
    // Round to 2 decimals so float artifacts (1.5000000000000002) don't leak into the stored key.
    val rounded = (chapterNumber * 100).roundToInt() / 100.0
    // A scanlator name is display text that arrives from a source, so it can carry stray
    // whitespace. Two entries differing only by it would blacklist different things.
    val name = scanlator.orEmpty().trim().take(MAX_KEY_SCANLATOR_LEN)
    return "$rounded@$name"
}

/**
 * Whether [chapter] is covered by [blacklist], the per-manga list of [scanlatorBlacklistKey]s.
 *
 * Every surface that shows or acts on a series' chapters must ask this rather than testing
 * membership of a raw key, so the key format has exactly one definition and callers cannot drift
 * apart from it.
 *
 * Deliberately not case-folding. Keys are already persisted per manga, so changing the format
 * would silently un-blacklist every entry a user has.
 */
fun isChapterBlacklisted(chapter: Chapter, blacklist: Collection<String>): Boolean {
    if (blacklist.isEmpty()) return false
    return scanlatorBlacklistKey(chapter.chapterNumber, chapter.scanlator) in blacklist
}
