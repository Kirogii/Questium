# Quest VR reader

Target: Meta Quest 3 / 3S, standalone. Reference: the user's 55-second Livro video and six screenshots.

## Required experience

- Settings switch enters immersive VR; leaving VR returns to the ordinary Android app.
- A spatial library with covers, categories, chapter selection and resume-reading.
- A movable, rotatable, resizable physical book with two textured pages, covers, a spine and page thickness.
- Pages curl continuously while grabbed, follow the fingers, and settle forward or back when released. Both hands and Touch controllers work.
- Toolbar below the book: library/menu, previous spread, page seeker, next spread, recenter and book options.
- Book options: size, distance, tilt, left/right reading direction, passthrough or completely black surroundings.
- Existing Houri sources, local content, downloads, reading progress and trackers remain the content backend.

## Integration

Embed Godot's Android library in a dedicated immersive activity in the same APK. Use OpenXR and the official OpenXR Vendors Meta plugin for Quest. A runtime Godot plugin connects the spatial UI to Houri's existing domain interactors and ReaderViewModel; source credentials never leave the application.

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

The nomtl debug Kotlin compilation also passes. Full APK assembly and real Quest acceptance remain unverified. This is an experimental implementation, not a tested 1:1 reproduction of Livro. Its geometry, controls and interaction are independently implemented; no Livro code or artwork is bundled.

The full Windows assembleDebug attempt failed in existing native modules: imagedecoder's native downloads/build and llamatik's missing WSL installation. FlexibleAdapter's unavailable JitPack artifact was replaced by source from the exact pinned commit. The dedicated Linux CI workflow is the APK verification path for this machine.

## Build and checks

Install JDK 21, the Android SDK and Godot 4.6 stable. Set JAVA_HOME, ANDROID_HOME and GODOT_BIN (the engine executable). Initialize recursive Git submodules. Do not edit local.properties. Windows native builds additionally require Houri's WSL toolchain; Linux is supported directly.

Run `./gradlew spotlessApply`, `./gradlew spotlessCheck`, then `./gradlew assembleDebug`. The app's preBuild task exports xr/ into a generated assets/vr.pck; the Meta OpenXR plugin is included in the APK. The Quest VR APK GitHub workflow builds the nomtl debug flavor and uploads the arm64 APK without requiring release-signing secrets. This flavor uses Houri's existing no-MTL engine; the ordinary reader and VR content bridge are shared.

Engine checks: `godot --headless --xr-mode off --path xr --editor --quit`, then `godot --headless --xr-mode off --path xr --script res://tests/book_check.gd` and the same command with `res://tests/input_check.gd`.

Desktop geometry/input preview: `godot --xr-mode off --path xr -- --pages=<image-directory>`. Arrow keys turn pages; the mouse operates spatial controls. Desktop checks do not verify Quest tracking, passthrough, Android lifecycle or headset performance.

On Quest, launch the normal Android app and choose Settings → Virtual reality → Enable VR. Enable hand tracking in the headset settings. Pinch near an outside page edge to turn; pinch the spine to move the book. Touch controller triggers/grips use the same physical grab regions and rays select controls. Exit VR returns to the normal app after saving reading progress.
