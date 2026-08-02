# Disambiguating "which side" from "what temperature" (oga-1i8)

Research + design proposal. **No production code lands from this bead** — the
deliverable is problem framing, evaluated interaction models with tradeoffs, a
recommendation, and a prototype / A-B plan. Implementation is a follow-up bead.

## Problem framing

`DeviceControlView` shows one zone (bed side) at a time and overloads a single
screen with two gesture axes:

| Axis | Gesture today | Action |
|------|---------------|--------|
| Vertical | swipe up/down, physical UP/DOWN (`onKey` / `onPreviousPage` / `onNextPage`) | raise / lower this side's temperature |
| Horizontal | swipe left/right, page keys | switch which side is focused |
| (point) | tap / SELECT / KEY_ENTER | toggle this side's power |

On small screens — round MIP faces, 240px-class devices — a horizontal
side-switch swipe is frequently misread as a vertical temperature swipe and
vice-versa. Diagonal intent + a narrow chord + imprecise/gloved/half-asleep
night touch make the two axes ambiguous, so the user changes the wrong thing:
they meant "switch to my partner's side" and instead cooled their own bed by a
degree, or meant "warm me up" and silently moved focus to the other side.

The failure is asymmetric and expensive:

- A mis-fired **temperature** change is silent and persistent — it stays wrong
  all night unless noticed.
- A mis-fired **side switch** is compounded by the next gesture: you then adjust
  temperature believing you're on your own side but you're on your partner's.

### A second, currently-worse problem: button-only devices can't switch sides at all

The side-switch axis is **swipe-only**. In `DeviceControlDelegate`:

- `onSwipe` LEFT/RIGHT → `selectNextZone()` / `selectPreviousZone()`
- `onKey` and `onPreviousPage`/`onNextPage` are **entirely** mapped to
  temperature; nothing routes a physical button to side switching.

Many manifest targets are button-primary with no touchscreen (fenix 7/8,
Forerunner 9xx, enduro3, most Edge units). On those devices there is **no input
at all** that changes the focused side — a two-zone bed is half-controllable.
So the redesign has to solve two things at once:

1. Reduce cross-axis mis-triggers on touch devices (the stated ask).
2. Give button-only devices *any* working side-select affordance (a latent bug
   this research surfaces).

Any model that removes the horizontal **swipe** axis helps (1); any model that
puts side-select on a button or a tappable target helps (2). The recommendation
is chosen to do both.

## Device landscape (from `manifest.xml`)

`minApiLevel="4.2.0"`, 75 products spanning three input classes. Don't hardcode
per-device — branch on `System.getDeviceSettings()` at runtime
(`isTouchScreen`, `screenShape`, `screenWidth`/`screenHeight`), exactly as the
view already does for `SCREEN_SHAPE_ROUND`.

| Class | Examples (targets) | Touch | Buttons | Notes |
|-------|--------------------|-------|---------|-------|
| Button-primary watch | fenix7/8, fr955/965/970, enduro3, epix2* | often **none** | 5-btn | today: **cannot switch sides** |
| Touch + button watch | venu2/3, vivoactive5/6, fr165/265, venux1 | yes | 2–5 btn | swipe ambiguity lives here |
| Touch Edge / handheld | edge540–1050, edgeexplore2, gpsmaph1, etrextouch | yes | few btn | tall rectangular; touch-primary |
| Small round MIP | fr165(s), instincte, venu2s/3s | yes/no | varies | **worst mis-trigger case** |

\* epix2 has a touchscreen but is used button-first by many owners; treat
"touch present" as *available*, not *primary*.

`isTouchScreen` is the single most important branch: it splits "swipe ambiguity
exists" from "no touch, must use buttons."

## Design principles

1. **One axis per screen, or one axis per input device.** The bug is two
   continuous axes sharing one surface. Remove the collision, don't just tune it.
2. **Keep the common action one gesture.** The overwhelmingly common action is
   "nudge *my* side's temp." That must stay a single up/down (button or swipe),
   no mode change first.
3. **Side is low-frequency + sticky.** You pick a side occasionally (often once)
   and then live on it. It doesn't deserve equal gesture real-estate with temp.
4. **Degrade gracefully across input classes** from one code path, driven by
   device settings — no per-product branches.
5. **Legible half-asleep in the dark.** Big current-side indicator, big temp,
   minimal chrome, no timing-sensitive gestures (double-tap, long-press races).

## Candidate models evaluated

Scored on: **mis-trigger rate** (primary goal), **discoverability**, **speed of
the common action**, **code cost**, **device coverage** (esp. button-only).
Scale: ✓✓ strong / ✓ ok / ~ weak / ✗ fails.

### A. Side as persistent selected state; all swipes = temperature (bead dir. #2)

A tap on a left/right indicator (touch) or a dedicated button (buttons) flips
the active side; **every** swipe/up-down then only moves temperature. The
horizontal *continuous* axis is deleted outright.

