package eu.kanade.presentation.library.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import tachiyomi.domain.library.model.LibraryDisplayMode
import tachiyomi.presentation.core.components.shimmer

/**
 * Loading placeholders that mirror each library/browse layout.
 *
 * A single generic skeleton cannot work here: the layouts differ in column count, cover aspect
 * ratio, whether a title is shown at all, and whether rows are one or four lines tall. Showing
 * the comfortable-grid shape while the user has the cover-only grid selected means the content
 * visibly re-flows the instant loading finishes - the placeholder has to be the same layout, not
 * merely "some grey boxes".
 *
 * Each `*Shimmer` therefore sits beside the real item composable it stands in for, and
 * [LibraryLayoutShimmer] is the single dispatcher, so a new [LibraryDisplayMode] has exactly one
 * place to be wired.
 */
@Composable
fun LibraryLayoutShimmer(
    displayMode: LibraryDisplayMode,
    columns: Int,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(8.dp),
    itemCount: Int = 18,
) {
    val spaced = modifier
        .fillMaxSize()
        .padding(contentPadding)

    when (displayMode) {
        LibraryDisplayMode.List -> LazyColumn(
            modifier = spaced,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            items(itemCount) { MangaListItemShimmer() }
        }

        LibraryDisplayMode.CoverOnlyGrid -> gridShimmer(spaced, columns, itemCount) {
            MangaCoverOnlyItemShimmer()
        }

        LibraryDisplayMode.CompactGrid -> gridShimmer(spaced, columns, itemCount) {
            MangaCompactGridItemShimmer()
        }

        LibraryDisplayMode.ComfortableGrid -> gridShimmer(spaced, columns, itemCount) {
            MangaComfortableGridItemShimmer()
        }

        LibraryDisplayMode.ComfortableGridPanorama -> gridShimmer(spaced, columns, itemCount) {
            MangaComfortableGridItemShimmer(panorama = true)
        }

        // Alternating heights so the eventual reflow is vertical only, which is what the real
        // StaggeredGrid does once real aspect ratios arrive.
        LibraryDisplayMode.StaggeredGrid -> gridShimmer(spaced, columns, itemCount) { index ->
            MangaStaggeredGridItemShimmer(tall = index % 2 == 0)
        }
    }
}

@Composable
private fun gridShimmer(
    modifier: Modifier,
    columns: Int,
    itemCount: Int,
    item: @Composable (Int) -> Unit,
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(columns.coerceAtLeast(1)),
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(itemCount) { item(it) }
    }
}

@Composable
private fun MangaCompactGridItemShimmer(modifier: Modifier = Modifier) {
    Column(modifier = modifier.padding(2.dp)) {
        CoverShimmer(ratio = 2f / 3f, corner = 4.dp)
        Spacer(Modifier.height(6.dp))
        LineShimmer(0.7f)
        Spacer(Modifier.height(4.dp))
        LineShimmer(0.25f)
    }
}

@Composable
private fun MangaComfortableGridItemShimmer(panorama: Boolean = false, modifier: Modifier = Modifier) {
    Column(modifier = modifier.padding(2.dp)) {
        CoverShimmer(ratio = if (panorama) 3f / 2f else 2f / 3f, corner = 6.dp)
        Spacer(Modifier.height(8.dp))
        LineShimmer(0.85f)
        Spacer(Modifier.height(6.dp))
        LineShimmer(0.5f)
        Spacer(Modifier.height(6.dp))
        LineShimmer(0.3f)
    }
}

@Composable
private fun MangaCoverOnlyItemShimmer(modifier: Modifier = Modifier) {
    CoverShimmer(ratio = 2f / 3f, corner = 4.dp, modifier = modifier)
}

@Composable
private fun MangaStaggeredGridItemShimmer(tall: Boolean, modifier: Modifier = Modifier) {
    Column(modifier = modifier.padding(2.dp)) {
        CoverShimmer(ratio = if (tall) 0.68f else 0.9f, corner = 6.dp)
        Spacer(Modifier.height(6.dp))
        LineShimmer(if (tall) 0.8f else 0.55f)
        if (tall) {
            Spacer(Modifier.height(4.dp))
            LineShimmer(0.45f)
        }
    }
}

@Composable
private fun MangaListItemShimmer(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 4.dp, vertical = 6.dp),
    ) {
        SkeletonBox(
            width = 56.dp,
            height = 80.dp,
            corner = 4.dp,
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = 12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            LineShimmer(0.6f)
            LineShimmer(0.4f)
            LineShimmer(0.35f)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                SkeletonBox(width = 44.dp, height = 16.dp, corner = 8.dp)
                SkeletonBox(width = 44.dp, height = 16.dp, corner = 8.dp)
            }
        }
    }
}

@Composable
private fun CoverShimmer(
    ratio: Float,
    corner: Dp,
    modifier: Modifier = Modifier,
) {
    SkeletonBox(
        corner = corner,
        modifier = modifier
            .fillMaxWidth()
            .aspectRatio(ratio),
    )
}

@Composable
private fun LineShimmer(fraction: Float, modifier: Modifier = Modifier) {
    SkeletonBox(height = 10.dp, modifier = modifier.fillMaxWidth(fraction))
}

@Composable
private fun SkeletonBox(
    modifier: Modifier = Modifier,
    width: Dp? = null,
    height: Dp? = null,
    corner: Dp = 8.dp,
) {
    Box(
        modifier = modifier
            .then(if (width != null) Modifier.width(width) else Modifier)
            .then(if (height != null) Modifier.height(height) else Modifier)
            .clip(RoundedCornerShape(corner))
            .shimmer(),
    )
}
