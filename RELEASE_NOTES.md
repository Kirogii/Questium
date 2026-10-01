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
- Fix all translations on a page disappearing when one text region was too short. A short line of translated text - a sound effect, a single character - made the image service throw while drawing, which discarded every other translation on that page
- Fix a crash when the on-device model failed to swap over. Unloading the previous model while loading a new one was not guarded like every other unload, so a failure there could escape the local translation path instead of falling back like other local model errors do
- Fix a failed model import being able to block all future model imports. An interrupted copy of a GGUF file could leave a partial file behind that the model list never showed, while it still counted against the storage needed to import anything else
- Fix translated text disappearing from pages sent to the image translation service. When a single word was too wide to fit a line, the wrapping code replaced the line it had just finished instead of starting a new one, so everything before that word was dropped from the page
- Fix AI translation quietly giving up on a page. When the on-device Gemini model returned nothing and offline fallback was turned off, the untranslated page was displayed and counted as done instead of being marked as failed, so it could never be retried. A provider that crashed also reported itself as an un-downloaded model, sending you to download something you already had. Pages that are too large or malformed to process now say so plainly
- Fix a page being dropped at the moment it is submitted for AI translation, which could happen when a chapter was translating faster than it was being read. A page rejected for being unreadable no longer leaves a stalled entry behind that held up the rest of the chapter
- Fix translated title and description being cached against the wrong provider when Gemini Nano was in use, so they were thrown away and re-translated on every visit
- Fix scrolling stuttering in the strip and continuous readers, especially on long manhwa pages. Every page shown was being read into memory twice over - once on the main thread, which could visibly stall the scroll - even though the only features that need a page in memory are off by default
- Fix a wide page's first half disappearing behind the page before it when rotating the device with Split wide pages on, so the two halves could not be tapped through in order
- Fix browsing E-Hentai getting steadily slower the longer you browsed. With detailed logging enabled the background log writer could stop and never restart, after which every log line piled up in a queue nothing was emptying
- Blacklisted chapters now stay blacklisted everywhere. They were already hidden in a series' chapter list and in the reader, but they could still turn up among your page previews, could still be queued for a download, and both the library's next-unread pick and the History tab's Resume button could still land on one
- Fix a restored backup resetting your per-series scanlator setup. Your scanlator priority, range rules, blacklisted chapters and light-novel flag were never written into the backup file, so restoring one handed every series back with those choices cleared and every chapter you had blacklisted visible again. Backups taken before now still restore - those series simply come back with no scanlator setup, the same as a fresh install
- Fix crash when tapping selected text in a manga description with a mouse after selecting it by touch
- Fix the cover crop preview starting too small and overshooting when zooming to fit, so the exported crop matches what you see
- Fix the library chapter badge counting blacklisted chapters that the details screen already hides
- Fix the AI translation toggle flashing on manga details pages when the feature is turned off
- Fix a thin line showing between pages in the WebGPU reader's webtoon mode
- Fix the release announcement posted on Discord listing raw commit names instead of the written release notes
- Fix being able to pinch the custom cover crop zoomed out past the point where the image fills the frame, which could save a cover with empty space around it
- Fix the private extension installer taking a very long time to load on a large extension collection. It was re-reading and re-checking every private extension once per installed extension, so the cost grew with the square of how many you had — with 100 private extensions it did 10,000 archive reads before loading a single source. Each private extension is now read and verified once, and those reads now happen in parallel instead of one at a time, so cold start and resume no longer crawl. This is what makes the private installer — the one that needs no install permission — practical on a big collection