- Mis-trigger: ✓✓ — no horizontal swipe axis remains to collide with vertical.
- Discoverability: ✓ — persistent "◀ You / Partner ▶" pill with a highlighted
  active side; tap target is visible.
- Common-action speed: ✓✓ — up/down is always temp, zero mode juggling.
- Code cost: ✓ — small. Remove LEFT/RIGHT from `onSwipe`; make
  `selectNextZone` fire from a tap-zone on the indicator and from a button (e.g.
  KEY_START/LAP, currently "refresh") or a menu.
- Device coverage: ✓✓ — tap works on touch; button flip works on button-only,
  finally giving those devices a side control.

### B. Axis separation by page (bead dir. #1)

Side selection is its own page/view; temperature control is another. A CIQ
view/page stack; no single screen carries both axes.

- Mis-trigger: ✓✓ within a page.
- Discoverability: ✓ page dots already exist (`drawZonePageDots`).
- Common-action speed: ~ — if side-select is a separate page you must navigate
  back to temp to nudge; adds a step to the *frequent* action. Better if temp is
  the default page and side-select is a rarely-visited sibling.
- Code cost: ~ — new view + delegate + navigation wiring.
- Device coverage: ✓ — page navigation exists on both input classes, but "which
  gesture pages" reintroduces a horizontal axis on touch unless paging is
  button/tab-only.

### C. Dominant-axis gesture locking (bead dir. #5)

Keep both axes on one screen but, once a swipe's initial vector commits past a
deadzone to horizontal or vertical, lock that axis for the rest of the gesture so
a diagonal drag can't cross over.

- Mis-trigger: ✓ — reduces *mid-gesture* crossover, but **cannot** fix a swipe
  whose *initial* vector is already ambiguous (the common short, fast night
  flick). It tunes the boundary, doesn't remove it.
- Discoverability: ✓✓ — invisible; gestures look unchanged.
- Common-action speed: ✓✓ — unchanged.
- Code cost: ~ — CIQ `onSwipe` only reports a discrete direction, not the raw
  track; true dominant-axis locking needs `onDrag`/touch-tracking
  (`InputDelegate` drag events) and hand-rolled thresholding. Non-trivial, and
  touch-only (does nothing for button devices).
- Device coverage: ~ — touch-only; leaves button-only side-switch still broken.

### D. Tap zones for side, up/down for temp (bead dir. #3)

Tap the left half / right half of the screen to select side; temperature stays
on up/down (buttons or swipe).

- Mis-trigger: ✓ — removes horizontal swipe. But **tap already means "toggle
  power"** today; overloading tap with left/right zones collides with power and
  with the vertical swipe start point.
- Discoverability: ~ — invisible tap halves; needs on-screen hinting.
- Common-action speed: ✓✓ for temp.
- Code cost: ~ — must re-home the power toggle (it currently owns tap/SELECT).
- Device coverage: ~ — tap-halves are touch-only; button devices still stuck.

### E. Hardware-button mapping (bead dir. #4)

Physical buttons drive one axis explicitly: UP/DOWN = temp (already true),
a dedicated key or long-press = switch side; drop swipe ambiguity on button
watches by not relying on swipe there.

