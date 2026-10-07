# Livro reference study and VR interaction implementation

## Reference and evidence

Reference: `C:/Users/Admin/Downloads/Book.mp4`, 54.92 seconds, 1280 × 720, 24 fps.
Reviewed the entire clip using two-second samples and half-second sequences for
opening, controls, manipulation and passthrough. Study frames are in
`D:/VR Kommiku/artifacts/livro-study/`. The supplied library images are a separate
visual reference; images 3 and 4 are identical.

| Video time | Observed behavior | Implementation target |
|---|---|---|
| 2–4 s | Pale spacious room, gray plank floor, tall bright windows, draped window edges | Rebuild architecture only: walls, floor, window frames and blinds/curtains; exclude all furniture |
| 4–6 s | Closed hardback floats in space; hand brings the front cover open | Closed/open cover state, cover edge grip, continuous hinge motion and settling |
| 6–12 s | Two page leaves, gentle gutter, visible thickness, curved page traveling across the spine | Real dimensional book, textured covers, physical drag-driven turn with reversible release |
| 13–15 s | Cover image, small close control, palm-facing compact toolbar | Close per book; toolbar hidden until palm faces head, stable pose and dismissal hysteresis |
| 15–19 s | Book opens and successive textured leaves turn | Preserve page direction, preload destination pages and block unloaded turns |
| 19–23.5 s | Title above menu/back/slider/forward/book controls; pointer hover highlights | Matching compact hierarchy, progress seek and explicit book/scroll-window override |
| 25–30 s | Library stays available; several books remain open in the scene; hand repositions one | Persistent workspace and movable independent book instances; active book supplies controls |
| 30–33 s | Books stay in world positions as the viewer looks/moves around | World anchored objects, room-scale movement and optional controller locomotion |
| 34–47 s | Same books in real surroundings, outlined tracked hands, physical cover/page interaction | Passthrough switch and native Meta hand meshes; joint-based fallback matching dark/outlined reference |

The clip does not expose exact gesture thresholds, hidden settings, collision
rules, source browsing, three-window docking or long-strip handling. These are
specified below from the user's instructions, with tunable thresholds. Visual
and interaction parity is a target that must be checked on the headset; sampled
video alone cannot establish identical feel or recover the original 3D assets.

The frame study also shows several details that guide the interaction code: the
closed cover is held at its lower-right edge, the first opening is a continuous
hinge motion, page turns begin at the outer white page edge, and the toolbar
appears in the lower reading band near the palm. The sampled frames do not
establish its exact attachment; our implementation follows the requested
above-palm placement. The toolbar is a dark rounded capsule with menu/back controls, a page
slider, forward control and book/options button. The reader briefly shows an
angled contents page before textured manga pages, then keeps the same book and
toolbar spatially stable while the camera moves.

## Complete book-system study

### 0–3 seconds: spatial setup

The camera begins in a large gray living room. The floor has broad, alternating
wood planks. Bright tall windows sit between heavy curtains, and the room has a
fireplace, shelves, chairs and tables. The book system is already designed to
float independently of the room: there is no desk, stand or collision surface
supporting it. The final product request removes the furniture while retaining
the architectural envelope.

### 4–6 seconds: cover acquisition and opening

The closed book appears as a thick dark hardback, angled slightly toward the
viewer and below eye level. A tracked hand reaches to the lower/right cover
edge. The cover follows the hand around a spine hinge instead of teleporting or
switching between two poses. The book starts nearly vertical, the cover rotates
away from the viewer, and the first white page becomes visible. The hand stays
close to the physical edge during the motion, with a thin interaction ray shown
beside the book.

Required states:

1. Closed: dark cover, visible thickness and a small close `X` near the upper
   corner.
2. Held-open: cover angle follows the hand continuously.
3. Settled-open: two leaves are exposed with a visible gutter and edge bars.
4. Cancelled: releasing before the midpoint returns to closed; releasing after
   the midpoint completes the opening.

### 6–13 seconds: page object and turn mechanics

