package eu.kanade.tachiyomi.extension.model

sealed interface LoadResult {
    data class Success(val extension: Extension.Installed) : LoadResult
    data class Untrusted(val extension: Extension.Untrusted) : LoadResult

    /**
     * Identity is carried alongside the reason so a failure can be shown against its extension and
     * reported to the right repository; the reason on its own could not be attributed to anything.
     */
    data class Error(
        val reason: String? = null,
        val pkgName: String? = null,
        val extensionName: String? = null,
        val versionName: String? = null,
        val versionCode: Long = 0L,
        val signatureHash: String? = null,
        val storeName: String? = null,
    ) : LoadResult
}
