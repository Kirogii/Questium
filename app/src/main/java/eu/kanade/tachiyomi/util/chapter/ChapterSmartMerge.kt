package eu.kanade.tachiyomi.util.chapter

import tachiyomi.domain.chapter.model.Chapter
import kotlin.math.roundToInt

/**
 * Cap on the scanlator half of a blacklist key. The name comes from a source and a backup can
 * carry anything, so an unbounded one would let a corrupt or hostile list bloat the prefs value
 * and every comparison made against it.
 */
private const val MAX_KEY_SCANLATOR_LEN = 64

fun scanlatorBlacklistKey(chapterNumber: Double, scanlator: String?): String {
    // Round to 2 decimals so float artifacts (1.5000000000000002) don't leak into the panel.
    val rounded = (chapterNumber * 100).roundToInt() / 100.0
    // A scanlator name is display text that arrives from a source, so it can carry stray
    // whitespace. Two entries that differ only by it would blacklist different things.
    val name = scanlator.orEmpty().trim().take(MAX_KEY_SCANLATOR_LEN)
    return "$rounded@$name"
}

/**
 * Whether [chapter] is covered by [blacklist], which is the per-manga list of
 * [scanlatorBlacklistKey]s.
 *
 * Every place that shows or acts on a series' chapters must ask this rather than testing
 * membership of the raw key itself, so the key format has exactly one definition and callers
 * cannot drift apart from it. Deliberately not case-folding: keys are already persisted per
 * manga, so changing the format would silently un-blacklist every entry a user has.
 */
fun isChapterBlacklisted(chapter: Chapter, blacklist: Collection<String>): Boolean {
    if (blacklist.isEmpty()) return false
    return scanlatorBlacklistKey(chapter.chapterNumber, chapter.scanlator) in blacklist
}

/**
 * A rule pinning one scanlator over a span of chapter numbers, stored encoded as
 * "from:to:scanlator" inside [tachiyomi.domain.manga.model.Manga.scanlatorRangeRules].
 */
data class ScanlatorRangeRule(
    val from: Double,
    val to: Double,
    val scanlator: String,
) {
    fun covers(chapterNumber: Double): Boolean = chapterNumber >= from && chapterNumber <= to
}

fun encodeScanlatorRangeRule(rule: ScanlatorRangeRule): String = "${rule.from}:${rule.to}:${rule.scanlator}"

fun parseScanlatorRangeRule(raw: String): ScanlatorRangeRule? {
    val parts = raw.split(':', limit = 3)
    if (parts.size != 3) return null
    val from = parts[0].toDoubleOrNull() ?: return null
    val to = parts[1].toDoubleOrNull() ?: return null
    if (from > to) return null
    return ScanlatorRangeRule(from, to, parts[2])
}

/**
 * Smart merge: keeps one chapter per chapter number, preferring scanlators in
 * [priority] order (unknown scanlators sort last, stable by original order).
 * Chapters whose "number@scanlator" key is in [blacklisted] are skipped for
 * that number; a number with no remaining candidates is hidden entirely.
 * Chapters without a positive number are never deduplicated.
 *
 * When [rangeRules] contain a rule covering a number, its scanlator wins for that
 * number regardless of global order; if it has no candidate for the number, the
 * global priority order applies. The last matching rule wins when several overlap.
 */
fun List<Chapter>.applyScanlatorPriority(
    priority: List<String>,
    blacklistedChapters: Set<String>,
    rangeRules: List<String> = emptyList(),
): List<Chapter> {
    if (priority.isEmpty() && blacklistedChapters.isEmpty() && rangeRules.isEmpty()) return this

    val rules = rangeRules.mapNotNull(::parseScanlatorRangeRule)

    val chosenIds = asSequence()
        .filter { it.chapterNumber > 0.0 }
        .groupBy { it.chapterNumber }
        .values
        .mapNotNull { sameNumber ->
            val preferredScanlator = rules.lastOrNull { it.covers(sameNumber.first().chapterNumber) }?.scanlator
            sameNumber
                .filterNot { isChapterBlacklisted(it, blacklistedChapters) }
                .minWithOrNull(
                    compareBy<Chapter> { chapter ->
                        if (chapter.scanlator == preferredScanlator) 0 else 1
                    }.thenBy { candidate ->
                        priority.indexOf(candidate.scanlator)
                            .takeIf { it != -1 }
                            ?: Int.MAX_VALUE
                    },
                )
                ?.id
        }
        .toSet()

    return filter { it.chapterNumber <= 0.0 || it.id in chosenIds }
}
