<!--
Curated release notes for the NEXT version. Append user-facing bullets here as
work lands, grouped under the headings below, then bump versionName and push.
CI renders this into the release body, and `--cut` archives it into
CHANGELOG.md and clears it after the release.

Write for someone deciding whether to update: what changed for them, not which
files moved. See .github/scripts/release_notes.py.
-->

### New
- **I'm in the thick of it and everybody knows.** Hey guys, Houri dev here. I'm in the thick of it and everybody knows. Or do they? This release answers the age-old question of "even though we can, should we?". Spoiler alert: the answer is **yes**.


### Improve

- **A new manga cover now shows up straight away** instead of the old one sticking around until the
  app is restarted. The details screen was holding its own copy of the series, so the change was
  written to disk but the screen kept drawing the cover it already had cached.
- **The nudge buttons in the cover editor now move the framing the way they say.** Pressing "up"
  showed more of the cover below the one you were looking at rather than above it.

### Fix

- **Fixed the reader getting stuck on a page until the app was force-killed.** Scrolling quickly could
  leave a page permanently loading, and the recovery meant to rescue it was the thing keeping it
  there: every retry created the condition that scheduled the next one, so it span thousands of
  times a second and dragged the memory up with it. Retries are now spaced out, and a page that keeps
  failing is rebuilt from scratch rather than retried against state that has wedged it.
- **Fixed the cover editor carrying on working after the page it was cropping was gone**, which
  logged a spurious failure while tearing down.

### Fix
