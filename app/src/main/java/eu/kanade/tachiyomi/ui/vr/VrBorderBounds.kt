package eu.kanade.tachiyomi.ui.vr

import kotlin.math.abs

/** Finds contiguous uniform margins on a bounded thumbnail, without allocating a tall page. */
internal object VrBorderBounds {
    fun find(width: Int, height: Int, pixels: IntArray): FloatArray {
        val full = floatArrayOf(0f, 0f, 1f, 1f)
        if (width < 2 || height < 2 || pixels.size != width * height) return full
        val background = pixels[0]
        fun border(pixel: Int): Boolean = (0..3).all {
            abs(((pixel ushr (it * 8)) and 255) - ((background ushr (it * 8)) and 255)) <= 16
        }
        var top = 0
        while (top < height && (0 until width).all { border(pixels[top * width + it]) }) top++
        if (top == height) return full
        var bottom = height
        while (bottom > top && (0 until width).all { border(pixels[(bottom - 1) * width + it]) }) bottom--
        var left = 0
        while (left < width && (top until bottom).all { border(pixels[it * width + left]) }) left++
        var right = width
        while (right > left && (top until bottom).all { border(pixels[it * width + right - 1]) }) right--
        left = (left - 1).coerceAtLeast(0)
        top = (top - 1).coerceAtLeast(0)
        right = (right + 1).coerceAtMost(width)
        bottom = (bottom + 1).coerceAtMost(height)
        return floatArrayOf(left.toFloat() / width, top.toFloat() / height, (right - left).toFloat() / width, (bottom - top).toFloat() / height)
    }
}
