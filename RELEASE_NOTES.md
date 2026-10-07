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

### Fix

- **Fixed a spinning gap in the long-strip reader where a page should be.** Scrolling quickly could
  drop a page from the reader's memory before it was decoded; coming back to it produced a loading
  placeholder that then never filled, while the pages around it loaded normally. A page the reader is
  actively showing is now always queued for decoding on the spot, instead of relying on a
  speculative pre-load that may not have reached far enough.
- **Fixed two-page spread height matching silently giving up on a chapter.** If a side was still being
  resized when the reader moved on, the "already resizing" marker was left set and every later
  attempt for that page was skipped, so the two halves could stay different heights for the rest of
  the session. The marker is now always cleared.
- **Loading pages in the long-strip reader now show the percentage as well as the spinner**, including
  before any bytes have arrived, so a stalled page is distinguishable from a page that has not
  started.
