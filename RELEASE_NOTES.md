<!--
Curated release notes for the NEXT version. Append user-facing bullets here as
work lands, grouped under the headings below, then bump versionName and push.
CI renders this into the release body, and `--cut` archives it into
CHANGELOG.md and clears it after the release.

Write for someone deciding whether to update: what changed for them, not which
files moved. See .github/scripts/release_notes.py.
-->

### New
- Quest reader: rounded book toolbar and Book Options popup, configurable controller buttons with labeled Touch Plus diagrams, hand switching, haptic feedback, and white page grab bars.

- Quest VR reader development: adds an immersive Settings entry, spatial reader controls and a native page-turn renderer. This work is experimental and still requires APK and headset validation.

### Improve

### Fix
- Update the Android VR runtime to Godot 4.6.3 so it can load the embedded reader pack instead of aborting at a black screen.
- Initialize the Quest reader with an OpenXR render surface and reuse its immersive activity instead of starting duplicate VR engines.
- Keep VR entry controls visible and recognize Meta/Oculus headsets that do not advertise Android’s head-tracking feature. Add a direct Enter VR action.
