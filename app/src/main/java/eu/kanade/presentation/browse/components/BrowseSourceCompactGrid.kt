package eu.kanade.presentation.browse.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.unit.dp
import androidx.compose.ui.util.fastAny
import androidx.paging.LoadState
import androidx.paging.compose.LazyPagingItems
import eu.kanade.presentation.library.components.CommonMangaItemDefaults
import eu.kanade.presentation.library.components.MangaCompactGridItem
import eu.kanade.tachiyomi.R
import exh.metadata.metadata.MangaDexSearchMetadata
import exh.metadata.metadata.RaisedSearchMetadata
import exh.metadata.metadata.RankedSearchMetadata
import exh.util.isLewd
import kotlinx.coroutines.flow.StateFlow
import tachiyomi.domain.manga.model.Manga
import tachiyomi.domain.manga.model.MangaCover
import tachiyomi.presentation.core.components.Badge
import tachiyomi.presentation.core.i18n.stringResource
import tachiyomi.presentation.core.util.plus

@Composable
fun BrowseSourceCompactGrid(
    mangaList: LazyPagingItems<StateFlow</* SY --> */Pair<Manga, RaisedSearchMetadata?>/* SY <-- */>>,
    columns: GridCells,
    contentPadding: PaddingValues,
    onMangaClick: (Manga) -> Unit,
    onMangaLongClick: (Manga) -> Unit,
    // KMK -->
    selection: List<Manga>,
    // KMK <--
) {
    // First page in flight with nothing to show: draw the grid's own cells *instead of* the grid.
    // Nesting a lazy grid inside a lazy grid item throws, so this cannot be a full-span item.
    if (mangaList.loadState.refresh is LoadState.Loading && mangaList.itemCount == 0) {
        BrowseSourceCompactGridShimmer(columns = columns, contentPadding = contentPadding)
        return
    }

    LazyVerticalGrid(
        columns = columns,
        contentPadding = contentPadding + PaddingValues(8.dp),
        verticalArrangement = Arrangement.spacedBy(CommonMangaItemDefaults.GridVerticalSpacer),
        horizontalArrangement = Arrangement.spacedBy(CommonMangaItemDefaults.GridHorizontalSpacer),
    ) {
        if (mangaList.loadState.prepend is LoadState.Loading) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                BrowseSourceLoadingItem()
            }
        }

        items(count = mangaList.itemCount) { index ->
            // SY -->
            val pair by mangaList[index]?.collectAsState() ?: return@items
            val manga = pair.first
            val metadata = pair.second
            // SY <--

            BrowseSourceCompactGridItem(
                manga = manga,
                // SY -->
                metadata = metadata,
                // SY <--
                onClick = { onMangaClick(manga) },
                onLongClick = { onMangaLongClick(manga) },
                // KMK -->
                isSelected = selection.fastAny { selected -> selected.id == manga.id },
                // KMK <--
            )
        }

        // A refresh over items already on screen is a footer, not a placeholder for the grid.
        if (mangaList.loadState.refresh is LoadState.Loading || mangaList.loadState.append is LoadState.Loading) {
            if (mangaList.itemCount > 0) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    BrowseSourceLoadingItem()
                }
            }
        }
    }
}

@Composable
internal fun BrowseSourceCompactGridItem(
    manga: Manga,
    // SY -->
    metadata: RaisedSearchMetadata?,
    // SY <--
    onClick: () -> Unit = {},
    onLongClick: () -> Unit = onClick,
    // KMK -->
    isSelected: Boolean = false,
    // KMK <--
) {
    MangaCompactGridItem(
        title = manga.title,
        isLewd = manga.isLewd(),
        coverData = MangaCover(
            mangaId = manga.id,
            sourceId = manga.source,
            isMangaFavorite = manga.favorite,
            ogUrl = manga.thumbnailUrl,
            lastModified = manga.coverLastModified,
        ),
        // KMK -->
        isSelected = isSelected,
        // KMK <--
        coverAlpha = if (manga.favorite) CommonMangaItemDefaults.BrowseFavoriteCoverAlpha else 1f,
        coverBadgeStart = {
            InLibraryBadge(enabled = manga.favorite)
        },
        // SY -->
        coverBadgeEnd = {
            if (metadata is MangaDexSearchMetadata) {
                metadata.followStatus?.let { followStatus ->
                    val text = LocalResources.current
                        .let { resources ->
                            remember(resources, followStatus) {
                                resources.getStringArray(R.array.md_follows_options)
                                    .getOrNull(followStatus)
                            }
                        }
                        ?: return@let
                    Badge(
                        text = text,
                        color = MaterialTheme.colorScheme.tertiary,
                        textColor = MaterialTheme.colorScheme.onTertiary,
                    )
                }
                metadata.relation?.let {
                    Badge(
                        text = stringResource(it.res),
                        color = MaterialTheme.colorScheme.tertiary,
                        textColor = MaterialTheme.colorScheme.onTertiary,
                    )
                }
            } else if (metadata is RankedSearchMetadata) {
                metadata.rank?.let {
                    Badge(
                        text = "+$it",
                        color = MaterialTheme.colorScheme.tertiary,
                        textColor = MaterialTheme.colorScheme.onTertiary,
                    )
                }
            }
        },
        // SY <--
        onLongClick = onLongClick,
        onClick = onClick,
    )
}
