# Book.mp4 interaction study — October 7, 2026

The supplied recording is 54.917 seconds at 24 fps, 1280 × 720. I inspected half-second samples across the entire video and every second frame (12 samples per second) around the opening, forward/reverse page turns, body grab, closing, carry and reopening sequences. Contact sheets are saved in `../artifacts/book-motion-study/`.

| Time in clip | Visible behavior | Implementation |
|---|---|---|
| 5.00–6.00 s | Right outer bar highlights purple. A pinch pulls the rigid front cover across the spine to the left; the book body stays in place. | A dedicated cover handle follows the hinge throughout opening. The acquisition angle is subtracted to prevent an initial jump. |
| 8.33–8.75 s; 8.92–9.25 s | An inward hand motion near the outer page lifts and curls a leaf across the spine. | Unpinched tracked fingertip sweeps drive continuous page curl in book coordinates. An edge approach and inward travel establish intent. |
| 10.33–10.83 s | A motion from the left turns a leaf in the reverse direction. | Either hand can start at either outer edge. Physical direction maps through the chapter's reading direction. |
| Around 21 s | An index finger reaches the floating page control and its selected state changes. The recording does not establish the exact activation depth. | Native controls accept direct fingertip approach/touch/withdraw gestures as well as pointer pinch. |
| 26.46–27.46 s | Pinching the middle of the closed cover carries the entire book. Releasing leaves it floating at the placed pose. | Closed-cover interior is a body-grab target. Translation and wrist rotation preserve the local grabbed point. No gravity or release throw is applied. |
| 37.08–37.67 s | Left bar highlights; a pinch pulls the open front cover back to the right. Cover art becomes visible outside. | The same moving handle closes the book from its left edge. Inside paper and stack follow the cover, while the body remains fixed. |
| 38.25–44.17 s | The closed book is carried around the room. Other hand gestures do not obviously resize it. | A second hand must newly pinch the same book to join a grab. Distant pinches have no effect. Existing two-hand resizing preserves pose on either hand's release. |
| 44.67–45.33 s | Right outer bar highlights again and the cover reopens. | Handle remains attached to the closed cover and supports repeated open/close cycles. |
| Throughout | Idle hand outlines and inactive bars are white; active grabs and selected bars are purple. | Native tracked hand material uses white idle outlines and purple active feedback. Both hands contribute to hover; one cannot erase the other's highlight. |

## Gesture behavior

- Sweep an open hand inward over an outer page to turn it. Cross the midpoint to commit; retreat before the midpoint to cancel. The return stroke is ignored; reaching the original outer edge re-arms another forward turn. Leaving the interaction region also permits a fresh gesture from either side.
- Pinch an outer page corner to pull the leaf directly. Pinch the thin moving cover bar to hinge the cover. Pinch the cover/body interior to carry the book.
- The body follows the hand's pose around the actual contact point. Releasing leaves the book in place. Tracking loss cancels an incomplete page/cover gesture; a second valid carrying hand can keep hold of the body.
- Point and pinch still selects distant UI. Nearby native buttons also accept a fingertip touch followed by withdrawal. Tracking loss, leaving the control bounds, or hiding the panel cancels a touch without activating its button.
- Long-strip content keeps its scroll interaction; page sweeps do not operate on a preview cover or a long-strip reader.

## What the recording cannot establish

These are independently implemented behaviors, not recovered Livro source code or its original model. A single rendered video cannot reveal exact joint trajectories, depth thresholds, filtering, collision volumes, prediction, or haptic parameters. Perspective and video edits prevent reliable recovery of physical dimensions or full motion timing. The apparent page turns span roughly 0.3–0.5 seconds in the inspected sequences; our leaf follows the hand and uses a short remaining-distance settle after release.

Pinch thresholds (22 mm acquire, 32 mm release), the page intent gate, cover hit radius and touch depth hysteresis are implementation choices. Two-hand scaling is retained from the existing app; its precise behavior is not established by this clip. These values need interactive Quest testing to judge comfort and tracking robustness. Desktop pose tests and rendered frames verify behavior and geometry, not perfect headset parity.

## Verification

`book_interaction_check.gd` checks rigid off-center wrist grabs, closed-cover carrying, repeated right-bar opening/left-bar closing, half-open handle reachability, distant-pinch isolation, ownership transfer and tracking loss. `hand_touch_check.gd` checks actual native button activation, exclusive capture, cancellation, pinch exclusion and book occlusion. Existing book, input, controller, hand-sweep, tracking, remote-grab and frosted-workspace checks cover the surrounding flows.

`hand_sweep_render.gd -- --cover` renders closed, partly open and fully open poses using simple generated page fixtures, not artwork taken from the reference video.
