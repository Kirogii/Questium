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
- **Source pages now show placeholders shaped like the results you are waiting for.** Opening a
  source's cover grid left the screen blank — or briefly drew the list-style loading rows — until
  the first page arrived, then snapped everything into place. The grid now fills with cover-shaped
  placeholders on the same grid the real covers will land on, so nothing jumps when they arrive.

### Fix

- **Fixed very tall pages rendering on top of themselves.** An image too tall for the decoder is cut
  into segments, and the reader could end up drawing the whole strip and its segments at the same
  time. Either the strip or its replacement could also linger as a blank or stale page when you
  turned to it. Long strips now have exactly one representation and page through cleanly.
- **Fixed very tall pages breaking a chapter after you left and came back.** A cut page was
  remembered as a set of separate pages, so reopening the chapter treated each of them as a whole
  page and cut them again — one strip could end up shown dozens of times, and pages after it were
  duplicated too.
- **Fixed the reader getting stuck on very tall pages.** Where a page was cut, the reader's page
  list could stay shorter than the chapter, leaving the rest of the strip and every page after it
  unreachable — turning past the end simply did nothing. This now follows in all three reading
  modes: strip, webtoon, and the GPU viewer.
- **Fixed the GPU reader jumping to the wrong page after a very tall page was cut.** It could send
  you back to wherever the chapter was opened rather than to the page replacing the one you were on.
- **Fixed very tall pages failing to reload after the image cache was cleared or trimmed.** Cutting
  one needs the original image, which could be dropped while its pieces were kept, leaving the page
  permanently broken instead of re-fetching.
- **Fixed chapters with a very tall page resuming on the wrong page.** Splitting a page into pieces
  shifts the position of every page after it, but your place in the chapter was remembered as a
  position in the pre-split list. Leaving and coming back could drop you a page or two further on —
  or, on the GPU reader, past where you stopped.
