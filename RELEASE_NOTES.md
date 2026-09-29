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

### Improve
- The History tab's "Resume" button now skips back to the most recent entry you haven't finished, instead of always starting from the most recent entry of all

### Fix
- Fix crash when tapping selected text in a manga description with a mouse after selecting it by touch
- Fix the cover crop preview starting too small and overshooting when zooming to fit, so the exported crop matches what you see
- Fix the library chapter badge counting blacklisted chapters that the details screen already hides
- Fix the AI translation toggle flashing on manga details pages when the feature is turned off
