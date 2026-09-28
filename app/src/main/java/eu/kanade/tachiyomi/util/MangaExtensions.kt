package eu.kanade.tachiyomi.util

import eu.kanade.domain.manga.interactor.UpdateManga
import eu.kanade.domain.manga.model.toSManga
import eu.kanade.tachiyomi.data.cache.CoverCache
import mihon.app.di.globalAppGraph
import tachiyomi.domain.manga.model.Manga
import tachiyomi.source.local.image.LocalCoverManager
import tachiyomi.source.local.isLocal
import java.io.InputStream
import java.time.Instant

fun Manga.removeCovers(coverCache: CoverCache = globalAppGraph.coverCache): Manga {
    if (isLocal()) return this
    return if (coverCache.deleteFromCache(this, true) > 0) {
        copy(coverLastModified = Instant.now().toEpochMilli())
    } else {
        this
    }
}

suspend fun Manga.editCover(
    coverManager: LocalCoverManager,
    stream: InputStream,
    updateManga: UpdateManga = globalAppGraph.updateManga,
    coverCache: CoverCache = globalAppGraph.coverCache,
) {
    if (isLocal()) {
        coverManager.update(toSManga(), stream)
        updateManga.awaitUpdateCoverLastModified(id)
    } else if (favorite) {
        coverCache.setCustomCoverToCache(this, stream)
        updateManga.awaitUpdateCoverLastModified(id)
        // KMK --> After the write, and only on the cached-custom-cover branch, so this counts
        // covers the user actually set rather than every cover save.
        runCatching { mihon.app.di.globalAppGraph.achievementManager.incrementCounter("custom_covers") }
        // KMK <--
    }
}