The open book is a two-page object with a shallow curved gutter. Each page is
white before content arrives, then receives a full-page image. Turning starts
from a narrow outer page edge. The page bends through the air around the spine;
it is visibly a surface with thickness and shadow, not a flat image replacement.
The user can reverse a partial turn by moving the hand back. A turn settles only
after crossing a midpoint. On completion, the next spread replaces the old one
and the hand interaction is ready immediately.

The video shows both ordinary comic pages and a contents/index spread. The
reader must therefore treat every page as image content while allowing any
chapter page to be a contents page. Page direction is right-to-left for manga,
and the visible order must be reversed without reversing the physical hinge
motion.

### 13–15 seconds: reader chrome

The cover and book are centered ahead of the viewer. A small dark `X` sits near
the book's upper-right corner. A dark rounded toolbar appears in the lower
reading band. It contains, in order, a menu button, previous control, title,
page position/slider, next control and a book/options button. A thin caption
bar can appear beneath it. Its exact attachment is uncertain from the footage;
the implementation anchors it above the palm and stabilizes it during selection.

The toolbar is hidden during normal reading. It appears after the left palm is
turned toward the viewer and remains visible briefly after the palm turns away.
Hovering a control changes its highlight color. Pinch or controller trigger
activates the control. The slider supports direct seeking and displays a blue
thumb/hover state.

### 15–24 seconds: reading sequence

The selected cover changes to a contents page, then to colored and black-and-
white manga spreads. Page images remain sharp and fill the physical leaves.
The reader does not replace the world with a full-screen HUD. The room, book,
hands/rays and lower toolbar remain visible together. The toolbar stays at a
stable distance while the viewer looks around.

### 24–33 seconds: library and multiple books

The library is a separate floating panel with a dark translucent rounded frame.
It shows a vertical navigation rail and selectable rows/cards. Selecting a
title leaves the library visible while a colored cover/book appears in front of
the viewer. Several previously opened books remain suspended around the user;
the newest book becomes active without destroying the others. Each book has its
own close `X`, pages and world transform.

The user can reach toward a book, grab its body or cover, and move it to a new
position. The book follows the hand with position and rotation, then remains
where released. Two-hand scaling and dock-only recentering are implementation
requirements; their exact behavior is not established by the sampled footage.

### 34–47 seconds: passthrough reading

The virtual room fades to the real environment while the book, pages, toolbar,
close control and interaction rays remain rendered. The book cover is still
colored and opaque over the grayscale passthrough camera. Real hands are visible
as dark silhouettes with bright outlines. The user opens the cover and turns
pages in passthrough with the same edge interactions as in the virtual room.

The passthrough transition must preserve object transforms and page progress.
Returning to the virtual room restores the room without recreating books. If
the runtime cannot provide Meta's hand mesh, the fallback is joint spheres and
outlined palm/finger geometry with the same pinch and edge interaction points.

### 48–55 seconds: exit/logo

The final frames blur the reading scene and show the Livro logo. This is an
outro presentation state, not part of the reader's input model.

### Interaction contract derived from the study

- Books are independent world objects with persistent transforms.
- Cover grab, page-edge grab, body grab, two-hand scale and controller grip are
  separate interaction modes with explicit capture and release.
- Partial cover/page gestures settle by midpoint and can be cancelled.
- UI capture suppresses page/body interaction until release.
- The palm gesture reveals the toolbar; the requested placement is above the
  palm, with selection stability while the other hand interacts.
- Every page turn preserves aspect ratio and image sharpness. Tall pages use a
  large scrollable window with vertical hand drag and up/down controls.
- Library visibility, book visibility, passthrough state and progress are
  independent state variables.
- Recenter affects docked windows only. It never relocates free windows or
  placed books.

## Hand-to-page responsiveness study

The finer 200 ms frame pass is stored in `artifacts/livro-study/hand-detail/`.
It shows that responsiveness comes from contact capture rather than from a
large cursor button. The purple ray ends at the index fingertip, while the
hand model remains visible beside the page. The fingertip approaches the cover
edge, the hand closes into a pinch/grab, and the book immediately enters a
captured state. After capture, small hand movement produces continuous cover or
page motion; the ray is no longer the thing that moves the page.

