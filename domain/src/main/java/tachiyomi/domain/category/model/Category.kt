package tachiyomi.domain.category.model

import java.io.Serializable

data class Category(
    val id: Long,
    val name: String,
    val order: Long,
    val flags: Long,
    // KMK -->
    val hidden: Boolean,
    val parentId: Long = 0L,
    val dateAdded: Long = DATE_UNKNOWN,
    val dateModified: Long = DATE_UNKNOWN,
    // KMK <--
) : Serializable {

    val isSystemCategory: Boolean = id == UNCATEGORIZED_ID

    companion object {
        const val UNCATEGORIZED_ID = 0L

        // KMK --> 0 = "unknown, predates tracking". Sorters treat it as a
        // fallback to id rather than as 1970, so legacy rows keep a sensible
        // order instead of all landing in one arbitrary tie.
        const val DATE_UNKNOWN = 0L
        // KMK <--
    }
}
