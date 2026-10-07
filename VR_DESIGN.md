# Quest VR reader

Target: Meta Quest 3 / 3S, standalone. Reference: the user's 55-second Livro video and four screenshots.

## Required experience

- Launch directly into the VR room with a native frosted glass HUD.
- A spatial library with covers, categories, chapter selection and resume-reading.
- A movable, rotatable, resizable physical book with two textured pages, covers, a spine and page thickness.
- Pages curl continuously while grabbed or swept with an open hand, follow the fingers, and settle forward or back at the midpoint. Both hands and Touch controllers work.
- Toolbar below the book: library/menu, previous spread, page seeker, next spread, recenter and book options.
- Book options: size, distance, tilt, left/right reading direction, passthrough or completely black surroundings.
- Existing Houri sources, local content, downloads, reading progress and trackers remain the content backend.

## Integration

Embed Godot's Android library in a dedicated immersive activity in the same APK. Use OpenXR and the official OpenXR Vendors Meta plugin for Quest. A runtime Godot plugin connects the spatial UI to Houri's existing domain interactors and ReaderViewModel; source credentials never leave the application.

The launcher opens VrActivity directly into the existing VR room. Godot renders the entire interface; the old Android composition panel is no longer built or started. The single Home HUD follows Reference1 with counted lime-icon navigation, date-grouped cover cards, persistent hearts, and a selected sidebar row. Source Search uses Reference3's search layout and the same cover cards. Reader opens the physical book for page manga and an automatic vertically scrollable surface for webtoons. Novel support is deferred.

Selecting a cover animates its textured, hinged 3D book out of the grid before hiding Home. A Reference4-style preview shows the cover, title badge, Save to Library and Read/Resume actions. Info opens a rounded frosted side panel with the full description, chapter search and a scrollable chapter list. Read starts the first chapter or resumes the latest chapter in reading history. A chapter image never overwrites the actual cover artwork. Favorites and a recoverable Recently Deleted collection are stored locally; removing from the library only changes membership.

Sticks do not move or snap-turn the player. Recenter uses the latest tracked head position and full gaze direction to relocate the HUD, preview, reader, keyboard and side windows. Head tracking remains physical. Controller sticks and pinch drags scroll the native interface. Headset acceptance covers launcher routing, source/cover loading, selecting a cover, chapter entry, resume, and recentering; exact perceptual parity needs in-headset comparison with the references.

An unobstructed tracked hand can sweep an index fingertip above an open physical page without pinching. Enter from an outer edge, then move inward to acquire the leaf. The curl follows horizontal travel across the spine in book coordinates, including when the book is tilted or resized. Crossing the midpoint settles forward; an early lift settles back. A completed stroke requires leaving the interaction volume before rearming. Pinches, UI capture, closed previews, long strips, tracking discontinuities and focus loss cannot start a sweep. The synthetic XR-joint regression is `xr/tests/hand_sweep_check.gd`; actual hand feel still requires headset acceptance.

Page textures are prepared asynchronously from existing ReaderPage streams. Keep a bounded window of current and neighboring pages. Only commit reading progress when a spread has settled or a seek has been confirmed. A cancelled page grab does not advance progress. A requested page must finish loading before it becomes a readable spread.

Do not substitute a WebView, a stereoscopic phone display, or a separately installed companion app for immersive VR.

## Acceptance on headset

1. Toggle VR on and off repeatedly without resetting the library or losing the current chapter.
2. Open downloaded, local, and source-backed chapters. Resume at the recorded page.
3. Grab either outside page corner; drag across the spine, release halfway, and verify completion/cancellation. Tracking loss must cancel safely.
4. Use controllers for the same operations. Ray selection must not accidentally start a physical page grab.
5. Seek to first, middle and final page, including odd-length chapters and RTL manga. Prev/next across chapter boundaries follows Houri chapter ordering.
6. Move and resize the book; check that ray and pinch hit regions follow the new transform.
7. Switch black/passthrough. Unsupported passthrough must visibly fall back to black.
8. Read for 20 minutes at the headset refresh rate. Check frame timing, texture memory, readable text, tracking, sleep/resume and persistent progress.

## Current status

The feature branch contains the embedded Godot/OpenXR activity, native content bridge, spatial library, deforming book, tracked input, seeker and options. The executable book and input checks pass, including far seeking and tracking-loss cancellation. Spotless formatting and validation pass. A desktop render verified page orientation and aspect preservation.

The nomtl debug Kotlin compilation, Linux Quest APK assembly and APK staging pass. The downloaded APK has a valid v2 signature, ARM64 native libraries and the embedded reader pack. Real Quest acceptance remains unverified. This is an experimental implementation, not a tested 1:1 reproduction of Livro. Its geometry, controls and interaction are independently implemented; no Livro code or artwork is bundled.

