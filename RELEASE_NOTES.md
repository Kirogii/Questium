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

- **Dynamic color now works below Android 12.** The Monet theme samples your wallpaper's own colours
  and builds the palette from them, instead of relying on the system palette that only exists on
  Android 12+. Changing your wallpaper re-themes the app straight away, without a restart.

### Fix

- **Fixed very tall pages rendering on top of themselves.** An image too tall for the decoder is cut
  into segments, and the reader could end up drawing the whole strip and its segments at the same
  time. Either the strip or its replacement could also linger as a blank or stale page when you
  turned to it. Long strips now have exactly one representation and page through cleanly.
