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

- **Fixed a crash that closed the app while reading in the WebGPU reader.** 1.23.10 released the
  small graphics buffers used to draw the loading spinner and chapter title card as soon as they
  were drawn, which is earlier than the GPU had actually read them. The submitted work then referred
  to freed memory and the app went down — most visibly on opening any chapter that still had pages
  loading. Those buffers are now released only once the GPU reports that frame finished.
- **Fixed the continuous reader slowly losing framerate over a long session.** Placeholder pages
  drew with graphics memory that was never handed back, so a long chapter accumulated more and more
  of it and the frame rate sagged the longer you read. The memory is now reclaimed, and a frame that
  draws none of it costs nothing.