The full Windows assembleDebug attempt failed in existing native modules: imagedecoder's native downloads/build and llamatik's missing WSL installation. FlexibleAdapter's unavailable JitPack artifact was replaced by source from the exact pinned commit. The dedicated Linux CI workflow is the APK verification path for this machine.

## Build and checks

Install JDK 21, the Android SDK and Godot 4.6 stable. Set JAVA_HOME, ANDROID_HOME and GODOT_BIN (the engine executable). Initialize recursive Git submodules. Do not edit local.properties. Windows native builds additionally require Houri's WSL toolchain; Linux is supported directly.

Run `./gradlew spotlessApply`, `./gradlew spotlessCheck`, then `./gradlew assembleDebug`. The app's preBuild task exports xr/ into a generated assets/vr.pck; the Meta OpenXR plugin is included in the APK. The Quest VR APK GitHub workflow builds the nomtl debug flavor and uploads the arm64 APK without requiring release-signing secrets. This flavor uses Houri's existing no-MTL engine; the ordinary reader and VR content bridge are shared.

Engine checks: `godot --headless --xr-mode off --path xr --editor --quit`, then `godot --headless --xr-mode off --path xr --script res://tests/book_check.gd` and the same command with `res://tests/input_check.gd`.

Desktop geometry/input preview: `godot --xr-mode off --path xr -- --pages=<image-directory>`. Arrow keys turn pages; the mouse operates spatial controls. Desktop checks do not verify Quest tracking, passthrough, Android lifecycle or headset performance.

The launcher opens the immersive VR activity directly into the room and native frosted library. Home, Source Search and Reader use the Godot workspace rather than an embedded Android app surface. Locomotion is disabled; recenter moves the workspace along the user's full gaze direction, including elevation, without changing the viewpoint. Enable hand tracking in the headset settings. Pinch near an outside page edge to turn; pinch the spine to move the book. Touch controller triggers/grips use the same physical grab regions and rays select controls.

## Quest reader controls

The detailed October 7 video study and gesture mapping are in [BOOK_INTERACTION_STUDY.md](BOOK_INTERACTION_STUDY.md). Closed-cover body pinches now carry the book; the moving outer bar opens and closes its cover. Off-center grabs retain their hand contact through wrist rotation, and direct fingertip touches operate native floating controls. Open-hand sweeps and pinched page-corner pulls remain separate page-turn gestures.

The reader has a rounded title/seeker toolbar, a Book Options popup with a four-icon navigation rail, and a settings page with labeled ringless Touch Plus diagrams and persistent button remapping. Right trigger advances, left trigger goes back, A/X selects with the active pointer hand, grips grab the spine or white page bars, B opens Book Options, Y toggles the library, right stick click recenters, left stick click switches pointer hands, and the left Menu button opens options. Meta remains reserved for the headset system menu. Stick horizontal input turns pages once per deflection; left vertical input adjusts distance and right vertical input adjusts size. Hand tracking retains pinch selection and physical page grabs. Controller buttons provide a short optional haptic pulse.

Controls, physical grab bars, settings construction, and input edge behavior are covered by `xr/tests/controls_check.gd`. Visuals are implemented with Godot rounded StyleBoxes and SVG icons; resemblance to the supplied references is verified with rendered previews, while exact visual parity and tactile feel require headset validation.

Verified build: https://github.com/Kirogii/VR-Tachiyomi/actions/runs/37213188026. Output: `VR-Tachiyomi-Quest3-debug.apk` (278,388,183 bytes). Android Gradle exposes its APK directory through `SingleArtifact.APK`; `:app:stageNomtlDebugQuestApk` stages that directory for CI without assuming an output path.

Android startup uses Godot 4.6.3 because the 4.6.0 Maven template rejects --main-pack. The immersive activity passes both the native --xr-mode on argument and XRMode.OPENXR.cmdLineArg for the Android GL surface, and uses singleTask to avoid duplicate engine startup when Horizon OS relaunches immersive activities.

## Frosted workspace verification (October 6, 2026)

The Home layout follows Reference1's sidebar, lime outline icons, date groups, transparent cover cards and plain captions. Source Search retains its own search field and source selector. Selecting a cover animates a textured physical book into the preview; Save, Read/Resume and Info replace the preview page seeker. Info contains the description and searchable scrolling chapters. Long-strip reading is supported; novel rendering is deferred.

Spotless and the native workspace, library ray input, stationary locomotion, physical controls, book and long-strip checks pass. Desktop library and preview renders are saved under the workspace artifacts directory. These checks do not establish exact visual parity, hand feel or sustained performance inside the headset.

The Windows nomtl APK is packaged using the unchanged ARM64 image-decoder libraries extracted from the preceding local debug APK. All current Kotlin, resources and Godot assets are built normally. A complete native decoder rebuild still requires the project's WSL/Linux toolchain. The staged output is `../artifacts/VR-Komikku-Frosted-Quest.apk` and is installed on the connected Quest. The native Godot and OpenXR plugins initialized during launch; the headset was asleep, so interactive headset acceptance remains pending.
