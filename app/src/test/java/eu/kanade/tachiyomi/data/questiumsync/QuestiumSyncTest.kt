package eu.kanade.tachiyomi.data.questiumsync

// KMK -->
import eu.kanade.tachiyomi.data.backup.models.Backup
import eu.kanade.tachiyomi.data.backup.models.BackupChapter
import eu.kanade.tachiyomi.data.backup.models.BackupManga
import io.kotest.matchers.shouldBe
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.parallel.Execution
import org.junit.jupiter.api.parallel.ExecutionMode
import java.net.ServerSocket
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

@Execution(ExecutionMode.CONCURRENT)
class QuestiumSyncTest {
    private fun library(chapter: Int, title: String = "Main title", epoch: Long = 0): SyncLibrary {
        val manga = BackupManga(
            1,
            "/book",
            title = title,
            favorite = true,
            chapters = (1..20).map {
                BackupChapter("/chapter/$it", "Chapter $it", chapterNumber = it.toFloat(), read = it <= chapter)
            },
        )
        return SyncLibrary(Backup(listOf(manga)), mapOf(SyncMerge.key(manga) to epoch))
    }

    @Test
    fun `only main library and explicit additions share secondary membership`() {
        val key = "1|/book"
        SyncState().sharesLibrary(key, false) shouldBe false
        SyncState().sharesLibrary(key, true) shouldBe true
        SyncState(knownBooks = setOf(key)).sharesLibrary(key, false) shouldBe true
        SyncState(libraryAdditions = setOf(key)).sharesLibrary(key, false) shouldBe true
        SyncState(knownBooks = setOf(key), localOnlyBooks = setOf(key)).sharesLibrary(key, false) shouldBe false
        SyncState(libraryAdditions = setOf(key), localOnlyBooks = setOf(key)).sharesLibrary(key, false) shouldBe false
    }

    @Test
    fun `history at page zero is retained without library membership`() {
        val manga = library(0).backup.backupManga.single().apply {
            favorite = false
            history = listOf(eu.kanade.tachiyomi.data.backup.models.BackupHistory("/chapter/20", 1000))
        }
        val compact = SyncMerge.compact(manga)
        compact.favorite shouldBe false
        compact.chapters.single().url shouldBe "/chapter/20"
        SyncMerge.resume(compact) shouldBe 20f
    }

    @Test
    fun `sync payload contains only identity membership and reading progress`() {
        val original = library(10).backup.backupManga.single().apply {
            notes = "private note"
            viewer_flags = 123
            description = "description"
            chapters[0].bookmark = true
        }
        val compact = SyncMerge.compact(original, favorite = false)
        compact.favorite shouldBe false
        compact.notes shouldBe ""
        compact.viewer_flags shouldBe null
        compact.description shouldBe null
        compact.chapters.size shouldBe 10
        compact.chapters.any { it.bookmark } shouldBe false
        SyncMerge.highest(compact) shouldBe 10f
    }

    @Test
    fun `local only library addition shares history without adding to main library`() {
        val remote = library(20)
        remote.backup.backupManga.single().favorite = false
        val result = SyncMerge.merge(SyncLibrary(Backup(emptyList())), listOf(remote)).backup.backupManga.single()
        result.favorite shouldBe false
        SyncMerge.highest(result) shouldBe 20f
    }

    @Test
    fun `opted in library addition promotes existing history on main`() {
        val main = library(10)
        main.backup.backupManga.single().favorite = false
        SyncMerge.merge(main, listOf(library(20))).backup.backupManga.single().favorite shouldBe true
    }

    @Test
    fun `compressed protocol accepts transfers larger than five megabytes`() {
        val random = ByteArray(6 * 1024 * 1024).also(java.util.Random(123)::nextBytes)
        val title = java.util.Base64.getEncoder().encodeToString(random)
        ServerSocket(0).use { server ->
            val key = SyncWire.secret()
            val reply = CompletableFuture.runAsync {
                server.accept().use { socket ->
                    SyncWire.serve(socket, { key }) { SyncMessage(library = library(20, title)) }
                }
            }
            val response = SyncWire.call(SyncPeer("server", "Main", "127.0.0.1", server.localPort, key), SyncMessage("snapshot", id = "device"))
            response.library!!.backup.backupManga.single().title shouldBe title
            reply.get(30, TimeUnit.SECONDS)
        }
    }

    @Test
    fun `main metadata wins while Quest chapter 20 advances phone chapter 10 without changing inputs`() {
        val main = library(10)
        val quest = library(20, "Different title")
        val merged = SyncMerge.merge(main, listOf(quest)).backup.backupManga.single()
        merged.title shouldBe "Main title"
        SyncMerge.highest(merged) shouldBe 20f
        SyncMerge.highest(main.backup.backupManga.single()) shouldBe 10f
        SyncMerge.advanced(SyncMerge.progress(main.backup.backupManga.single()), SyncMerge.progress(merged)) shouldBe true
    }