- Mis-trigger: ✓✓ on button devices (no swipe used).
- Discoverability: ~ — button-to-function mapping is invisible; needs an
  on-screen hint (there's already a hint line).
- Common-action speed: ✓✓.
- Code cost: ✓ — map one more key to `selectNextZone`. **Note:** with only two
  sides, a single "toggle side" key is enough (no prev/next needed).
- Device coverage: ✓ button-only; but alone it says nothing about touch devices.

### F. Adaptive per-device UI (bead dir. #6)

Detect input from the device profile and present the best model per class.

- This isn't a rival model; it's the **delivery mechanism**. Every good option
  above already wants a `isTouchScreen` branch. Adopt F as the umbrella and pick
  the concrete model per class underneath it.

### G. (new) Two-sides-at-once split view — no "focused side" concept

For two-zone beds, show **both** sides simultaneously (left half = you, right
half = partner), each with its own temp readout, and adjust the side your input
targets. Removes "switch side" as a *mode* entirely: there's nothing to switch
because both are always visible.

- Mis-trigger: ✓✓ — no side-select axis exists.
- Discoverability: ✓✓ — both sides visibly on screen; matches the physical bed
  mental model.
- Common-action speed: ✓✓ on touch (tap the side's +/−); ~ on button-only (a
  button must still pick which half UP/DOWN targets — reduces to model A/E under
  the hood for buttons).
- Code cost: ~ — real layout work on small round screens (two temp columns in a
  narrow chord is tight; fine on tall Edge/rectangular).
- Device coverage: ✓ touch; needs an A/E-style button target for button-only.

## Recommendation

**Adopt F (adaptive) as the frame, with A (persistent selected side; all swipes
= temperature) as the concrete model on every class, and E's button mapping as
A's button-side implementation.** In one sentence: **delete the horizontal swipe
axis everywhere; make "switch side" a discrete tap-target (touch) or a single
dedicated button (buttons); keep up/down = temperature universally.**

Why this over the others:

- It is the only option that fixes **both** problems from a single change — the
  mis-trigger ask *and* the button-only "can't switch sides" gap — at small code
  cost.
- It preserves the common action (up/down = temp) with zero mode juggling
  (principle 2) and respects side as low-frequency + sticky (principle 3).
- It's one code path with an `isTouchScreen` branch (principle 4), no
  per-product forks.
- G (split view) is the more elegant end-state and worth a later spike, but its
  small-round-screen layout cost is real; ship A first, revisit G if telemetry
  says users still fumble side identity.
- C (axis locking) is explicitly **not** recommended as the primary fix: it only
  narrows the ambiguous band, needs drag-tracking CIQ plumbing, and does nothing
  for button devices. It's an optional refinement layered on A later if any
  residual swipe axis remains.

### Concrete interaction spec (model A + E)

Single `DeviceControlView` screen, per input class:

- **Common (all devices):** big active-side label ("Your side" / partner label
  from `zoneLabel`), big temp, power state. UP/DOWN (button or swipe) = temp.
  SELECT/ENTER/tap-on-power = toggle power. This is unchanged from today except
  the swipe LEFT/RIGHT handlers are removed.
- **Touch devices (`isTouchScreen == true`):** a persistent side pill near the
  top — `◀ A · B ▶` with the active side highlighted. Tapping the pill (or its
  left/right target) flips the active side. No horizontal swipe anywhere.
- **Button devices (`isTouchScreen == false`):** map one currently-underused key
  to "toggle side." KEY_START/KEY_LAP is presently "refresh"; with only two
  sides, reassign a **long-press** or the menu (`onMenu`) to side-toggle, or move
  refresh and free a key — decide at implementation time. Update the hint line
  ("UP/DOWN temp · SELECT power · MENU side").
- **Single-zone beds:** side control is hidden entirely (as `selectNextZone`
  already no-ops when `_zones.size() <= 1`); no pill, no side button, no wasted
  affordance.

Estimated change surface: `DeviceControlDelegate.onSwipe` (drop LEFT/RIGHT),
one new tap-region / key binding for side-toggle, `onUpdate` gains the side pill
for touch + a revised hint line. No model/API/network changes — it's purely the
input + a draw addition, isolated to `DeviceControlView.mc`.

## Prototype / A-B plan

**Prototype (single follow-up bead):** implement model A+E behind the existing
`isTouchScreen`/`screenShape` branches in `DeviceControlView.mc`. Verify in the
CIQ simulator across the three input classes using devices already in the CI
build matrix:

- Touch round small: `fr165` / `venu3s` — confirm pill tap flips side, no swipe
  crossover.
- Button-only: `fenix7` / `fr965` — confirm side-toggle key works (the case
  that's **completely broken** today) and no gesture is required.
- Touch rectangular: `edge840` — confirm layout on tall screens.

**A-B measurement (needs lightweight telemetry — separate bead if adopted):**
the honest signal for "did we stop changing the wrong thing" is behavioral.
Instrument two counters and compare old vs new build:

- **Correction rate:** a temp change immediately followed (< N s) by an equal-
  and-opposite temp change on the *other* side = a probable mis-target. Expect
  this to drop.
- **Side-switch → immediate-undo rate:** a side switch followed within < N s by
  a switch back = an accidental side change. Removing the swipe axis should drive
  this toward zero on touch, and > 0 (from real use) on button devices that
  previously *couldn't* switch at all.

If CIQ telemetry/analytics isn't wired up, fall back to a qualitative A-B: build
both variants, dogfood a week each on one touch and one button device, log
subjective mis-triggers. Ship A if mis-triggers drop and no new confusion about
"which side am I on" appears; if side-identity confusion shows up, layer G's
always-both-visible readout on top.

## Summary

| Model | Mis-trigger | Discover | Speed | Code | Coverage | Verdict |
|-------|:-:|:-:|:-:|:-:|:-:|--------|
| A persistent side + all-swipe-temp | ✓✓ | ✓ | ✓✓ | ✓ | ✓✓ | **recommend (core)** |
| E button side-toggle | ✓✓ | ~ | ✓✓ | ✓ | ✓ | **recommend (button impl of A)** |
| F adaptive per-device | — | — | — | — | — | **recommend (frame)** |
| B page separation | ✓✓ | ✓ | ~ | ~ | ✓ | viable, slower common action |
| G split both-sides view | ✓✓ | ✓✓ | ✓ | ~ | ✓ | strong later spike |
| D tap-zones for side | ✓ | ~ | ✓✓ | ~ | ~ | collides with power/tap |
| C axis locking | ✓ | ✓✓ | ✓✓ | ~ | ~ | optional refinement only |

**Recommended path:** ship **A+E under F** (delete horizontal swipe axis; side =
tap-target on touch / one button on button-only; up/down = temp everywhere),
then evaluate **G** as a follow-up if side-identity confusion persists.
