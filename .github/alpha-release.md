# Questium v1.0.0 - First Release

This is the first release of Questium, bringing the current spatial manga reader and hand controls to Quest 3 and Quest 3S.

**Alpha testing disclaimer:** Most features are added, but the application is still in alpha testing. Expect bugs and unfinished behavior. This is published as a regular GitHub release so it is easy to find; that does not mean the app is production-ready.

- Adds reading History for library and non-library books, refreshed centered transparent Questium branding, and application screenshots with animated hand gesture tutorials in the README.
- Includes the local Quest interface and interaction fixes: frosted library and settings, native keyboard input handling, fingertip taps, centered draggable popups, chopping page turns, and the palm-facing non-dominant-hand seeker.
- AI upscaling now runs in the spatial two-page book and long-page reader. Enable it globally in Upscaling settings, download the models, select Native mode, and enable **Upscale Manga** in each book's options. Simple mode performs ordinary resizing rather than AI inference.
- The Quest build includes ONNX CPU inference with NNAPI acceleration when supported. Unavailable accelerators or failed inference fall back safely; Vulkan/NCNN and translation are not included in this APK.
- Corrects the external-data filenames used by Real-CUGAN and Real-ESRGAN ONNX models, preserving previously downloaded weights.
- Reader color controls, border cropping, page scaling, scroll aspect/padding, page transitions, preloading, and keep-screen-on now reach the VR reader. Settings for the Android-only viewers are labeled and disabled in the spatial settings hub. See [reader settings support](https://github.com/Kirogii/VR-Tachiyomi/blob/master/docs/VR_READER_SETTINGS.md) for scope.
- Merges the original Houri fork through v1.23.12, including cover updates, extension handling, and long-page/graphics memory fixes.

Install **VR-Tachiyomi-alpha.apk** on Quest 3 / 3S. This development-flavor APK retains the existing application ID and signing key, allowing an update over the previous signed alpha without clearing its library. Novel support is deferred. Natural hand feel and every native-keyboard interaction still need continued headset testing.

### Glass and book controls

Camera-backed glass on Quest 3/3S requires camera permission; frames are blurred in memory and never saved or uploaded. Room-color blur approximates passthrough rather than providing exact stereo alignment. Book settings now have swipeable sections, palm hide/restore, and a hardcover option. Tutorials use outlined hands, actual book controls, and abstract sample pages.
