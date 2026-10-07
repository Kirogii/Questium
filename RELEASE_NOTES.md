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

- **Failed extensions now say why they failed.** The extensions screen showed only a spinner or an
  error icon, with no indication of what had gone wrong — an extension that could not load, a
  download that was rejected, and a network failure all looked identical. The reason is now shown
  under the extension's name.
- **Fixed an extension keeping a stale icon after being updated.** The icon was cached for as long as
  the app ran and was never dropped when the extension changed, so an updated extension kept showing
  the icon from the version it replaced.
- **Fixed the update button doing nothing on some extensions.** If a repository was re-signed, the
  extension was still listed as having an update available, but tapping update did nothing at all.
  The badge and the button now agree on which extension they mean.
- **Fixed extensions failing to load leaving the app waiting indefinitely.** If loading extensions
  failed outright, the app never finished starting up and anything that depends on extensions never
  appeared, with no error shown. Loading now always completes, even when every extension failed.
- **Failed extensions can now be reported to the right place.** An extension that fails usually means
  the site it reads has changed and its maintainer needs to know, but nothing told you who to contact,
  so people would report source problems to Houri support, where they could not be acted on. You are
  now told which repository the extension came from and given a link to its own issue tracker, plus a
  button that copies a full report — extension version, source, repository, app build, device, and
  stack trace — to paste into the issue. You are also asked to check whether the problem is already
  reported first, and to report it in one place rather than several, so maintainers get one clear
  report instead of ten duplicates. The prompt can be dismissed permanently for that version of the
  extension, and the app will not suggest reporting a new version of it again unless you ask.
- **Extensions are found faster in large libraries.** Looking up which extension owns a source
  scanned every installed extension each time, which got noticeably slower the more extensions you had
  installed. It is now looked up directly.

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