### Cover contact

At roughly 5.0–6.6 seconds, the index fingertip approaches the lower/right edge
of the closed cover. The cover is not activated from its center. Capture begins
only when the fingertip is close to the edge and the pinch closes. The cover
rotates around the spine as the hand moves laterally and slightly upward. The
cover follows every sampled movement, including the first few degrees, with no
visible dead zone. When the hand releases, the cover settles to the nearest
closed/open state. The implementation must keep the hand as the owner until
release, even if the fingertip briefly leaves the thin edge collider.

### Page contact and curl

At approximately 17.5–19.5 seconds, the hand reaches the outer page edge. The
first visible response is a narrow lifted edge, followed by a curved leaf
traveling over the gutter. The page image stays attached to the moving surface;
it does not fade out or swap at the start of the gesture. The hand can remain
near the lower outer edge while the upper half of the page bends progressively.
The turn crosses the gutter around its midpoint, then settles into the next
spread. Releasing before that midpoint returns the leaf to its original spread.

At 19.5–23.7 seconds, repeated turns are available immediately. The hand can
grab either outer edge according to reading direction. The slider and page
buttons do not interrupt the physical page state; after a UI seek, the new
spread is ready for another edge grab.

### Passthrough contact

At 42.0–47.0 seconds, passthrough makes the hand silhouette easier to read. The
book remains fully opaque and colorful while the real room is grayscale. The
hand reaches toward the cover, closes around the edge, and opens it with the
same response as in the virtual room. During the page turn, the hand and ray
remain visible in front of the page. This implies an interaction/depth order of
hand, ray and book over the passthrough layer, while the virtual room is hidden.

### Timing and capture requirements

- Use fingertip-to-surface distance for acquisition; do not require a ray hit
  after the pinch has already captured the object.
- Start capture on the pinch transition, not while the finger merely hovers.
- Keep capture ownership stable until pinch release or tracking loss.
- Sample hand movement every frame and map it directly to cover angle, page curl
  progress or scroll offset.
- Use hysteresis for pinch distance so a noisy Quest hand does not release the
  page mid-turn.
- Use midpoint settling for both cover opening and page turning.
- Cancel the active gesture on tracking loss, app pause or UI takeover.
- Keep the interaction bars thin and close to the page edges, matching the
  video’s narrow white edge guides.
- For controllers, use the same capture state and edge regions; the trigger or
  pinch is only the acquisition signal, while aim/grip pose supplies movement.

The video does not provide numerical millimeter thresholds or frame-perfect
latency measurements. The code therefore exposes the contact widths, pinch
distances, midpoint and settle durations as refinement parameters to tune on a
Quest 3S against the captured reference behavior.

### Evidence limits and refinement list

The MP4 does not reveal exact world dimensions, gesture angle thresholds,
collision geometry, loading delays, source APIs, or the implementation of the
original hand mesh. Those values are tunable implementation parameters. Quest
testing is required to refine page curl amplitude, midpoint timing, palm dwell,
ray length, panel depth ordering, hand appearance, passthrough brightness and
the spacing of multiple books. The current code records these as refinement
items rather than treating the sampled frames as proof of exact 1:1 parity.

## Workspace and windows

- Start with three curved-around-the-user docking positions: sources/search on
  the left, library in the center, manga details/chapters on the right.
- Keep library available when a chapter opens. Spawn the reading object below
  the window band, rather than replacing the library with a reader screen.
- Drag windows by their frame/handle, preview the nearest empty dock, snap on
  release; a deliberate move away from a dock leaves the window free in space.
- Recenter moves the window arrangement only when explicitly requested. Books
  retain their world positions and never follow head movement automatically.
- Allow several books to remain open. Selecting/grabbing a book makes it active;
  closing one saves progress and removes only that object.
- Maintain app capabilities: installed sources, source search/filtering, manga
  details, chapter selection, library categories, updates/history/downloads,
  extension management and settings must remain reachable. Reuse the Android
  app services and screens rather than replacing working data flows with mocks.
