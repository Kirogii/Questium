<!--
Curated release notes for the NEXT version. Append user-facing bullets here as
work lands, grouped under the headings below, then bump versionName and push.
CI renders this into the release body, and `--cut` archives it into
CHANGELOG.md and clears it after the release.

Write for someone deciding whether to update: what changed for them, not which
files moved. See .github/scripts/release_notes.py.
-->

### New
- This release is dedicated to my ex-friend **Juliana**, slinger of slurs and the core reason our world doesn't have gender equality yet. If it wasn't for her pissing me off so much, this release would've taken a lot longer.
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
- **Extra-long webtoon strips no longer show the wrong page.** Only strips far beyond the usual length were affected: when a strip needed more than sixteen segments, the numbering for its segments ran into the numbering range of the page after it, and the reader could hand back a page from elsewhere in the chapter. The reserved range per page is now large enough that a strip has to be implausibly long to reach it.
- **Dynamic theming applies to the manga page again.** The colour was being sampled from a cover held in GPU memory, which cannot be read directly, so the theme stayed untinted on most devices. It is now sampled from a readable copy, and doing so no longer stutters the screen as the details page opens.
- **Completing a manga no longer counts twice.** Both completion paths already recorded a cleared backlog entry, and the reader recorded it a second time on top, which inflated that lifetime counter and could award its tiers twice as fast as intended.
- **Restoring a backup still sends achievement webhooks.** Bulk mode was suppressing the outgoing webhook along with the toasts and sounds, so every achievement earned during a restore went unrecorded by anything listening for them.
- **Migrating your old manga edits no longer stalls on one stale entry.** An edit for a series no longer in your library made the whole import roll back on every launch, so none of your other edits were carried over. Each edit is now brought across on its own, and the ones with nothing to attach to are reported and skipped.
- **Monet theming on Android 8–11 no longer risks a crash.** Reading the wallpaper and system accent colours on those releases now checks the API level first.
- **Changing the translation target language or provider now takes effect.** Translated pages were saved under a key that recorded neither, so switching either kept serving the pages already on disk and the setting looked like it was being ignored. Saved pages are now re-used only when they match the language, provider and model they were produced with.
- **A dropped connection no longer silently ends translation for the chapter.** When a translation provider could not be reached, the page was recorded as "skipped" rather than "failed" — which meant it was never retried, the chapter never showed an error, and the pages stayed in their original language. Pages the provider failed on are now retried, and are offered for retry in the reader.
- **Pausing translation actually pauses.** Cancelling the worker immediately restarted it, so queued pages kept draining.
- **Long webtoon strips are only paid for once.** Pages produced by cutting a tall strip were never saved, so every visit re-ran detection, text recognition and the translation request for them. The reader also no longer creates folders merely by looking for a cached page.
- **The status chip reports on the page you are looking at.** It previously reflected the chapter as a whole, so a chapter with one translated page showed "Translated" over pages that were still in their original language — including pages that had deliberately been left untranslated.
- **Mihon upstream**: FlexibleAdapter now comes from its original `eu.davidea` 5.1.0 release on Maven Central instead of a JitPack fork that is no longer served.
