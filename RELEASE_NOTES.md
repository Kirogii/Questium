<!--
Curated release notes for the NEXT version. Append user-facing bullets here as
work lands, grouped under the headings below, then bump versionName and push.
CI renders this into the release body, and `--cut` archives it into
CHANGELOG.md and clears it after the release.

Write for someone deciding whether to update: what changed for them, not which
files moved. See .github/scripts/release_notes.py.
-->

### New

- **Export the database as a file.** Settings > Data > Export now has an "Export database" row that writes a self-contained snapshot wherever you choose. Recent changes are folded in first, so the file carries every commit rather than only what happened to be flushed — importing it elsewhere no longer silently rolls back the last few chapters read, category edits and tracker rows. The snapshot is verified before the export is reported as successful.

### Improve

- **Every library layout now has its own loading skeleton.** The library and the source browse pages load into a placeholder that matches the layout you selected — list, compact grid, cover-only, comfortable, panorama, staggered — instead of one generic grid that made the content jump as it arrived.
- **Category management fits small screens.** On phones the row actions collapse into an overflow menu so the category name stays readable, and the bulk-action bar wraps instead of pushing its last two buttons off screen.

### Fix

- **Edits to manga entries now persist.** Titles, authors, artists, covers, descriptions, tags and status you set from the manga info editor were kept in a file outside the database, so they were lost on uninstall, missing from database exports, and invisible to backups. They now live in the database alongside everything else. Existing edits are migrated in automatically the first time the app starts.
- **Dynamic theming works again.** Cover-based theming on the manga page and in the reader was sampling the palette from a second image request that failed whenever the cover could not be re-fetched, and the resolved colour was stored in a map that was not safe to read and write from different threads. The palette is now taken from the cover already on screen. Monet also picks up wallpaper and accent changes without a restart, and falls back to your own accent instead of an unrelated static theme on devices without the Android 12 system palette.
- **The "Start reading" button follows the cover colour**, with a label colour chosen for readability rather than for contrast against arbitrary cover colours.
- **Restoring a backup no longer floods the screen with achievement toasts.** Restoring writes every previously unlocked achievement at once; that was announced one toast and one sound at a time. A restore now produces a single summary line, and an unlock earned during normal reading is never announced twice.
- **Achievements are more reliable.** "Wipe achievement data" now also resets the lifetime counters it left behind (downloads, categories, sources, tracker updates and friends), so those achievements can actually be earned again; finishing a manga reports one combined result instead of two; the collection achievements no longer re-scan the whole catalogue on every unlock; and a failure in one step of a chapter read no longer discards every step after it.
- **Turning a setting on now unlocks its achievement even if you turned it on before.** The preference watchers used to only react to changes and were not installed at all while achievements were disabled, so settings restored from a backup never qualified.
- **On-device AI settings follow the RAM gate consistently.** Disabling the gate from About now takes effect immediately rather than after a restart, and the upscaler model downloads are hidden on devices the gate is protecting instead of being offered and then crashing.
- **The tracking filter finds tracked entries again.** The library's tracked/untracked filter and the per-tracker filters were reading a track list that had been filtered down to a single tracker, so anything you tracked elsewhere looked untracked.
- **The tracker dialog stops flickering.** It rendered your locally stored tracking data and then swapped the whole thing for freshly fetched data a moment later. It now refreshes first and shows one set of information.
- **Long webtoon strips no longer duplicate as you scroll.** A page too tall to decode is cut into segments; the cut could run twice for the same page and append a second copy of every segment, so the page count kept growing. The page counter and the saved reading position also indexed the page list with a segment's synthetic index, which broke both once a strip was cut.
- **Mihon upstream**: FlexibleAdapter now comes from its original `eu.davidea` 5.1.0 release on Maven Central instead of a JitPack fork that is no longer served.
