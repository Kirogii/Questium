package eu.kanade.tachiyomi.data.questiumsync

// KMK -->
import eu.kanade.tachiyomi.data.backup.models.Backup
import eu.kanade.tachiyomi.data.backup.models.BackupChapter
import eu.kanade.tachiyomi.data.backup.models.BackupExtensionStore
import eu.kanade.tachiyomi.data.backup.models.BackupHistory
import eu.kanade.tachiyomi.data.backup.models.BackupManga
import io.kotest.matchers.shouldBe
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.parallel.Execution
import org.junit.jupiter.api.parallel.ExecutionMode

@Execution(ExecutionMode.CONCURRENT)
class SyncDeltaTest {
    private fun library(count: Int = 1419): SyncLibrary = SyncLibrary(
        Backup(
            (1..count).map { book ->
                BackupManga(
                    1,
                    "/book/$book",
                    title = "Book $book",
                    favorite = true,
                    chapters = (1..40).map { chapter -> BackupChapter("/$book/$chapter", "Chapter $chapter", read = true, chapterNumber = chapter.toFloat()) },
                    history = listOf(BackupHistory("/$book/40", 1000)),
                )
            },
        ),
    )

    private fun copy(library: SyncLibrary): SyncLibrary = SyncWire.json.decodeFromString(SyncLibrary.serializer(), SyncWire.json.encodeToString(SyncLibrary.serializer(), library))

    @Test
    fun `1419 unchanged books transfer no book records and one changed chapter transfers once`() {
        val before = library()
        val baseline = SyncBaseline("first", before)
        SyncDelta.encode(before, baseline).library.backup.backupManga.size shouldBe 0
        val current = copy(before)
        current.backup.backupManga[1000].chapters[5].lastPageRead = 12
        current.backup.backupManga[1000].history = listOf(BackupHistory("/1001/6", 2000))
        val transfer = SyncDelta.encode(current, baseline)
        transfer.library.backup.backupManga.size shouldBe 1
        transfer.library.backup.backupManga.single().chapters.size shouldBe 1
        transfer.library.backup.backupManga.single().chapters.single().lastPageRead shouldBe 12L
        val restored = SyncDelta.decode(transfer, baseline).library
        SyncDelta.encode(current, SyncBaseline("restored", restored)).library.backup.backupManga.size shouldBe 0
        before.backup.backupManga[1000].chapters[5].lastPageRead shouldBe 0L
    }

    @Test
    fun `first sync into empty VR establishes a shared baseline so second sync does not echo 1419 books`() {
        val emptyVr = SyncLibrary(Backup(emptyList()))
        val firstPull = SyncDelta.encode(emptyVr, null, "vr-before-apply")
        val mainReceived = SyncDelta.decode(firstPull, null)
        val merged = SyncMerge.merge(library(), listOf(mainReceived.library))
        val firstApply = SyncDelta.encode(merged, null, "shared-after-apply")
        val vrApplied = SyncDelta.decode(firstApply, null)
        val mainAcknowledged = SyncBaseline(firstApply.revision, merged)
        val vrJournal = SyncJournal(pending = mainReceived).applied(vrApplied)
        val mainJournal = SyncJournal(incoming = mainReceived).applied(mainAcknowledged)
        vrJournal.pending shouldBe null
        vrJournal.incoming!!.revision shouldBe vrJournal.outgoing!!.revision
        val nextPull = SyncDelta.encode(copy(merged), vrJournal.outgoing)
        nextPull.base shouldBe mainJournal.incoming!!.revision
        nextPull.library.backup.backupManga.size shouldBe 0
        val changedOnVr = copy(merged)
        changedOnVr.backup.backupManga[1000].chapters[5].lastPageRead = 21
        val changedPull = SyncDelta.encode(changedOnVr, vrJournal.outgoing)
        changedPull.library.backup.backupManga.size shouldBe 1
        changedPull.library.backup.backupManga.single().chapters.single().lastPageRead shouldBe 21L
        SyncDelta.decode(changedPull, mainJournal.incoming).library.backup.backupManga[1000].chapters[5].lastPageRead shouldBe 21L
    }

