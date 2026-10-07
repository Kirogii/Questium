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

### Fix

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
