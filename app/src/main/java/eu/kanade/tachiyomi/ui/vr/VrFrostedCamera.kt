package eu.kanade.tachiyomi.ui.vr

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import java.util.concurrent.atomic.AtomicReference

/** A tiny, blurred, in-memory room texture. No camera images are saved or uploaded. */
class VrFrostedCamera(private val context: Context) {
    private val worker = HandlerThread("VrFrostedGlass").apply { start() }
    private val handler = Handler(worker.looper)
    private val latest = AtomicReference<ByteArray?>()
    private var camera: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var images: ImageReader? = null
    private var active = false
    private var lastFrame = 0L

    fun takeFrame(): ByteArray = latest.getAndSet(null) ?: byteArrayOf()

    @SuppressLint("MissingPermission")
    fun start() {
        if (context.checkSelfPermission(PERMISSION) != PackageManager.PERMISSION_GRANTED ||
            context.checkSelfPermission(android.Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        handler.post {
            if (active) return@post
            active = true
            runCatching {
                val manager = context.getSystemService(CameraManager::class.java)
                val source = CameraCharacteristics.Key("com.meta.extra_metadata.camera_source", Int::class.javaObjectType)
                val id = manager.cameraIdList.firstOrNull { manager.getCameraCharacteristics(it).get(source) == 0 }
                    ?: run {
                        active = false
                        return@post
                    }
                val sizes = manager.getCameraCharacteristics(id).get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                    ?.getOutputSizes(ImageFormat.YUV_420_888).orEmpty()
                val size = sizes.filter { it.width >= WIDTH && it.height >= HEIGHT }
                    .minByOrNull { kotlin.math.abs(it.width.toFloat() / it.height - 4f / 3f) * 1_000_000 + it.width * it.height }
                    ?: run {
                        active = false
                        return@post
                    }
                images = ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, 2).apply {
                    setOnImageAvailableListener({ sourceReader ->
                        runCatching { sourceReader.acquireLatestImage() }.getOrNull()?.use { image ->
                            val now = SystemClock.elapsedRealtime()
                            if (active && now - lastFrame >= 80) {
                                lastFrame = now
                                latest.set(blurredRgb(image))
                            }
                        }
                    }, handler)
                }
                manager.openCamera(
                    id,
                    object : CameraDevice.StateCallback() {
                        override fun onOpened(device: CameraDevice) {
                            if (!active) {
                                device.close()
                                return
                            }
                            camera = device
                            val surface = images?.surface ?: run {
                                device.close()
                                return
                            }
                            @Suppress("DEPRECATION")
                            device.createCaptureSession(
                                listOf(surface),
                                object : CameraCaptureSession.StateCallback() {
                                    override fun onConfigured(configured: CameraCaptureSession) {
                                        if (!active) {
                                            configured.close()
                                            return
                                        }
                                        session = configured
                                        runCatching {
                                            val request = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply { addTarget(surface) }
                                            configured.setRepeatingRequest(request.build(), null, handler)
                                        }.onFailure { stop() }
                                    }
                                    override fun onConfigureFailed(failed: CameraCaptureSession) {
                                        failed.close()
                                        stop()
                                    }
                                },
                                handler,
                            )
                        }
                        override fun onDisconnected(device: CameraDevice) {
                            device.close()
                            stop()
                        }
                        override fun onError(device: CameraDevice, error: Int) {
                            device.close()
                            stop()
                        }
                    },
                    handler,
                )
            }.onFailure { stop() }
        }
    }

    fun stop() {
        handler.post {
            active = false
            session?.close()
            session = null
            camera?.close()
            camera = null
            images?.close()
            images = null
            latest.set(null)
        }
    }

    fun close() {
        stop()
        worker.quitSafely()
    }

    private fun blurredRgb(image: Image): ByteArray {
        val rgb = IntArray(WIDTH * HEIGHT * 3)
        fun sample(plane: Image.Plane, x: Int, y: Int): Int =
            plane.buffer.get(y * plane.rowStride + x * plane.pixelStride).toInt() and 255
        for (y in 0 until HEIGHT) {
            for (x in 0 until WIDTH) {
                val sx = x * image.width / WIDTH
                val sy = y * image.height / HEIGHT
                val luma = (sample(image.planes[0], sx, sy) - 16).coerceAtLeast(0)
                val u = sample(image.planes[1], sx / 2, sy / 2) - 128
                val v = sample(image.planes[2], sx / 2, sy / 2) - 128
                val i = (y * WIDTH + x) * 3
                rgb[i] = ((298 * luma + 409 * v + 128) shr 8).coerceIn(0, 255)
                rgb[i + 1] = ((298 * luma - 100 * u - 208 * v + 128) shr 8).coerceIn(0, 255)
                rgb[i + 2] = ((298 * luma + 516 * u + 128) shr 8).coerceIn(0, 255)
            }
        }
        // Separable box passes keep detailed camera imagery out of the renderer.
        val scratch = IntArray(rgb.size)
        repeat(2) {
            for (y in 0 until HEIGHT) {
                for (x in 0 until WIDTH) {
                    for (c in 0..2) {
                        var sum = 0
                        for (dx in -4..4) sum += rgb[(y * WIDTH + (x + dx).coerceIn(0, WIDTH - 1)) * 3 + c]
                        scratch[(y * WIDTH + x) * 3 + c] = sum / 9
                    }
                }
            }
            for (y in 0 until HEIGHT) {
                for (x in 0 until WIDTH) {
                    for (c in 0..2) {
                        var sum = 0
                        for (dy in -4..4) sum += scratch[((y + dy).coerceIn(0, HEIGHT - 1) * WIDTH + x) * 3 + c]
                        rgb[(y * WIDTH + x) * 3 + c] = sum / 9
                    }
                }
            }
        }
        return ByteArray(rgb.size) { rgb[it].toByte() }
    }

    companion object {
        const val PERMISSION = "horizonos.permission.HEADSET_CAMERA"
        const val WIDTH = 96
        const val HEIGHT = 72
    }
}
