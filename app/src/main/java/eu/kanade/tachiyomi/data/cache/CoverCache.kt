package eu.kanade.tachiyomi.data.cache

import android.content.Context
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import eu.kanade.tachiyomi.util.storage.DiskUtil
import tachiyomi.domain.manga.model.Manga
import java.io.File
import java.io.IOException
import java.io.InputStream

/**
 * Class used to create cover cache.
 * It is used to store the covers of the library.
 * Names of files are created with the md5 of the thumbnail URL.
 *
 * @param context the application context.
 * @constructor creates an instance of the cover cache.
 */
@Inject
@SingleIn(AppScope::class)
class CoverCache(private val context: Context) {

    companion object {
        private const val COVERS_DIR = "covers"
        private const val CUSTOM_COVERS_DIR = "covers/custom"
    }

    /**
     * Cache directory used for cache management.
     */
    private val cacheDir = getCacheDir(COVERS_DIR)

    private val customCoverCacheDir = getCacheDir(CUSTOM_COVERS_DIR)

    /**
     * Returns the cover from cache.
     *
     * @param mangaThumbnailUrl thumbnail url for the manga.
     * @return cover image.
     */
    fun getCoverFile(mangaThumbnailUrl: String?): File? {
        return mangaThumbnailUrl?.let {
            File(cacheDir, DiskUtil.hashKeyForDisk(it))
        }
    }

    /**
     * Returns the custom cover from cache.
     *
     * @param mangaId the manga id.
     * @return cover image.
     */
    fun getCustomCoverFile(mangaId: Long?): File {
        return File(customCoverCacheDir, DiskUtil.hashKeyForDisk(mangaId.toString()))
    }

    /**
     * Saves the given stream as the manga's custom cover to cache.
     *
     * @param manga the manga.
     * @param inputStream the stream to copy.
     * @throws IOException if there's any error.
     */
    @Throws(IOException::class)
    fun setCustomCoverToCache(manga: Manga, inputStream: InputStream) {
        getCustomCoverFile(manga.id).outputStream().use {
            inputStream.copyTo(it)
        }
    }

    /**
     * Delete the cover files of the manga from the cache.
     *
     * Not what a library removal wants any more - see [hasRetainedCover]. Kept for the paths that
     * genuinely mean "this image should not be on disk", such as a source replacing a cover URL.
     *
     * @param manga the manga.
     * @param deleteCustomCover whether the custom cover should be deleted.
     * @return number of files that were deleted.
     */
    fun deleteFromCache(manga: Manga, deleteCustomCover: Boolean = false): Int {
        var deleted = 0

        getCoverFile(manga.thumbnailUrl)?.let {
            if (it.exists() && it.delete()) ++deleted
        }

        if (deleteCustomCover) {
            if (deleteCustomCover(manga.id)) ++deleted
        }

        return deleted
    }

    /**
     * Whether a cover for [manga] is on disk, whether or not it is still in the library.
     *
     * Used on removal to decide whether anything is worth keeping, and whether the caller needs to
     * bump `coverLastModified` so a visible cover redraws.
     */
    fun hasRetainedCover(manga: Manga): Boolean =
        getCoverFile(manga.thumbnailUrl)?.exists() == true || getCustomCoverFile(manga.id).exists()

    /** Cache key a library cover is stored under, for handing to [pruneOrphanedCovers]. */
    fun libraryCoverKey(manga: Manga): String? = manga.thumbnailUrl?.let { DiskUtil.hashKeyForDisk(it) }

    /** Cache key a custom cover is stored under, for handing to [pruneOrphanedCovers]. */
    fun customCoverKey(mangaId: Long): String = DiskUtil.hashKeyForDisk(mangaId.toString())

    /**
     * Deletes covers that are both older than [retentionMillis] and named in neither [referencedKeys]
     * nor anything the library still points at.
     *
     * The membership test is the whole point. Age alone cannot tell an orphan from a cover that has
     * simply been on disk for months, and pruning by age would quietly re-download the library's own
     * covers. [referencedKeys] is built from the library by the caller, which is the only place that
     * knows it.
     *
     * @return how many files were deleted.
     */
    fun pruneOrphanedCovers(referencedKeys: Set<String>, retentionMillis: Long): Int {
        val cutoff = System.currentTimeMillis() - retentionMillis
        var deleted = 0

        // The custom directory is nested inside the library one, so it is walked separately: a
        // custom cover is keyed by manga id rather than by URL and would never appear in the
        // library directory anyway, but listing the parent would walk it a second time.
        cacheDir.listFiles()?.forEach { file ->
            if (!file.isFile || file.name in referencedKeys) return@forEach
            if (file.lastModified() >= cutoff) return@forEach
            if (file.delete()) deleted++
        }
        customCoverCacheDir.listFiles()?.forEach { file ->
            if (!file.isFile || file.name in referencedKeys) return@forEach
            if (file.lastModified() >= cutoff) return@forEach
            if (file.delete()) deleted++
        }

        return deleted
    }

    /**
     * Delete custom cover of the manga from the cache
     *
     * @param mangaId the manga id.
     * @return whether the cover was deleted.
     */
    fun deleteCustomCover(mangaId: Long?): Boolean {
        return getCustomCoverFile(mangaId).let {
            it.exists() && it.delete()
        }
    }

    private fun getCacheDir(dir: String): File {
        return context.getExternalFilesDir(dir)
            ?: File(context.filesDir, dir).also { it.mkdirs() }
    }
}
