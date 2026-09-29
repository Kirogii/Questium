package tachiyomi.domain.category.model

/**
 * KMK --> Display-only ordering for the library's category tabs and the category
 * management screen. None of these mutate the stored `sort` column, so a
 * reader who re-sorts by name has not silently rewritten their manual order.
 */
enum class CategorySortOrder {
    MANUAL,
    NAME_ASC,
    NAME_DESC,
    DATE_ADDED_NEWEST,
    DATE_ADDED_OLDEST,
    DATE_MODIFIED_NEWEST,
    DATE_MODIFIED_OLDEST,
    ;

    companion object {
        // The management screen persists an Int; keep this the single mapping
        // so the two screens cannot drift apart.
        fun fromStored(value: Int): CategorySortOrder {
            return entries.getOrElse(value) { MANUAL }
        }
    }
}

/**
 * Rows predating tracking carry [Category.DATE_UNKNOWN]. They are placed after
 * dated rows rather than treated as 1970, so a partially-migrated library does
 * not bury every real category at the top of a "newest first" list.
 */
fun List<Category>.sortedForDisplay(sortOrder: CategorySortOrder): List<Category> {
    if (sortOrder == CategorySortOrder.MANUAL) return sortedBy { it.order }
    val dateOf: (Category) -> Long = when (sortOrder) {
        CategorySortOrder.DATE_ADDED_NEWEST, CategorySortOrder.DATE_ADDED_OLDEST -> Category::dateAdded
        else -> Category::dateModified
    }
    val comparator: Comparator<Category> = when (sortOrder) {
        CategorySortOrder.NAME_ASC -> compareBy(String.CASE_INSENSITIVE_ORDER, Category::name)
        CategorySortOrder.NAME_DESC -> compareBy(String.CASE_INSENSITIVE_ORDER, Category::name).reversed()
        CategorySortOrder.DATE_ADDED_NEWEST, CategorySortOrder.DATE_MODIFIED_NEWEST ->
            compareByDescending(dateOf)
        else -> compareBy(dateOf)
    }

    val dated = mutableListOf<Category>()
    val undated = mutableListOf<Category>()
    for (category in this) {
        if (dateOf(category) == Category.DATE_UNKNOWN) undated += category else dated += category
    }
    return dated.sortedWith(comparator) + undated.sortedBy { it.order }
}