    @Test
    fun `offline chapter 20 cannot undo a deliberate revert to chapter 10`() {
        val main = library(10, epoch = 1)
        val offline = library(20)
        SyncMerge.highest(SyncMerge.merge(main, listOf(offline)).backup.backupManga.single()) shouldBe 10f
        val readAfterRevert = library(12, epoch = 1)
        SyncMerge.highest(SyncMerge.merge(main, listOf(readAfterRevert)).backup.backupManga.single()) shouldBe 12f
    }

    @Test
    fun `same chapter preserves furthest page and read state`() {
        val main = library(10)
        val quest = library(10)
        main.backup.backupManga.single().chapters[10].lastPageRead = 4
        quest.backup.backupManga.single().chapters[10].lastPageRead = 17
        val merged = SyncMerge.merge(main, listOf(quest)).backup.backupManga.single()
        merged.chapters[10].lastPageRead shouldBe 17L
        SyncMerge.advanced(SyncMerge.progress(main.backup.backupManga.single()), SyncMerge.progress(merged)) shouldBe true
    }

    @Test
    fun `encrypted protocol transfers a library only with the paired key`() {
        ServerSocket(0).use { server ->
            val key = SyncWire.secret()
            val reply = CompletableFuture.runAsync {
                server.accept().use { socket ->
                    SyncWire.serve(socket, { identity ->
                        identity shouldBe "device"
                        key
                    }) { request ->
                        request.operation shouldBe "snapshot"
                        SyncMessage(operation = "snapshot", library = library(20))
                    }
                }
            }
            val response = SyncWire.call(SyncPeer("server", "Main", "127.0.0.1", server.localPort, key), SyncMessage("snapshot", id = "device"))
            SyncMerge.highest(response.library!!.backup.backupManga.single()) shouldBe 20f
            reply.get(5, TimeUnit.SECONDS)
        }
    }

    @Test
    fun `wrong pairing key is rejected before the handler runs`() {
        ServerSocket(0).use { server ->
            var called = false
            val reply = CompletableFuture.runAsync {
                server.accept().use { socket ->
                    runCatching {
                        SyncWire.serve(socket, { SyncWire.secret() }) {
                            called = true
                            SyncMessage()
                        }
                    }
                }
            }
            assertThrows(Exception::class.java) {
                SyncWire.call(SyncPeer("server", "Main", "127.0.0.1", server.localPort, SyncWire.secret()), SyncMessage("snapshot", id = "device"))
            }
            reply.get(5, TimeUnit.SECONDS)
            called shouldBe false
        }
    }

    @Test
    fun `main removals cannot be resurrected by an offline device`() {
        val remote = library(20)
        val key = SyncMerge.key(remote.backup.backupManga.single())
        val main = SyncLibrary(Backup(emptyList()), removed = setOf(key))
        val merged = SyncMerge.merge(main, listOf(remote)).backup.backupManga.single()
        merged.favorite shouldBe false
        SyncMerge.highest(merged) shouldBe 20f
    }

    @Test
    fun `source identity prevents combining matching titles from different sources`() {
        val main = library(10)
        val other = library(20)
        other.backup.backupManga.single().source = 2
        SyncMerge.merge(main, listOf(other)).backup.backupManga.size shouldBe 2
    }

    @Test
    fun `rollback record preserves old chapter and history after serialization`() {
        val before = library(10).backup.backupManga.single()
        val record = ProgressChange("change", SyncMerge.key(before), before.title, 1234, SyncMerge.progress(before), 10f, 20f)
        val restored = SyncWire.json.decodeFromString(ProgressChange.serializer(), SyncWire.json.encodeToString(ProgressChange.serializer(), record))
        restored shouldBe record
        restored.before.count { it.read } shouldBe 10
    }

    @Test
    fun `public and malformed addresses are rejected`() {
        assertThrows(IllegalArgumentException::class.java) { SyncWire.address("8.8.8.8") }
        assertThrows(IllegalArgumentException::class.java) { SyncWire.address("github.com") }
        SyncWire.address("192.168.1.42").isSiteLocalAddress shouldBe true
    }

    @Test
    fun `stable and preview update checks target only this fork`() {
        eu.kanade.tachiyomi.data.updater.getGithubRepo(false) shouldBe "Kirogii/Questium"
        eu.kanade.tachiyomi.data.updater.getGithubRepo(true) shouldBe "Kirogii/Questium"
    }

    @Test
    fun `opening chapter 20 at page zero advances chapter 10 despite an older device clock`() {
        val main = library(10)
        val quest = library(10)
        main.backup.backupManga.single().history = listOf(eu.kanade.tachiyomi.data.backup.models.BackupHistory("/chapter/10", 2000))
        quest.backup.backupManga.single().history = listOf(eu.kanade.tachiyomi.data.backup.models.BackupHistory("/chapter/20", 1000))
        val merged = SyncMerge.merge(main, listOf(quest)).backup.backupManga.single()
        SyncMerge.highest(merged) shouldBe 20f
        SyncMerge.resume(merged) shouldBe 20f
    }
}
// KMK <--