- Use the screenshots' rounded frosted panel, understated borders, spacious
  sidebar, cover tiles, restrained lime accent and clear search controls.
  Frost should blur the scene behind each panel and keep text opaque/readable.

## Book behavior

1. A loaded chapter creates a cover-bearing hardback. Support open/closed state
   without losing reading position; the cover pivots around the spine.
2. Pinch an outer page edge to start a turn. The grabbed leaf follows the hand
   around the spine with a curved surface; release past the midpoint commits,
   otherwise the leaf settles back. Mirror this behavior for RTL manga.
3. Grip the book body/spine to translate and rotate it, maintaining the original
   grab offset. Release freezes it at that pose, matching the video.
4. Two-hand body grip adjusts scale from hand separation while keeping the
   midpoint and rotation stable; clamp to comfortable physical bounds.
5. Edge hover highlights the narrow grab bar. UI interaction, page turning and
   body manipulation must have separate capture rules, with cancellation on
   tracking loss, app pause, book close or chapter replacement.
6. Progress is attached to the chapter/reading object. Returning to a placed book
   resumes its page and mode. Keep GPU textures bounded to nearby pages.

## Long pages and scroll-window mode

- Prefer chapter reading metadata (webtoon/continuous vertical) when available.
- Also inspect original decoded image dimensions. If height/width exceeds 2.2,
  automatic mode chooses a large scrollable window instead of shrinking the full
  image onto a conventional page. Ordinary portrait manga stays in book mode.
- Scroll window fits page width, crops vertically and scrolls through content at
  readable scale. Preserve original dimensions even when the Android bridge
  samples a large image for decoding; avoid an aspect ratio decision based on
  a distorted thumbnail.
- Pinch-drag on the screen scrolls. Stick up/down scrolls smoothly; page/chapter
  boundary transitions preserve continuity. Never turn a long strip into a
  stretched double-page image.
- Toolbar offers Auto / Book / Scroll window so users can override mixed-content cases.
- Book and scroll window share move, rotate, resize, close, progress and chapter actions.

## Hands and palm toolbar

- Use the runtime's Meta hand mesh with correctly bound XRHandModifier3D tracker
  and skeleton. Do not overlay visible joint spheres on a valid native mesh.
- In passthrough, offer a hand-shaped holdout so real hands show through virtual
  content where supported; otherwise retain the native tracked hand mesh.
- If native mesh support is unavailable, render connected finger/palm geometry
  with the dark surface and pale/purple interaction outline seen in the video.
- Palm normal facing the head, adequate tracking confidence and a short dwell
  reveal the toolbar. Use different reveal/hide thresholds to prevent flicker.
- Anchor toolbar just above the palm and orient it toward the eyes. Keep it
  stable while the other hand clicks. Looking away or turning the palm away
  dismisses it after a grace interval. Hidden is the default.
- Controller fallback: menu button reveals the same toolbar; sticks and triggers
  remain usable without hand tracking. Input capture prevents accidental turns
  while selecting toolbar buttons.

## Room and movement

- Approximate the clip's large rectangular pale-gray room, gray alternating wood
  planks, tall luminous windows with cross mullions and gathered curtains/blinds.
- Include no chairs, tables, fireplace, shelves, rugs, lamps or ornaments.
- Use shared geometry/materials and modest lighting suitable for Quest 3S.
- Room-scale walking always works. Controller left stick supports walking and
  snap turn; right stick is reader scrolling in scroll-window mode. Keep user height
  from tracking, and avoid moving the headset vertically during locomotion.
- Passthrough hides the virtual room while retaining placed reading objects and
  windows. Switching back restores the same world layout.

## Implementation sequence and acceptance

1. Reference study and this plan before scene changes. **Study complete.**
2. Book/scroll-window reader model and page classification; regression tests for tall
   images, aspect preservation, mode override, scroll clamping, RTL page turns.
3. Physical object manipulation, cover opening, two-hand scaling, palm toolbar,
   native hand rendering and capture tests.
4. Persistent three-window workspace and frost styling without losing Android
   source/library capabilities; docking and retained-book state tests.
