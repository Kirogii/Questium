package exh.yakuyomi

import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn

/**
 * Which backend will actually service a translation request.
 *
 * The order here is the resolution order: an enabled image service replaces the whole text
 * pipeline, then the on-device Gemini Nano model, then a local GGUF model, then the cloud.
 */
enum class TranslationProviderKind {
    /** Whole-page image translation service; not a text provider. */
    IMAGE_SERVICE,
    GEMINI_NANO,
    LOCAL_GGUF,
    CLOUD,
}

/**
 * The single answer to "who is translating right now", including the identity stamped onto cache
 * entries.
 *
 * [providerName] and [modelName] must be stable for a given configuration: they are part of every
 * page and metadata cache key, so two code paths deriving them differently would read and write
 * the same cache under different names.
 */
data class ActiveTranslationProvider(
    val kind: TranslationProviderKind,
    val providerName: String,
    val modelName: String,
    /** False when the selected provider cannot run yet (e.g. a cloud provider with no API key). */
    val isReady: Boolean,
    val unavailableReason: String? = null,
) {
    val isImageService: Boolean get() = kind == TranslationProviderKind.IMAGE_SERVICE

    /** True for backends that translate text lines, i.e. everything except the image service. */
    val isTextProvider: Boolean get() = kind != TranslationProviderKind.IMAGE_SERVICE
}

/**
 * The one place the active provider is decided.
 *
 * Previously the page pipeline, the metadata path and the cache identity each re-derived this
 * independently, and they had already drifted: metadata identity ignored Gemini Nano, so a
 * metadata entry could be stamped with the cloud model while pages were being translated on
 * device. Adding a provider meant editing four separate decision sites.
 */
@SingleIn(AppScope::class)
@Inject
class TranslationProviderResolver(
    private val prefs: TranslationPreferences,
    private val geminiNano: GeminiNanoTranslator,
    private val localLlm: LocalLlmManager,
) {

    suspend fun resolve(): ActiveTranslationProvider {
        val providerPref = prefs.provider().get()
        val wantsImageService = prefs.mangaTranslatorEnabled().get() ||
            providerPref.equals(PROVIDER_IMAGE_SERVICE, ignoreCase = true)
        if (wantsImageService) {
            return ActiveTranslationProvider(
                kind = TranslationProviderKind.IMAGE_SERVICE,
                providerName = PROVIDER_IMAGE_SERVICE,
                modelName = PROVIDER_IMAGE_SERVICE,
                isReady = true,
            )
        }

        if (prefs.geminiNanoEnabled().get() && geminiNano.isAvailable()) {
            return ActiveTranslationProvider(
                kind = TranslationProviderKind.GEMINI_NANO,
                providerName = PROVIDER_GEMINI_NANO,
                modelName = PROVIDER_GEMINI_NANO,
                isReady = true,
            )
        }

        if (localLlm.isLocalProvider()) {
            return ActiveTranslationProvider(
                kind = TranslationProviderKind.LOCAL_GGUF,
                providerName = PROVIDER_LOCAL,
                modelName = "$PROVIDER_LOCAL:${localLlm.resolveModel()?.id ?: "auto"}",
                isReady = true,
            )
        }

        val provider = providerPref.lowercase().ifBlank { DEFAULT_CLOUD_PROVIDER }
        val model = prefs.effectiveModel().ifBlank { DEFAULT_CLOUD_MODEL }
        val hasKey = prefs.effectiveApiKey().isNotBlank()
        return ActiveTranslationProvider(
            kind = TranslationProviderKind.CLOUD,
            providerName = provider,
            modelName = model,
            isReady = hasKey,
            unavailableReason = if (hasKey) null else "no API key configured for $provider",
        )
    }

    /** Target language, defaulted the same way for every caller. */
    fun targetLanguage(): String = prefs.targetLang().get().ifBlank { DEFAULT_TARGET_LANG }

    // The metadata path below is deliberately synchronous. Its readiness is read from the UI on a
    // hot path (MangaInfoTranslationController) and is stubbed in tests, so it must not depend on
    // the suspending Gemini Nano probe. Metadata does not use Gemini Nano today - it needs no page
    // image - so this is a real difference in capability, not a second copy of the same decision.

    /**
     * Metadata readiness. The image service cannot translate bare text, so it reports unsupported.
     */
    fun metadataState(): MangaInfoProviderState {
        if (prefs.mangaTranslatorEnabled().get() ||
            prefs.provider().get().equals(PROVIDER_IMAGE_SERVICE, ignoreCase = true)
        ) {
            return MangaInfoProviderState.MANGA_TRANSLATOR_UNSUPPORTED
        }
        if (localLlm.isLocalProvider()) return MangaInfoProviderState.READY
        return if (prefs.effectiveApiKey().isNotBlank()) {
            MangaInfoProviderState.READY
        } else {
            MangaInfoProviderState.NOT_CONFIGURED
        }
    }

    /** Provider/model identity stamped on metadata cache entries. */
    fun metadataIdentity(): MangaInfoIdentity = if (localLlm.isLocalProvider()) {
        MangaInfoIdentity(
            provider = PROVIDER_LOCAL,
            model = "$PROVIDER_LOCAL:${localLlm.resolveModel()?.id ?: "auto"}",
        )
    } else {
        MangaInfoIdentity(provider = prefs.provider().get().lowercase(), model = prefs.effectiveModel())
    }

    companion object {
        const val PROVIDER_IMAGE_SERVICE = "mangatranslator"
        const val PROVIDER_GEMINI_NANO = "gemini-nano"
        const val PROVIDER_LOCAL = "local"
        const val DEFAULT_CLOUD_PROVIDER = "openrouter"
        const val DEFAULT_CLOUD_MODEL = "google/gemma-2-9b-it:free"
        const val DEFAULT_TARGET_LANG = "en"
    }
}
