<!--
Curated release notes for the NEXT version. Append user-facing bullets here as
work lands, grouped under the headings below, then bump versionName and push.
CI renders this into the release body, and `--cut` archives it into
CHANGELOG.md and clears it after the release.

Write for someone deciding whether to update: what changed for them, not which
files moved. See .github/scripts/release_notes.py.
-->

### New
- **Are you? Are you? Coming to the tree?** They strung up a man, and say he murdered three.

### Improve

### Fix
- Source grids no longer switch to a list-shaped skeleton while the next page is loading — the loading placeholders now stay grid-shaped, matching the covers already on screen.
- **Fixed the continuous reader running away from you at a chapter boundary.** Scrolling into the next chapter kept snapping back, so the pages moved down faster than you could read them.
- **Fixed pages in a chapter you had scrolled into sometimes never loading.** They sat on their placeholder until you left and came back.
- Removed covers are now actually kept for as long as the retention setting says. The setting could be ignored entirely: the timestamp that starts the window was not always written, several ways of leaving the library skipped it, and a details refresh could delete a cover belonging to a title already removed.
- **Fixed your zoom being forgotten when you reopen a chapter.** In continuous and webtoon the zoom-out slider goes down to 1%, but anything under half size was being rounded up to 50% before it was saved — so a chapter you had zoomed out to read reopened zoomed in. Very zoomed-in paged pages were clipped for the same reason.
