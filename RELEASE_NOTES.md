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

- **The feed tabs now show a layout-shaped placeholder while loading** instead of a spinner. The
  Feed tab, the per-source feed, the multi-feed tab and the two feed-ordering screens all used to sit
  on a centred spinner while their first load — a separate network round-trip for every source —
  finished. They now show dimmed placeholders laid out like the content that is coming: rows of
  cover cards for the feeds, and reorderable rows for the ordering screens. The card widths match the
  real ones, including the wide-cover setting, so nothing slides sideways when the results arrive.

### Fix

- **Fixed pages in the long-strip reader loading forever.** A page could end up marked as still being
  fetched or decoded while nothing was actually working on it — most often after you scrolled past it
  and back while it was still loading. The reader then treated it as busy, never retried it, and left
  its loading animation spinning indefinitely. Pages caught in that state are now retried, those
  markers are cleared whenever a load or decode ends for any reason, and a check re-drives anything
  that still gets stranded.
- **Fixed already-loaded pages unloading themselves in the long-strip reader.** Scrolling out of a
  section and back could evict a page you had already read in favour of a placeholder that had not
  been decoded yet, so you landed on a spinner and had to load it again. Eviction now prefers the
  cheapest thing to lose — never-decoded placeholders first, then work not yet started, then content
  you were already looking at.
- **Fixed the cover preview freezing when it opened.** Building the preview image generated its whole
  range of detail levels and uploaded each to the graphics card, but the app waited for that on the
  main thread, so the dialog could hang for a noticeable moment on a large cover before it showed
  anything. The work now happens off the main thread, so the preview appears straight away.
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