5. Room architecture and locomotion, followed by desktop rendered visual review.
6. Required Spotless checks for Kotlin/XML, relevant Godot tests, full Android
   build, APK installation when the device is connected, headset logging.
7. Compare headset behavior against the video: opening/closing, page grip,
   midpoint release, body movement, scaling, persistent books, palm reveal,
   window scrolling, library/source search and the unfurnished room. Record remaining
   differences here, rather than claiming unverified 1:1 parity.

## Status

- Implementation tracking now lives in `TODO.md` in this document's section
  order. Interaction/functionality comes before mesh refinement.
- Desktop checks pass for book turns/RTL/loading/seeking, input capture and
  two-hand resize continuity, controller settings/grabs, tracked-head placement,
  and three-window/persistent-book workspace behavior.
- Cover/page acquisition uses the initial contact angle to avoid jumping on
  pinch. Tracking loss restores interrupted cover grabs. UI routing chooses
  the nearest visible panel and placed books block clicks through to windows.

- Lower outer corners now prioritize page/cover capture over body movement.
  The input regression check passes with a workspace log path, including
  corner acquisition, pointer release, and tracking-loss cancellation.
- Midpoint cancellation, two-hand scaling, and palm reveal thresholds are
  implementation choices to validate on the headset. The sampled promotional
  video demonstrates turns and hand contact but does not establish these exact
  rules or prove a particular toolbar attachment strategy.

- Reference study complete; implementation is in the working tree. ADB access
  is restored and the Quest is connected. Headset interaction refinement remains
  pending; connection alone does not verify the experience.
- Spotless apply/check and the arm64 Android build pass using the existing
  cached native libraries. The final APK passed packaging with its embedded
  reader pack hash verified and arm64 OpenXR loader present. It was installed
  successfully on the Quest with app data preserved, then launched.
- Eleven desktop checks pass: book, input, controls, tracking, native panel,
  workspace, remote grabs, scrolling, palm menu, fallback hands and locomotion.
- Native Android composition now uses negative sort order and hole punching
  to allow hands/books in front of the library. Visual verification, native hand
  appearance, passthrough holdout and final library frost styling remain pending.
- Existing black-screen/Android panel work remains in the feature branch and
  must be preserved while changing the workspace.

## Technical references

### Latest book/model correction

- The embedded reader now includes the vendor GDExtension descriptor and desktop
  test libraries from the existing OpenXR Vendors 5.1.0 dependency. Previously
  Java loaded the Android library but the reader pack had no extension list,
  leaving native model classes unavailable and activating capsule placeholders.
- Controllers use OpenXRFbRenderModel with the required Quest manifest feature;
  hands use OpenXRFbHandTrackingMesh and XRHandModifier3D. Capsule visuals are removed.
- Resumed chapters also request page zero for cover artwork and open at the
  saved spread. Closed curved page blocks flatten beneath the cover image.
- Beveled rounded covers, curved paper blocks with page-edge lines and 64×24
  leaves replace box-like book geometry. Real cached Quest content renders in
  desktop open/turn/closed previews. Exact Livro appearance still needs Quest comparison.
- Spotless apply/check, the full arm64 build and all eleven interaction checks
  pass. The final asset refresh passed packaging; the APK contains the exported
  extension list, vendor descriptor and arm64 libraries. Installed successfully
  as VR-book-models-fixed.apk with app data preserved. Quest rendering validation
  remains pending; model registration on desktop is not a headset visual check.

- Livro official developer announcement: https://www.reddit.com/r/oculus/comments/15tsnll/
- Meta hand mesh setup: https://godotvr.github.io/godot_openxr_vendors/manual/meta/hand_tracking.html
- Meta passthrough: https://godotvr.github.io/godot_openxr_vendors/manual/meta/passthrough.html
- Hand representation: https://developers.meta.com/vr/design/hand-representation/
- Native panel depth/hole punching: https://docs.godotengine.org/en/4.6/classes/class_openxrcompositionlayer.html
- Joint validity and fallback hand topology: https://docs.godotengine.org/en/4.6/classes/class_xrhandtracker.html

