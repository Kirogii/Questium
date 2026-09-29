package tachiyomi.domain.category.model

import io.kotest.matchers.shouldBe
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.parallel.Execution
import org.junit.jupiter.api.parallel.ExecutionMode

@Execution(ExecutionMode.CONCURRENT)
class CategorySortingTest {

    private fun category(
        id: Long,
        name: String,
        order: Long = id,
        dateAdded: Long = Category.DATE_UNKNOWN,
        dateModified: Long = Category.DATE_UNKNOWN,
    ) = Category(
        id = id,
        name = name,
        order = order,
        flags = 0,
        hidden = false,
        dateAdded = dateAdded,
        dateModified = dateModified,
    )

    private fun names(categories: List<Category>) = categories.map { it.name }

    @Test
    fun `manual mode returns the stored order untouched`() {
        val categories = listOf(category(1, "Beta", order = 2), category(2, "Alpha", order = 1))

        names(categories.sortedForDisplay(CategorySortOrder.MANUAL)) shouldBe listOf("Alpha", "Beta")
    }

    @Test
    fun `name sorting is case insensitive`() {
        val categories = listOf(category(1, "banana"), category(2, "Apple"), category(3, "cherry"))

        names(categories.sortedForDisplay(CategorySortOrder.NAME_ASC)) shouldBe listOf("Apple", "banana", "cherry")
        names(categories.sortedForDisplay(CategorySortOrder.NAME_DESC)) shouldBe listOf("cherry", "banana", "Apple")
    }

    @Test
    fun `date added newest first`() {
        val categories = listOf(
            category(1, "old", dateAdded = 100),
            category(2, "new", dateAdded = 300),
            category(3, "mid", dateAdded = 200),
        )

        names(categories.sortedForDisplay(CategorySortOrder.DATE_ADDED_NEWEST)) shouldBe listOf("new", "mid", "old")
        names(categories.sortedForDisplay(CategorySortOrder.DATE_ADDED_OLDEST)) shouldBe listOf("old", "mid", "new")
    }

    @Test
    fun `date modified is read independently of date added`() {
        val categories = listOf(
            category(1, "createdFirst", dateAdded = 100, dateModified = 300),
            category(2, "modifiedLast", dateAdded = 300, dateModified = 100),
        )

        names(categories.sortedForDisplay(CategorySortOrder.DATE_MODIFIED_NEWEST)) shouldBe
            listOf("createdFirst", "modifiedLast")
    }

    @Test
    fun `undated rows sort after dated rows instead of counting as 1970`() {
        val categories = listOf(
            category(1, "legacy"),
            category(2, "recent", dateAdded = 500),
        )

        names(categories.sortedForDisplay(CategorySortOrder.DATE_ADDED_NEWEST)) shouldBe listOf("recent", "legacy")
    }

    @Test
    fun `undated rows keep stored order among themselves`() {
        val categories = listOf(
            category(1, "first", order = 2),
            category(2, "second", order = 1),
        )

        names(categories.sortedForDisplay(CategorySortOrder.DATE_ADDED_NEWEST)) shouldBe listOf("second", "first")
    }

    @Test
    fun `an entirely undated library does not collapse into a date tie`() {
        val categories = listOf(
            category(1, "Beta", order = 2),
            category(2, "Alpha", order = 1),
        )

        names(categories.sortedForDisplay(CategorySortOrder.DATE_ADDED_OLDEST)) shouldBe listOf("Alpha", "Beta")
    }

    @Test
    fun `stored mode out of range falls back to manual`() {
        CategorySortOrder.fromStored(99) shouldBe CategorySortOrder.MANUAL
        CategorySortOrder.fromStored(CategorySortOrder.NAME_DESC.ordinal) shouldBe CategorySortOrder.NAME_DESC
    }
}
