# Livro interaction reference study — 2026-10-11

## References inspected

- [Casual controller reading video](https://www.youtube.com/watch?v=7eOo9qD8UDE),
  202.63 seconds. Sampled the full duration and inspected the 35–39.5 second
  controller page turn at finer intervals.
- [Hand-tracked reading short](https://www.youtube.com/shorts/A_8q4s0BTpI),
  48.79 seconds. Sampled the full duration and inspected 5–8 seconds more closely.
- User's `C:/Users/Admin/Downloads/Book.mp4`, 54.92 seconds. Inspected the full
  sequence in contact sheets and 8.5–12 seconds at finer intervals.
- [Livro developer's project description](https://www.fmbnicolau.com/projects/livro-xr-reader)
  and [official app page](https://chronicbite.github.io/livro/).

Local analysis frames are in `D:/VR Kommiku/artifacts/livro-video-20261011/`.
They are reference material, not shipped artwork or textures.

## Observations and implications

| Reference / time | Visible behavior | Questium implementation consequence |
|---|---|---|
| Controller video 0–8 s | Library surfaces and an independent book occupy the same space; the book is readable without being welded to the UI. | Keep UI selection, book movement and page movement as separate captures. |
| Controller video 8–35 s | The reader holds a steady, tilted two-page spread. White side rails are unobtrusive; the controller can rest out of the way. | Do not move or turn the book just because a controller trigger is pressed away from a target. |
| Controller video 37.05–37.45 s | A controller approaches the right rail, with purple interaction feedback. | Ray targeting and close contact must both acquire a page, and show a rail highlight. |
| Controller video 37.86 s | A single curved leaf rises through the spread while the bound book stays in place. | Retain the trigger capture throughout motion and animate the leaf from its grabbed contact. Grip remains whole-book movement. |
| Controller video 38.27–39.5 s | The new spread rests flat after the controller passes inward. The book's pose is retained. | Settle one turn on release after the midpoint; never repeat while the trigger stays down. |
| Controller video 42–177 s | Repeated reading pauses and page changes retain a comfortable book pose. | Keep right-stick quick turns available alongside physical grabs. No automatic camera-follow or unsolicited recentering during reading. |
| Controller video 185–194 s | A controller moves/tilts the whole book, revealing the library behind it. | Grip should preserve both translation offset and wrist rotation; distinguish this from a rail trigger grab. |
| Short 0–4 s | A closed cover becomes an open spread. | A closed cover's rail opens the book; open rails must not unexpectedly close it. |
| Short 7.18–8 s | An outlined hand approaches the outer rail and a curved leaf follows inward. | Preserve the existing tracked-hand turning path while adding equivalent controller acquisition. |
| Short 12–44 s | Brief gestures alternate with stationary reading; both edge rails remain available. | Retain both forward and backward rails, including right-to-left reading order. |
| Book.mp4 8.5–11 s | Flexible leaves lift at the spine and settle flat, without making the entire book rigidly flip. | Reuse the existing flexible-page shader and release settling; fix controller routing around it. |
| Book.mp4 11.36–12 s | The rail changes from white to purple during interaction. | Hold the purple highlight for the captured page even after the pointer leaves the original rail. |
| Book.mp4 24–31 s | Several books can coexist and be manipulated independently. | Keep nearest-book targeting and per-book state; don't route every grab to the last active book. |
| Book.mp4 36–45 s | Reading also works in passthrough. | Book controls and spatial UI must work with either the bar scene or passthrough. |

The recordings show interaction results, not controller button telemetry. The
trigger/grip assignments in Questium follow the user's requested trigger behavior;
the exact button map of Livro cannot be proven from these videos. The developer
confirms Touch and hand tracking, physical book manipulation and custom spatial UI.
The video does not supply an editable Livro model or its source code.

## Implemented interaction contract and checks

The [controller guide](CONTROLLER_CONTROLS.md) defines the complete implemented
default map. Trigger presses first select the nearest UI or book target. A trigger
on an open rail acquires its leaf, retains ray distance during the gesture, and
commits only after crossing halfway. Grip captures the body or window handle.
Existing tracked-hand gestures retain their separate paths. Focus/tracking loss
cancels capture.

`tests/livro_controller_check.gd` exercises distant trigger capture, early release,
forward and backward commits, stationary book pose, tracking loss, real Search
button clicks, fingertip presses and keyboard submission, stale-result rejection,
supersampled UI coordinates and startup heading. Existing control, hand, remote
grab, layout and locomotion checks cover the connected paths.

Headset feedback exposed a controller-only discontinuity: a lateral ray drag
stays on the page plane, so its angle jumps at the spine. Controller progress
now follows horizontal travel from the acquired rail; tracked fingers retain
their angular curl. The check compares intermediate progress in both directions
and verifies persisted source/LTR/RTL overrides.

## Rendering findings

The previous room shader deliberately quantized lighting into five levels and
added world-tiled Bayer noise. The previous shaft used only 12 noisy samples and
disabled hardware depth testing. UI fallback glass sampled a copied screen texture
25 times. Those mechanisms can add grain, aliasing or unstable transparent-layer
feedback independently of the headset display resolution.

Questium now uses smooth lighting, stable 24-sample shafts, an eye-specific camera
transform, hardware depth testing plus scene-depth clipping, and beams bounded to
their receiving furniture/floor. The regression render checks that an opaque box
fully blocks a beam while unobstructed rays remain visible.

UI textures render at 2x their logical dimensions, preserving existing hit
coordinates. Eye targets use 1.5x the runtime recommendation, requesting 8x MSAA
(Godot clamps this to the driver's supported sample count), 16x anisotropy and
full-resolution periphery. Godot 4.6's
[OpenXR implementation](https://github.com/godotengine/godot/blob/4.6/modules/openxr/openxr_api.cpp)
recreates changed swapchains in `pre_render()`; this was checked against source
because the interface documentation's initialization note is restrictive.
[Godot's viewport documentation](https://docs.godotengine.org/en/4.6/classes/class_viewport.html)
describes logical-size stretching/font oversampling and MSAA tradeoffs.

Pages, scrolling strips and cover shaders explicitly select anisotropic mipmap
sampling. A project-wide anisotropy setting alone does not change shader samplers.
Android reads `GL_MAX_TEXTURE_SIZE` on the render thread and retains source detail
up to that dimension, including the AI output scale. Each output page is bounded
to 16 megapixels (about 86 MiB of RGBA plus mipmaps); long chapters use separate
strips rather than one huge GPU texture. Display caches remain lossless PNG and
runtime page textures remain uncompressed. These higher settings still need
frame-time and thermal verification on Quest; the measurements below describe
the earlier 1.25x/4x build.

These changes remove avoidable software artifacts. Physical screen resolution,
lens clarity and content resolution still limit detail; headset frame times and
the feel of controller drags require live hardware confirmation.

## Headset verification, 2026-10-11

The installed build reports 2730×2860 eye targets, 4x MSAA and disabled foveation.
After avoiding updates of hidden panels, the app's own VrApi telemetry reached
70–73 frames per second at a 72 Hz target in the observed view; this does not
guarantee that rate for every view or during page inference.

AI upscaling was enabled in preferences, but the headset's model directory was
empty and cached page dimensions matched the source. Installed the configured
Real-CUGAN 2x ONNX model/data using the manifest's exact SHA-256 hashes. The
on-device `VrUpscaleProbe` then passed real inference through `VrPageUpscaler`
for both book pages and padded long-page strips. Its temporary test preferences
are restored in `finally`; individual books still use their own upscale toggle.
