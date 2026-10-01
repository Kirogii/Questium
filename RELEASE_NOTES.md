<!--
Curated release notes for the NEXT version. Append user-facing bullets here as
work lands, grouped under the headings below, then bump versionName and push.
CI renders this into the release body, and `--cut` archives it into
CHANGELOG.md and clears it after the release.

Write for someone deciding whether to update: what changed for them, not which
files moved. See .github/scripts/release_notes.py.
-->

### New
- Sort categories and subcategories by name, date added, or date modified from the category management screen, and have that choice also drive the order of the library's category tabs. Sorting only changes what you see — your manual order is kept and returns whenever you switch back to Manual
- Filter global search results by source category, using the same categories as the Sources tab, alongside the existing pinned/all filter
- Color your chapter bookmarks to record why you kept them. Select a bookmarked chapter, tap the color button in the selection bar, and its bookmark icon takes that color. Bookmarks with no color look exactly as they always did, and colors stay on your device — recoloring doesn't mark the chapter as changed or re-sync it
- Filter a manga's chapter list by bookmark color, from the same chapter filter sheet as the unread and bookmarked filters. Pick any combination of colors to show only bookmarks tagged with one of them
- Nudge and zoom buttons on the custom cover crop screen. A directional pad shifts the image one small step at a time and a pair of buttons zooms in and out, and holding any of them keeps repeating — so you can line a cover up precisely on a small screen, or on a phone whose touchscreen drifts, instead of having to drag and guess
- The Private extension installer is now offered in release builds, not just debug ones. It is the only installer that needs no install permission at all, so it keeps working when Android's "install unverified apps" setting is unavailable or has lapsed — which now means a 24 hour wait and a warning that can switch itself back off. Extensions installed privately are checked against the repository signing key before they are stored, and a copy that fails verification is discarded instead of replacing a working extension

### Improve
- The History tab's "Resume" button now skips back to the most recent entry you haven't finished, instead of always starting from the most recent entry of all
- Achievements use noticeably less battery while you read. Checking whether you'd already earned something no longer rescans the whole achievement list for every single check, so finishing a chapter does far less work than before

### Fix
- Fix crash when tapping selected text in a manga description with a mouse after selecting it by touch
- Fix the cover crop preview starting too small and overshooting when zooming to fit, so the exported crop matches what you see
- Fix the library chapter badge counting blacklisted chapters that the details screen already hides
- Fix the AI translation toggle flashing on manga details pages when the feature is turned off
- Fix a thin line showing between pages in the WebGPU reader's webtoon mode
- Fix the release announcement posted on Discord listing raw commit names instead of the written release notes
- Fix being able to pinch the custom cover crop zoomed out past the point where the image fills the frame, which could save a cover with empty space around it
- Fix the private extension installer taking a very long time to load on a large extension collection. It was re-reading and re-checking every private extension once per installed extension, so the cost grew with the square of how many you had — with 100 private extensions it did 10,000 archive reads before loading a single source. Each private extension is now read and verified once, and those reads now happen in parallel instead of one at a time, so cold start and resume no longer crawl. This is what makes the private installer — the one that needs no install permission — practical on a big collection
