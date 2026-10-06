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