    @Test
    fun `membership removals chapter deletions history deletions and revert epochs round trip`() {
        val before = library(2)
        val key = SyncMerge.key(before.backup.backupManga[0])
        val current = copy(before).copy(epochs = mapOf(key to 1L), removed = setOf(key))
        current.backup.backupManga[0].apply {
            favorite = false
            chapters = listOf(BackupChapter("/1/1", "Chapter 1", read = false, lastPageRead = 2))
            history = emptyList()
        }
        val baseline = SyncBaseline("old", before)
        val received = SyncDelta.decode(SyncDelta.encode(current, baseline), baseline)
        received.library.epochs shouldBe current.epochs
        received.library.removed shouldBe current.removed
        received.library.backup.backupManga[0].favorite shouldBe false
        received.library.backup.backupManga[0].chapters.single().lastPageRead shouldBe 2L
        received.library.backup.backupManga[0].chapters.single().read shouldBe false
        received.library.backup.backupManga[0].history shouldBe emptyList()
        val deleted = current.copy(backup = Backup(current.backup.backupManga.drop(1)))
        SyncDelta.decode(SyncDelta.encode(deleted, baseline), baseline).library.backup.backupManga.size shouldBe 1
    }

    @Test
    fun `outgoing baseline advances only after matching acknowledgement`() {
        val old = SyncBaseline("old", library(1))
        val next = SyncBaseline("next", library(2))
        val journal = SyncJournal(outgoing = old, pending = next)
        journal.acknowledge("dropped").outgoing shouldBe old
        journal.acknowledge("old").outgoing shouldBe old
        journal.acknowledge("next").outgoing shouldBe next
        journal.acknowledge("next").pending shouldBe null
        val persisted = SyncWire.json.decodeFromString(SyncJournal.serializer(), SyncWire.json.encodeToString(SyncJournal.serializer(), journal))
        persisted.outgoing!!.revision shouldBe "old"
        persisted.pending!!.revision shouldBe "next"
    }

    @Test
    fun `a lost apply acknowledgement falls back to a full snapshot instead of corrupting progress`() {
        val old = SyncBaseline("old", library(1))
        val changed = library(2)
        val transfer = SyncDelta.encode(changed, old, "new")
        val applied = SyncDelta.decode(transfer, old)
        assertThrows(IllegalArgumentException::class.java) { SyncDelta.decode(transfer, applied) }
        val full = SyncDelta.encode(changed, null)
        SyncDelta.decode(full, applied).library.backup.backupManga.size shouldBe 2
    }

    @Test
    fun `independent directions do not acknowledge or overwrite each others baselines`() {
        val a = SyncBaseline("a", library(1))
        val b = SyncBaseline("b", library(2))
        val c = SyncBaseline("c", library(3))
        val journal = SyncJournal(incoming = a, outgoing = b, pending = c)
        journal.acknowledge("c").incoming shouldBe a
        val localChange = library(4)
        SyncDelta.decode(SyncDelta.encode(localChange, journal.outgoing), journal.outgoing).library.backup.backupManga.size shouldBe 4
        journal.outgoing shouldBe b
    }

    @Test
    fun `extension requirements and stores survive empty reading deltas`() {
        val before = library(1)
        val store = BackupExtensionStore("https://store/repo.json", "Store", null, "key", "https://store", null, false, null)
        val current = before.copy(
            backup = before.backup.copy(backupExtensionStores = listOf(store)),
            extensions = listOf(SyncExtension("extension.en.test", "signature", store.indexUrl)),
        )
        val baseline = SyncBaseline("old", before)
        val transfer = SyncDelta.encode(current, baseline)
        transfer.library.backup.backupManga.size shouldBe 0
        val received = SyncDelta.decode(transfer, baseline).library
        received.extensions shouldBe current.extensions
        received.backup.backupExtensionStores.single().indexUrl shouldBe store.indexUrl
        received.backup.backupExtensionStores.single().signingKey shouldBe "key"
        val merged = SyncMerge.merge(before, listOf(received))
        merged.backup.backupExtensionStores.single().indexUrl shouldBe store.indexUrl
        merged.extensions shouldBe current.extensions
    }
}
// KMK <--
