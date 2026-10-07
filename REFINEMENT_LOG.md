# VR reading refinement — October 7, 2026

Requested two-hour work window: 12:23–14:23 UTC. Focus: thin Livro-like book,
Quest 3S hand visibility, hand controls, and relevant VR reading TODOs.

## First pass

- Reduced cover thickness from 9 mm to 0.7 mm and page-stack thickness from 18 mm to 1.6 mm at the book's base scale. Reduced resting page angle from 0.20 to 0.035 radians and removed the large spine.
- Replaced the turning sheet's predominantly rigid rotation with a curved tangent integrated along its width. The rest spread stays flat; the turn supplies depth.
- Added compatible skinned fallback hands from the official Godot hand-tracking demo, with license and pinned source attribution. Native meshes remain preferred when ready.
- Corrected hand visibility gating for an unspecified runtime source; finger occlusion now disables acquisition without erasing a valid palm/hand. Controller-inferred tracking remains excluded from natural-hand gestures.
- Verified both fallback skeletons with simulated poses and inspected rendered hands, flat covers and curled pages. These checks do not prove live Quest tracking quality.
- Existing cover, body-grab, page-sweep and controller checks pass after the geometry changes.

The earlier full APK build passed before this refinement request. The next build
must include the thin-book and hand-visibility changes before it is delivered.

## October 7 passthrough and interaction correction

- Removed the procedural room from startup. Enabled alpha-blended passthrough and a 42% black translucent background sphere, behind all virtual controls/content.
- Reduced physical preview scale from 1.8 to 1.05 and reader scale from 1.3 to 0.85. Shortened/repositioned preview actions and the title badge; moved Info outside their bounds. Each preview gets a separate untokened book, leaving older readers hidden and restorable.
- Book options scroll within a fixed panel, bound long titles to one ellipsized line, and pin Close Book/Edit Settings outside the scrolling area. Forced book/scroll modes persist in reader configuration and survive chapter entry.
- Quest native keyboard uses the system overlay feature, focusable Android EditText and InputMethodManager. Fields open it directly and receive session-tagged text updates. Removed the custom key grid and keyboard buttons. A desktop check validates response routing; the OS keyboard still needs live headset typing acceptance.
- Added curled-finger fist acquisition/release hysteresis for carrying a book, opposed top-corner pinches for resizing closed/open physical books, and unpinched fingertip swipes near the long-page surface. Resizing excludes long-page windows. Refined sheet bend/twist for a flatter Livro-style curl.
- Palm guide follows the non-dominant hand with a stricter facing cone and hides immediately when the palm faces away. OpenXR pose_recentered and in-app recenter cancel captures before moving HUD/book; reading recenter reveals the HUD and puts the book beside it.
- Source picker presents icon/title rows with scrolling and filtering. Its shop action opens searchable available extensions and uses the existing extension installer. Actual installation retains OS package-confirmation behavior and repository configuration.
- Desktop checks passed: hand_controls_check, preview_input_check, frosted_check, book_check, hand_sweep_check, hand_touch_check, palm_check, input_check, book_interaction_check, tracking_check, scroll_check. Rendered preview verified cover/action/Info separation. Android Spotless checks and APK build passed; final packaging follows the last Godot spacing/recenter refinements.
- Native keyboard integration follows Meta's system overlay documentation: https://developers.meta.com/vr/documentation/native/android/mobile-keyboard-overlay/

Final APK packaging passed (2m 38s); installation on Quest serial 340YC10GBQ0FJN succeeded. Headset power status returned Asleep after launch, so live passthrough/keyboard/hand acceptance remains unverified. APK ZIP integrity check passed.

## Reach and hand-gesture refinement — 2026-10-07
- Library HUD defaults to half scale at 0.62 m, supports opposed top-corner resizing, and follows back into view after an idle dwell. Following pauses during captured interactions. Thumb-up fists in open space adjust workspace depth.
- Open edge-on hands use the palm for white-bar inward page sweeps. Slow gestures settle at the center; fast inward travel completes early. Long mode supports the same side-bar gesture independently of vertical fingertip scrolling.
- Extended index detection, wider long-page capture and accumulated small vertical motions improve slow scrolling. Natural-hand page scrolling does not carry the book body.
- Hand rays use the native aim pose or wrist-to-knuckle forward direction, retaining direction through pinches. Procedural controllers remain visible until native render models load.
- Source-language cog filters installed sources and invalidates disabled selections. English is enabled by default; choices persist.
- Passed desktop regressions: reference flat-hand pose, slow and fast bar gestures, reach controls, native HUD/preview flow, tracking, physical-book controls, real hand sweeps, long scrolling and preview input.
Final validation: spotlessCheck and APK assembly passed (4m 58s). APK ZIP integrity passed; reach_controls_check and bar_hand_check passed against the actual embedded VR pack. Updated APK installed successfully on Quest 340YC10GBQ0FJN. Live hand acceptance remains required because the headset is asleep.
Release refinement: canceled stale builds at user request, removed automatic view following, added fist dragging for HUD/popup interiors, independent options, topmost popup rendering/input and fixed Close controls. Desktop popup, preview, reach, manual recenter, remote and palm regressions passed.
