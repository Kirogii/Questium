<!--
Curated release notes for the NEXT version. Append user-facing bullets here as
work lands, grouped under the headings below, then bump versionName and push.
CI renders this into the release body, and `--cut` archives it into
CHANGELOG.md and clears it after the release.

Write for someone deciding whether to update: what changed for them, not which
files moved. See .github/scripts/release_notes.py.
-->

### New

### Improve

- **Improved scrolling smoothness in the continuous (webtoon) reader.** Finding a page's position
  inside a chapter scanned the whole page list from the start every time, and the reader did dozens
  of those per frame, so a long chapter paid for it constantly. Positions are now looked up directly,
  and pages inside a single frame are resolved once instead of re-walked.
- **The "an extension is not working" popup now shows which extension it is about** — its icon, plus
  its version, repository and failing source as compact tags — so you can tell at a glance what broke
  and whether the "don't show again" you are about to press applies to the version you are running.
- **Extension error popups can now be switched off.** Each popup offers a button to disable them,
  which asks for confirmation first and explains that broken extensions stay listed on the extensions
  page. You can also switch them off, and back on, at any time in **Advanced settings**.
- **The error shown underneath a failing extension can now be switched off.** It is on by default,
  and is separate from the popup switch: turning this off hides only the message under the row and
  leaves the popups working. Failures are still recorded either way, so switching it back on shows
  what is broken right now rather than starting from scratch.

### Fix

- **Fixed the continuous reader jumping forward a screen and a half every time a page finished
  loading.** A page still loading only reserved one screen's worth of height, so the moment the real
  image arrived — often several times that height on a webtoon — your position inside it was scaled
  up to match, and the view leapt ahead mid-scroll. Your place in the strip now stays put.
- **Fixed pages of the next chapter never appearing when scrolling into it.** Reaching a chapter
  boundary made the reader repeatedly switch the active chapter back and forth as you crossed it,
  which restarted the chapter loader and rebuilt the page window on every pass, so the pages you were
  scrolling towards got dropped and re-queued. The chapter now advances once, as you enter it.
- **Fixed the whole screen being left blank when zoomed out in the continuous reader.** The reader only
  ever drew a fixed number of pages either side of the current one, so zooming out far enough that
  more pages fit than that cut the bottom of the screen off. It now draws as far as the zoom requires.
- **Fixed stuttering that got worse the longer you read.** Placeholder pages — the loading spinner and
  the chapter title card — allocated graphics memory on every frame and never released it, so a long
  session slowly exhausted it and the framerate sagged. That memory is now released each frame.
- **Fixed a long pause the first time a chapter name in a non-Latin script was drawn**, such as a
  Japanese or Korean title. Each character had to be rendered and uploaded individually, rebuilding the
  whole font atlas repeatedly while the screen was live. Characters are now prepared in one batch.
- **Fixed the continuous reader resuming in the wrong place.** The saved scroll position was restored
  by an absolute page number where a position relative to the current page was expected, so reopening a
  chapter could land you well away from where you left off.
- **Fixed a brief flash of a stale image when opening a chapter**, where a frame could reach the screen
  before anything had been drawn into it.
- **Fixed extensions being listed as broken when nothing had actually gone wrong.** The error list
  treated any message written at error level as a failure, including a few cases that are deliberate
  checks rather than faults — most visibly an extension containing NSFW content while that content is
  switched off, which marked a perfectly working extension as broken and offered to report it. Only
  real exceptions are tracked now.
- **Fixed extensions staying marked as broken on the extensions page after they started working
  again.** Most failures that reach the error watchdog are a site being briefly unavailable rather
  than a scraper that needs fixing — a server error, a rate limit, a dropped connection — and those
  clear up on their own. An extension that answers again now drops its error, so it stops being
  listed as broken once it is plainly working.
- **Fixed the extension error popups appearing during a global search.** Searching every source at once
  meant each broken one produced its own popup, and they queued up over the results. Global searches no
  longer raise them; the failure is still listed on the extensions page, and using a broken source on
  its own still reports it.
- **Fixed the long-strip reader running out of memory and stalling the whole app.** A page that could
  not finish loading was put back into the decode queue on every single frame, because the reader
  re-queued anything it was asked to display. Each attempt allocated fresh decoder and network memory
  and forced a garbage collection, so the heap filled as fast as it could be emptied — which took down
  the entire app, not just the reader. Pages are now queued once, when the reader first asks for them,
  and recovery is left to the existing check that runs only when something actually changes.
- **Fixed pages in the long-strip reader staying at 0% while the pages around them loaded.** The page
  you were looking at was placed at the back of the decode queue instead of the front, so anything the
  reader had speculatively loaded jumped ahead of it and it could wait indefinitely. The page on screen
  now decodes first.
