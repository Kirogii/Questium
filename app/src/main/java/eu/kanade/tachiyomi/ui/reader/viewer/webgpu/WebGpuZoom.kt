// KMK -->
package eu.kanade.tachiyomi.ui.reader.viewer.webgpu

import ca.mpreg.webgpuviewer.viewer.ImagePage
import eu.kanade.tachiyomi.ui.reader.viewer.ReaderPageImageView.ZoomStartPosition

/**
 * The zoom stack every decoded page has to pass through before it is shown.
 *
 * All three run on a freshly built [ImagePage.ImageSingle] - at decode, and again after a
 * dual-page height-match rescale or a translation swap replaced the image - so they are collected
 * here rather than repeated at each of those call sites.
 */
internal fun WebGpuViewer.applyZoomPolicy(page: ImagePage.ImageSingle) {
    if (!isDualPageMode()) {
        if (!applyWideZoomIfNeeded(page)) {
            applyFitModeAnchor(page)
        }
    }
    applyDoubleTapZoomPolicy(page)
}

/**
 * The viewer library always performs its built-in double-tap zoom, so when the
 * preference is disabled the page's max scale is clamped to its home scale - the
 * zoom animation then lands where it started. The paged "disable zoom in" pref
 * clamps the same way, and the library additionally caps pinch/double-tap-drag
 * gestures at a restricted maxScale. The library sentinel -1f restores the computed default.
 */
internal fun WebGpuViewer.applyDoubleTapZoomPolicy(page: ImagePage.ImageSingle) {
    if (isDestroyed || isContinuous) return
    if (config.doubleTapZoom && !config.disableZoomIn) {
        try {
            page.maxScale = -1f
        } catch (_: Exception) {
        }
        return
    }
    val w = try {
        pager.state.width
    } catch (_: Exception) {
        0
    }
    val h = try {
        pager.state.height
    } catch (_: Exception) {
        0
    }
    if (w <= 0 || h <= 0) return
    try {
        page.maxScale = page.homeScale
    } catch (_: Exception) {
    }
}

internal fun WebGpuViewer.applyWideZoomIfNeeded(page: ImagePage.ImageSingle): Boolean {
    if (isDestroyed || !config.landscapeZoom) return false
    val image = page.image ?: return false

    val screenW = try {
        pager.state.width
    } catch (_: Exception) {
        0
    }
    val screenH = try {
        pager.state.height
    } catch (_: Exception) {
        0
    }
    if (screenW <= 0 || screenH <= 0) return false

    // Don't zoom if the trimmed page already fits at original scale.
    if (page.trimWidth <= screenW) return false

    // Wide page: half the (trimmed) image width is wider than the screen aspect ratio.
    val aspectRatio = minOf(
        page.trimWidth.toFloat() / page.trimHeight.toFloat(),
        image.width.toFloat() / image.height.toFloat(),
    )

    // not wide enough
    if (aspectRatio < 1.1) return false

    if (aspectRatio <= 2f * screenW.toFloat() / screenH) return false

    // Scale to fit half the image width to the full screen width
    val wideScale = screenW.toFloat() / (page.trimWidth / 2f)

    page.homeScale = wideScale

    // need to set parent for positioning to work
    page.parent = pager.state

    val minX = page.minX(page.homeScale)
    val maxX = page.maxX(page.homeScale)

    val startX = when (config.imageZoomType) {
        ZoomStartPosition.LEFT -> maxX
        ZoomStartPosition.RIGHT -> minX
        ZoomStartPosition.CENTER -> 0f
    }

    page.homeX = startX
    page.scale = page.homeScale
    page.x = startX
    page.y = page.homeY
    return true
}

internal fun WebGpuViewer.applyFitModeAnchor(page: ImagePage.ImageSingle) {
    if (isDestroyed) return
    val scaleType = config.imageScaleType
    if (scaleType != 3 && scaleType != 4 && scaleType != 5) return

    val image = page.image ?: return

    val screenW = try {
        pager.state.width
    } catch (_: Exception) {
        0
    }
    val screenH = try {
        pager.state.height
    } catch (_: Exception) {
        0
    }
    if (screenW <= 0 || screenH <= 0) return

    val w = page.trimWidth.toFloat()
    val h = page.trimHeight.toFloat()
    if (w <= 0f || h <= 0f) return

    val cutoutTopPx = pager.state.cutoutTopPx
    val contentW = screenW.toFloat()
    val contentH = if (pager.state.avoidCutout && cutoutTopPx > 0f) screenH - cutoutTopPx else screenH.toFloat()

    page.homeScale = when (scaleType) {
        3 -> contentW / w
        4 -> contentH / h
        else -> 1f // original size
    }.coerceAtLeast(0.01f)

    page.parent = pager.state

    if (scaleType == 5) { // original size
        val minScaleComputed = minOf(contentW / page.width, contentH / page.height).coerceAtLeast(0.01f)
        if (page.homeScale < minScaleComputed) {
            page.minScale = page.homeScale
        }
    }

    // zoom start for fit height/original size
    if (scaleType == 4 || scaleType == 5) {
        val minX = page.minX(page.homeScale)
        val maxX = page.maxX(page.homeScale)
        page.homeX = when (config.imageZoomType) {
            ZoomStartPosition.LEFT -> maxX
            ZoomStartPosition.RIGHT -> minX
            ZoomStartPosition.CENTER -> 0f
        }
    }

    // push below cutout for fit width/original size
    val trimTop = image.trim?.top ?: 0
    val imageTopY = (screenH - page.height * page.homeScale) / 2f
    val trimTopY = imageTopY + trimTop * page.homeScale
    if ((scaleType == 3 || scaleType == 5) && h * page.homeScale > screenH) {
        val target = if (pager.state.avoidCutout && cutoutTopPx > 0f) {
            if (pager.state.alwaysAvoidCutout) cutoutTopPx / 2f else cutoutTopPx
        } else {
            0f
        }
        page.homeY = maxOf(0f, (target - trimTopY) / (page.homeScale * screenH))
    }

    page.scale = page.homeScale
    page.x = page.homeX
    page.y = page.homeY
}
// KMK <--
