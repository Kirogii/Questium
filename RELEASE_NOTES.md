<!--
Curated release notes for the NEXT version. Append user-facing bullets here as
work lands, grouped under the headings below, then bump versionName and push.
CI renders this into the release body, and `--cut` archives it into
CHANGELOG.md and clears it after the release.

Write for someone deciding whether to update: what changed for them, not which
files moved. See .github/scripts/release_notes.py.
-->

### New
- Rebrand the app as Questium with a single Touch controller logo.
- Use the app's actual library, source search, manga details and chapter history in the frosted VR interface; chapter selection opens the spatial book.
- Quest reader: rounded book toolbar and Book Options popup, configurable controller buttons with labeled Touch Plus diagrams, hand switching, haptic feedback, and white page grab bars.

- Quest VR reader development: adds an immersive Settings entry, spatial reader controls and a native page-turn renderer. This work is experimental and still requires APK and headset validation.

### Improve
- Include all upstream commits through Houri v1.23.9, including extension management fixes and long-page memory improvements.
- Build Quest APKs in GitHub Actions with automatic Godot setup, signed artifacts and a dedicated alpha prerelease.
- Make the VR library half-sized and closer, allow resizing its top corners, and retain their placement until manually recentered. A thumb-up fist adjusts workspace distance.
- Turn pages with an open hand from the white side bars, including quick inward swipes; improve extended-finger scrolling and stabilize hand pointers during pinches.
- Show fallback controller models and add source language selection with English enabled by default.
- Launch directly into darkened passthrough, with smaller book previews and reader defaults, accessible preview actions, and scrolling book options with bounded titles.
- Use the Quest system keyboard from textboxes, browse source icons in a scrolling picker, and search/install extension sources from VR.
- Carry books with a curled fist, resize physical spreads with both top corners, swipe long pages with a light fingertip motion, and keep the palm guide attached only while facing you. Recenter places the book beside the HUD.

- Flatten the spatial book into thin covers and paper edges, with a curved sheet during turns instead of a thick rigid page block.
- Tap nearby frosted controls directly with a tracked fingertip; interrupted touches cancel safely without activating a button.
- Match the reference book gestures more closely: carry a closed book by its cover, pull its moving outer bar to open or close it, and keep the grabbed point attached during wrist rotation. Idle hands have white outlines that turn purple during interaction.
- Grab books and window handles from a distance with controllers, close individual books from their own controls, and see edge hover feedback on every placed book.
- Scroll long pages smoothly through slow drags and loading boundaries, with backward continuity and throttled chapter transitions; preserve cover state when advancing chapters.
- Keep palm controls above the hand, stable during selection, and available through the controller menu. Add connected tracked fingers when the native hand mesh is unavailable.
- Document and tune the hand-to-page interaction around fingertip contact, pinch hysteresis, captured edge dragging, midpoint settling, and passthrough depth order based on the Livro reference video.
- Long manga pages now use a large scrollable reader window when their aspect ratio would make two-page mode unreadable. Automatic detection preserves page width, keeps only nearby strips in GPU memory, and supports hand drag plus right-stick up/down scrolling.
- Replace the three-window workspace with a single frosted Home, Source Search and Reader interface in the VR room; selecting a cover brings out the physical book preview.

### Fix
- Keep tracked hands visible when the native Quest mesh is delayed or unavailable by using a bundled skinned fallback; support unspecified tracking-source data and retain hand visuals during brief fingertip occlusion.
- Prevent distant second-hand pinches from resizing a held book; preserve its pose when either hand lets go, and keep cover handles reachable throughout their hinge movement.
- Prevent the More/settings screen from crashing while loading the Questium logo; compact oversized logo paths below Android's resource string limit, including launcher variants.
- Bundle the native hand/controller model extension in the embedded reader, enable Quest controller render models, and remove capsule placeholders.
- Load cover artwork when resuming chapters and keep the closed page block behind it; rebuild books with beveled covers, curved paper stacks, visible page edges and denser turning leaves.
- Preserve placed windows when reopening the library, save the active book before closing it, route clicks to the nearest visible surface, and block clicks through books.
- Prevent cover/page acquisition jumps and restore interrupted cover grabs; keep two-hand resizing stable when returning to one-hand movement.
- Grab the page or closed cover when pinching a lower outer corner instead of moving the whole book; controller grip continues to move the book body.
- Correct upside-down Quest library panels and allow either controller to select items, with a visible pointer on the Android panel.
- Fix black VR frames from an uninitialized library-layer pose, allow the app library to open on its private display, and restart cleanly after closing VR.
- Center the Quest library and book on the tracked headset, connect controller tracking and pointers, and open VR in library mode before selecting a chapter.
- Include the OpenXR loader in the embedded Quest reader so VR can start instead of displaying a black screen.
- Use the Android OpenXR launch flag with the reader project's XR configuration.
- Update the Android VR runtime to Godot 4.6.3 so it can load the embedded reader pack instead of aborting at a black screen.
- Initialize the Quest reader with an OpenXR render surface and reuse its immersive activity instead of starting duplicate VR engines.
- Keep VR entry controls visible and recognize Meta/Oculus headsets that do not advertise Android’s head-tracking feature. Add a direct Enter VR action.
## VR cover library and frosted interface

- Exit VR returns to the headset instead of opening the old Android reader interface.
- Turn physical book pages with an open-hand sweep above the page; the curl follows your hand, settles across the spine, and cancels safely on tracking loss.
- Match the library's heading weight and left-aligned cover captions to the reference; recenter the interface along your gaze, including looking up and down.
- Launch directly into the VR room with a single frosted Home, Source Search, and Reader HUD.
- Show manga cover art in the library and source grids; selecting a cover brings out its hinged 3D book.
- Add a preview with Save to Library, Read/Resume, and a searchable chapter and description side panel.
- Disable stick locomotion and snap turning; recenter the interface in the current facing direction.
- Keep cover artwork while reading and support long strips. Novel support is deferred.

- Remove automatic HUD/book recentering while looking away; preserve manual recenter controls.
- Drag the main HUD and popups by clenching inside their panels. Keep popups above books and other UI, with accessible Close controls.
