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

- **The long-strip reader now loads pages in the order you read them.** Pages behind the current one
  used to jump the queue, so scrolling forward kept landing on placeholders while the strip you had
  already passed was fully decoded. Now the current page decodes first, then the pages ahead of it
  nearest-first, then the ones behind.
- **Library loading placeholders line up with the real grid.** The skeletons used wider spacing than
  the finished items and none of their inner padding, so they sat slightly larger than the covers
  that replaced them and did not follow the screen edges.

### Fix

- **Fixed a transparent strip down the right and bottom edge of upscaled pages on the NPU path.** The
  ONNX models were fed the same padded tiles everywhere, including at the page edges, but they have no
  padding of their own, so the edge tiles came back a little smaller than the code assumed and the edge
  of every page was left unpainted. Edge tiles are now fed without the padding they could not fill.
- **Fixed upscaled pages occasionally coming back partly grey or not displaying at all.** A cached page
  whose file was cut short — by the system reclaiming space while it was open, or by the app being
  closed mid-encode — was served as a finished page. Cached pages are now checked before they are handed
  back, and a damaged one is dropped instead.
- **Fixed upscaling silently giving up for the rest of the session on devices where a model cannot
  run.** A model that failed once — a driver that rejects it, a backend that is unavailable — was kept
  and retried on every page after, loading the weights again each time. It is now discarded after the
  first failure, so the next attempt moves on to the next backend and the reader stops paying for a
  model it cannot use.
- **Fixed the app closing on very large pages when upscaling.** Two size checks in the native upscaler
  multiplied their operands at 32-bit width and could overflow before being compared, so an unusually
  large page could pass a guard it should have been rejected by.
- **Fixed upscaled pages running out of memory on large or long pages.** Encoding a page back to an
  image could exhaust memory on the attempt itself and drop the page entirely; it now falls back to the
  smaller format rather than failing.
- **Fixed the library re-saving every cover colour on every pause.** Switching away from the app, opening
  a dialog or answering a permission prompt each rewrote both stored colour sets in full even when nothing
  had changed; the write is now skipped unless a cover actually gained a colour.
- **Fixed titles disappearing from library covers in rare cases.** A stored colour whose text-colour half
  was missing was read back as fully transparent, drawing the title invisibly on the cover colour. The
  readable colour is now worked out from the cover colour instead.
- **Fixed mangled library covers on rare covers whose header decodes oddly.** Such a cover could store a
  broken aspect ratio, which was then used to size the grid item.
- **Fixed library covers losing their colours when opening a series.** The grid colours were being
  skipped whenever the theme colour could not be read from a cover, even though the two come from
  different swatches and the grid colour is the one more likely to exist.
- **Fixed duplicated and misnumbered pages around chapter boundaries in the long-strip reader.** When
  a very tall page was cut into segments, the page it replaced was no longer in the chapter's list,
  and the reader mistook that for the end of a chapter: the next chapter's pages were laid into the
  strip where the segments belonged, so pages could appear twice, and the page counter and seek bar
  could show the wrong chapter's numbering. Segmented pages now take the place of the page they
  replaced.
- **Fixed the seek bar when reading between chapters.** The page list is now watched for all three
  chapters the reader spans rather than only the current one, so a page being split in a neighbouring
  chapter is picked up instead of leaving the strip and the progress display out of step.
- **Fixed "pure black dark mode" on the Dynamic theme below Android 12.** The black override reached
  the background and surface but skipped every container surface for that theme, so cards, sheets and
  list items stayed on the wallpaper's own hue while the rest of the screen went black. Android 12 and
  newer were unaffected because the system palette already supplies dark containers there.
- **Fixed cover-based theming below Android 12.** That release has no system palette to read a theme
  from, so the accent is now taken from the cover's own pixels instead: the cover is reduced to a
  small grid and its most common colour is averaged out, which gives the series page its buttons,
  gradient and read button the cover's colour on older devices as well. A cover made of a single
  flat tone could also previously produce no colour at all, leaving the page on the global theme.
