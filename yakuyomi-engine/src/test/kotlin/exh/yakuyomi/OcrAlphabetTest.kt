package exh.yakuyomi

import io.kotest.matchers.shouldBe
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.parallel.Execution
import org.junit.jupiter.api.parallel.ExecutionMode
import java.io.File

/**
 * Invariants for the OCR alphabets shipped as assets.
 *
 * A CTC alphabet is matched to the model's output by index, so a mismatch is silent: OCR keeps
 * returning text, just the wrong text. Nothing in the pipeline can catch a vocabulary that is one
 * entry short, which is why the sizes and the reserved prefix are asserted here.
 */
@Execution(ExecutionMode.CONCURRENT)
class OcrAlphabetTest {

    private val assets: File = generateSequence(File(System.getProperty("user.dir"))) { it.parentFile }
        .map { File(it, "src/main/assets") }
        .firstOrNull { File(it, PP_OCR_ASSET).isFile }
        ?: error("could not locate src/main/assets/$PP_OCR_ASSET from ${System.getProperty("user.dir")}")

    private fun lines(name: String): List<String> =
        File(assets, name).readLines().filter { it.isNotEmpty() }

    private val ppocr = lines(PP_OCR_ASSET)
    private val bundled = lines(BUNDLED_ASSET)

    @Test
    fun `ppocrv5 vocabulary matches the model logits width`() {
        // 1 blank + 1 inserted space + 18383 entries of PaddleOCR's ppocrv5_dict.txt. The model
        // emits 18385 logits, so this count is a contract with the weights, not a snapshot.
        ppocr.size shouldBe 18385
    }

    @Test
    fun `bundled vocabulary is untouched by adding the alternative`() {
        // The PP-OCRv5 asset must not have been regenerated over the top of the original.
        bundled.size shouldBe 19264
    }

    @Test
    fun `ppocrv5 reserves blank then the inserted space`() {
        // PaddleOCR's space sits at index 1, one past the blank, and is not in the dict file.
        ppocr[0] shouldBe "<blank>"
        ppocr[1] shouldBe "<SP>"
    }

    @Test
    fun `ppocrv5 keeps the ideographic space that kotlin counts as whitespace`() {
        // Regression guard. The dictionary opens with U+3000, and String.isNotBlank() treats it as
        // whitespace, so the loader's filter used to drop it and shift all 18382 later characters
        // by one - every line readable, every character wrong.
        ppocr[2] shouldBe "\u3000"
        ppocr[2].isBlank() shouldBe true
    }

    @Test
    fun `no other entry is whitespace-only`() {
        // loadAlphabet filters on isNotEmpty, so nothing else may be silently removable.
        ppocr.indices.filter { ppocr[it].isBlank() } shouldBe listOf(2)
    }

    @Test
    fun `the two alphabets differ so filename selection matters`() {
        // YakuyomiEngine picks between them by OCR model filename; identical files would mean the
        // choice was untested and one of the two models was always wrong.
        (ppocr == bundled) shouldBe false
    }

    private companion object {
        const val PP_OCR_ASSET = "yakuyomi_alphabet_ppocrv5.txt"
        const val BUNDLED_ASSET = "yakuyomi_alphabet.txt"
    }
}
