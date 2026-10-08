<!--
Curated release notes for the NEXT version. Append user-facing bullets here as
work lands, grouped under the headings below, then bump versionName and push.
CI renders this into the release body, and `--cut` archives it into
CHANGELOG.md and clears it after the release.

Write for someone deciding whether to update: what changed for them, not which
files moved. See .github/scripts/release_notes.py.
-->

### New

- **I'm in the thick of it and everybody knows.** Hey guys, Houri dev here. I'm in the thick of it
  and everybody knows. Or do they? This release answers the age-old question of "even though we can,
  should we?". Spoiler alert: the answer is **yes**.

### Improve

- **A new manga cover now shows up straight away** instead of the old one sticking around until the
  app is restarted. The details screen was holding its own copy of the series, so the change was
  written to disk but the screen kept drawing the cover it already had cached.
- **The nudge buttons in the cover editor now move the framing the way they say.** Pressing "up"
  showed more of the cover below the one you were looking at rather than above it.
- **Scrolling in the WebGPU reader no longer queues behind the page loader.** Deciding whether a
  double-page spread needed its two halves resized to match ran on the same lock the loader uses to
  release finished pages, so every frame waited on it - and the placeholder spinner took that same
  lock just to draw itself. Both now read the values they need directly, so the loader can catch up
  without the display waiting.

### Fix

- **Fixed a removed cover lingering on screen after removing several titles at once.** Bulk removal
  stamped the cached files so their retention window started at the removal, but never recorded the
  new timestamp on the title, so the cover that was still visible was never told to redraw. Removing
  a single title at a time already did this.
- **Fixed wide pages getting a black band above and below them in WebGPU double-page mode.** The
  "rotate to fit" option that turns a landscape page a quarter turn so it fills its half of the
  spread worked in the classic reader but did nothing at all in the WebGPU one, which left the page
  fitted to half the screen width - a short strip with empty space above and below it that only
  zooming cleared.
- **Fixed tapping a tap zone in vertical reading mode dragging the page sideways instead of turning
  it.** When "navigate by panning" was on (the default) and you were zoomed into a page - so there
  was room to pan sideways - the next/previous zone slid the page across its own width rather than
  moving down to the next page, which dropped you in the opposite corner. Zoomed-out reading was
  unaffected, which is why it looked intermittent.
- **Fixed the reader getting stuck on a page until the app was force-killed.** Scrolling quickly
  could leave a page permanently loading, and the recovery meant to rescue it was the thing keeping
  it there: every retry created the condition that scheduled the next one, so it span thousands of
  times a second and dragged the memory up with it. Retries are now spaced out, and a page that
  keeps failing is rebuilt from scratch rather than retried against state that has wedged it.
- **Fixed the cover editor carrying on working after the page it was cropping was gone**, which
  logged a spurious failure while tearing down.
- **Fixed the cover dialog going on showing the cover you had just replaced.** Setting a custom
  cover from the crop editor left the full-screen cover viewer drawing the old image, because it
  only asked for the cover once per manga rather than once per cover - so the change did not show
  up until you left the screen and came back.
- **Fixed blank and frozen pages in the WebGPU reader.** A page that was still being prepared when
  it scrolled past - or when a very tall page was split into pieces - had its image uploaded to the
  GPU and then dropped without being released, so every occurrence quietly cost tens of megabytes
  of graphics memory until the reader began failing to load pages at all.
- **Fixed the WebGPU loading screen sometimes showing nothing but a black page.** The percentage
  readout was drawn only once the loading icon had finished uploading, so on the very first frame
  after opening a chapter - or after the GPU was reset - there was no icon *and* no percentage.
- **Fixed WebGPU webtoon chapters skipping pages after a very tall page was split.** Each piece of
  a tall page is shorter than the space reserved for it while it loads, so a reader partway down
  one could be left looking at the next page while the reader still thought they were on the
  previous one - and nothing corrected them.
- **Fixed a page removed by a split never being replaced in the WebGPU continuous reader.** The
  page that had been split away stayed cached as a window entry, so its slot stayed blank and
  everything below it was out by the number of new pieces until the reader moved on.
- **Fixed the WebGPU reader briefly reporting the wrong page and skipping one right after a tall
  page was split**, because the page it re-anchored onto was measured from a position that no
  longer existed.
- **Fixed a page rescued from being stuck still leaking its graphics memory.** Six different places
  gave up on a page, and each released a slightly different set of things - so a page dropped by the
  "this page is wedged, rebuild it" recovery kept the two images held aside for the before/after
  comparison. They now all release the same things in the same order.
