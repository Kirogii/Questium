package eu.kanade.presentation.browse.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.plus
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import eu.kanade.presentation.components.ComfortableGridItemShimmer
import eu.kanade.presentation.components.CompactGridItemShimmer
import eu.kanade.presentation.library.components.CommonMangaItemDefaults

/**
 * Placeholder cells for a source's manga grid while its first page is still loading.
 *
 * The grid layouts used to reuse [BrowseSourceLoadingItem], which is a list row - a 56x80 cover
 * beside text lines - so an empty grid showed three full-width rows and then snapped into a grid of
 * covers. Same complaint the library's shimmer documents: the placeholder has to be the layout it
 * stands in for, or the content re-flows the moment real data lands.
 *
 * Spacing matches [BrowseSourceCompactGrid] and [BrowseSourceComfortableGrid] so the cells land on
 * the same grid the real items will.
 */
@Composable
internal fun BrowseSourceCompactGridShimmer(
    columns: GridCells,
    contentPadding: PaddingValues,
    itemCount: Int = 18,
) {
    BrowseSourceGridShimmer(columns, contentPadding, itemCount) { CompactGridItemShimmer() }
}

@Composable
internal fun BrowseSourceComfortableGridShimmer(
    columns: GridCells,
    contentPadding: PaddingValues,
    usePanoramaCover: Boolean = false,
    itemCount: Int = 18,
) {
    BrowseSourceGridShimmer(columns, contentPadding, itemCount) {
        ComfortableGridItemShimmer(panorama = usePanoramaCover)
    }
}

@Composable
private fun BrowseSourceGridShimmer(
    columns: GridCells,
    contentPadding: PaddingValues,
    itemCount: Int,
    item: @Composable () -> Unit,
) {
    LazyVerticalGrid(
        columns = columns,
        modifier = Modifier
            .fillMaxSize()
            .padding(contentPadding + PaddingValues(8.dp)),
        verticalArrangement = Arrangement.spacedBy(CommonMangaItemDefaults.GridVerticalSpacer),
        horizontalArrangement = Arrangement.spacedBy(CommonMangaItemDefaults.GridHorizontalSpacer),
    ) {
        items(itemCount) { item() }
    }
}
