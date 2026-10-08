# Spatial reader settings in v1.0.1

The frosted settings hub uses the same preference store and callbacks as Houri. A shared preference only changes VR when the spatial renderer or its Android data loader consumes it. Android-only viewer controls are disabled and labeled in the Reader category instead of silently saving an ineffective value.

| Settings | Spatial behavior |
| --- | --- |
| Global upscaling, per-book opt-in, mode, factor, model, preset, backend and cache | Both book leaves and long-page strips use the shared upscale engine. Book Options contains Upscale Manga. Native mode uses real ONNX inference in the Quest flavor; Simple mode is ordinary resizing. Models must be downloaded first. |
| AI backend | ONNX CPU is available; NNAPI is attempted when supported, with CPU fallback. Quest's no-translation flavor does not include NCNN/Vulkan. The downloader fetches ONNX artifacts for this flavor. |
| Live AI/crop changes | Processing settings and model readiness identify a new render revision. Visible pages are re-requested without closing the book or resetting the seek position. Results from an obsolete revision are ignored. |
| Long-page AI | Width-preserving strips remain bounded for GPU textures. Inference includes neighboring padding, then trims that padding before display. The source's page geometry and strip positions are retained; failed processing displays original pixels. |
| Color filter, ARGB blend mode, hue, grayscale, inversion, brightness and contrast | Shared shader controls apply to both fixed leaves, the curling leaf, and long-page strip surfaces. Contrast uses the shared WebGPU contrast preference. |
| Border cropping | Paged and long-page switches remain separate. Crop bounds are found on a bounded thumbnail, retain a safety margin, and are applied in texture coordinates. Strip sampling and scroll height account for the cropped extent. Source files are untouched. |
| Image scaling | Fit, stretch, fit width, fit height, original size, and smart fit affect the book's image placement. Original size uses a fixed spatial pixel density; it is independent of AI output resolution. |
| Long-page aspect and side padding | Changes the content width and scroll geometry within the physical window. |
| Reader background, page numbers and page transitions | Background controls the paper margin. Page numbers appear on the hand seeker. Disabling pager transitions removes the automatic settling animation; a manually dragged page still follows the hand. |
| Preload size | Controls nearby page requests, capped at ten for Quest texture memory. The current spread and pending seek are retained. |
| Default reading mode, skip read/filtered/duplicate chapters, history, downloads and source loading | The existing ReaderViewModel and loaders consume these shared settings. Book Options can force two-page or long-scroll display. |
| Keep screen on | Updates the Android activity's keep-screen-on flag. It does not disable Quest presence or guardian behavior. |
| Phone orientation, cutouts, 2D tap zones/zoom, volume-key mapping, WebGPU-only renderer effects, chapter transition cards and other Android-only viewer behavior | Labeled Android reader settings and disabled in the VR Reader category. VR uses tracked gestures, controller mappings, physical book sizing and Book Options. Translation/MTL and novels are not part of the Quest APK. |

Validation includes the full standalone APK build, Kotlin crop/split tests and the Godot reader/interaction suite. A debug-only `vr_upscale_probe` runs real Real-CUGAN inference through the same VR image writer for both leaves and a padded strip, then restores user preferences. Continued physical headset testing is required for gesture comfort and native keyboard behavior.
