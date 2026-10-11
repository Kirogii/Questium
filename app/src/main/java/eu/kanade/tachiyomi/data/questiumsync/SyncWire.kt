package eu.kanade.tachiyomi.data.questiumsync

// KMK -->
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

@Serializable
data class SyncPeer(val id: String, val name: String, val host: String, val port: Int, val secret: String, val main: Boolean = false)

@Serializable
data class SyncMessage(
    val operation: String = "",
    val id: String = "",
    val name: String = "",
    val port: Int = 0,
    val secret: String = "",
    val main: Boolean = false,
    val selected: List<String> = emptyList(),
    val devices: List<SyncPeer> = emptyList(),
    val library: SyncLibrary? = null,
    val error: String = "",
)

/** Versioned, bounded, encrypted LAN protocol. Fresh server challenges prevent replay. */
object SyncWire {
    const val PORT = 37443
    private const val MAGIC = 0x51535931
    // The wire length is an Int, so the protocol itself is the only practical bound.
    private const val MAX_BYTES = Int.MAX_VALUE - 28
    val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }
    private val random = SecureRandom()

    fun secret(): String = Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32).also(random::nextBytes))

    fun address(host: String): InetAddress {
        require(host.matches(Regex("[0-9.]{7,15}"))) { "Use a local IPv4 address" }
        return InetAddress.getByName(host).also {
            require(it.isSiteLocalAddress || it.isLinkLocalAddress || it.isLoopbackAddress) { "Sync requires a local network address" }
        }
    }

    fun call(peer: SyncPeer, request: SyncMessage): SyncMessage = Socket().use { socket ->
        require(peer.port in 1024..65535)
        socket.connect(InetSocketAddress(address(peer.host), peer.port), 5000)
        socket.soTimeout = 120000
        val input = DataInputStream(socket.getInputStream())
        val output = DataOutputStream(socket.getOutputStream())
        output.writeUTF(if (request.operation == "pair") "" else request.id)
        output.flush()
        require(input.readInt() == MAGIC) { "Unsupported sync protocol" }
        val challenge = ByteArray(32).also(input::readFully)
        write(output, peer.secret, challenge + byteArrayOf(2), SyncMessage(operation = "authenticate"))
        require(read(input, peer.secret, challenge + byteArrayOf(3), 4096).operation == "authenticated")
        write(output, peer.secret, challenge + byteArrayOf(0), request)
        read(input, peer.secret, challenge + byteArrayOf(1)).also { require(it.error.isEmpty()) { it.error } }
    }

    fun serve(socket: Socket, secretFor: (String) -> String, handler: (SyncMessage) -> SyncMessage) {
        socket.soTimeout = 5000
        val input = DataInputStream(socket.getInputStream())
        val output = DataOutputStream(socket.getOutputStream())
        val identity = input.readUTF()
        require(identity.length <= 36)
        val secret = secretFor(identity)
        val challenge = ByteArray(32).also(random::nextBytes)
        output.writeInt(MAGIC)
        output.write(challenge)
        output.flush()
        require(read(input, secret, challenge + byteArrayOf(2), 4096).operation == "authenticate")
        write(output, secret, challenge + byteArrayOf(3), SyncMessage(operation = "authenticated"))
        socket.soTimeout = 120000
        val request = read(input, secret, challenge + byteArrayOf(0))
        require(if (identity.isEmpty()) request.operation == "pair" else request.id == identity && request.operation != "pair")
        val response = try {
            handler(request)
        } catch (_: Exception) {
            SyncMessage(error = "Sync failed. Check the main device's status and try again.")
        }
        write(output, secret, challenge + byteArrayOf(1), response)
    }

    private fun write(output: DataOutputStream, secret: String, aad: ByteArray, message: SyncMessage) {
        val bytes = json.encodeToString(SyncMessage.serializer(), message).toByteArray(Charsets.UTF_8)
        require(bytes.size <= MAX_BYTES) { "Sync payload is too large for the wire protocol" }
        val nonce = ByteArray(12).also(random::nextBytes)
        val cipher = cipher(Cipher.ENCRYPT_MODE, secret, nonce, aad)
        val encrypted = cipher.doFinal(bytes)
        output.writeInt(nonce.size + encrypted.size)
        output.write(nonce)
        output.write(encrypted)
        output.flush()
    }

    private fun read(input: DataInputStream, secret: String, aad: ByteArray, limit: Int = MAX_BYTES): SyncMessage {
        val size = input.readInt()
        require(size in 28..limit + 28) { "Invalid sync payload size" }
        val nonce = ByteArray(12).also(input::readFully)
        val encrypted = ByteArray(size - 12).also(input::readFully)
        val bytes = cipher(Cipher.DECRYPT_MODE, secret, nonce, aad).doFinal(encrypted)
        return json.decodeFromString(SyncMessage.serializer(), bytes.toString(Charsets.UTF_8))
    }

    private fun cipher(mode: Int, secret: String, nonce: ByteArray, aad: ByteArray): Cipher {
        val key = Base64.getUrlDecoder().decode(secret)
        require(key.size == 32) { "Invalid pairing key" }
        return Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(mode, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
            updateAAD(aad)
        }
    }
}
// KMK <--
