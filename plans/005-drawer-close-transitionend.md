# 005 - Replace hand-timed `setTimeout` drawer/banner closes with `transitionend`-driven state

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: MEDIUM
- **Category**: Interruptibility
- **Estimated scope**: 2 files (`frontend_sj/frontend/src/pages/Inventory/index.jsx`, `frontend_sj/frontend/src/pages/Tracking/index.jsx`)

## Problem

Both pages close their detail drawer (and, in Inventory's case, an undo banner) by flipping an `exiting` boolean and firing a `setTimeout` hand-matched to the keyframe animation's duration:

```jsx
// src/pages/Inventory/index.jsx:130-133 - current
const closeDetail = useCallback(() => {
  setDetailExiting(true)
  setTimeout(() => { setDetailRecord(null); setDetailExiting(false) }, 220)
}, [])
```

```jsx
// src/pages/Inventory/index.jsx:239-246 - current
const exitUndoBanner = (afterExit) => {
  setUndoBannerExiting(true)
  setTimeout(() => {
    setUndoDelete(null)
    setUndoBannerExiting(false)
    afterExit?.()
  }, 180)
}
```

```jsx
// src/pages/Tracking/index.jsx:86-89 - current
const closeLogDrawer = useCallback(() => {
  setLogDrawerExiting(true)
  setTimeout(() => { setDetailLog(null); setLogDrawerExiting(false) }, 220)
}, [])
```

This is a real interruptibility risk: if the same close function is called again inside its own timer window (e.g. the drawer is reopened for a different record before the 220ms timer fires from the previous close), the stale `setTimeout` still fires and can null out the *new* record/turn off the *new* exiting state out from under it, or fire `afterExit` for the wrong invocation. It's also brittle, if the keyframe duration in `tailwind.config.js` (`slideOutDrawer`, `toastOut`-equivalent for the undo banner) is ever changed, these hardcoded numbers silently drift out of sync.

## Target

Drive the "actually remove from state" step off the CSS transition/animation's own `onAnimationEnd`/`onTransitionEnd` event instead of a timer, so it's tied to the real animation, and guard against a stale event firing for a since-replaced instance using a ref-based generation counter.

```jsx
// src/pages/Inventory/index.jsx - target
const detailCloseGen = useRef(0)

const closeDetail = useCallback(() => {
  detailCloseGen.current += 1
  setDetailExiting(true)
}, [])

const handleDetailAnimationEnd = useCallback(() => {
  setDetailRecord(null)
  setDetailExiting(false)
}, [])
```

Then in the JSX where `RecordDrawer` is rendered, pass `onExitAnimationEnd={handleDetailAnimationEnd}` and have `RecordDrawer.jsx` attach it to the panel's `onAnimationEnd` (the panel uses `animate-slide-out-drawer`, a real CSS `@keyframes` animation, so the native `animationend` event fires exactly when it completes. No drift possible).

Apply the identical pattern to `exitUndoBanner` and `closeLogDrawer`.

## Repo conventions to follow

- `RecordDrawer.jsx` and `LogDrawer.jsx` are function components that receive `exiting` as a prop (see plan 004, which adds this same prop to `AssetDrawer.jsx`), adding one more prop (`onExitAnimationEnd`) to each follows the same shape.
- React's `onAnimationEnd`/`onTransitionEnd` synthetic events bubble from the actual animated element, attach the handler to the specific `div`/`aside` that carries the `animate-slide-out-drawer` (or equivalent) class, not a wrapping element, or it may not fire (CSS animation events only fire on the element the animation is declared on, not ancestors, unless the event bubbles: `animationend` does bubble in React's synthetic event system, but attaching directly to the animated element is the reliable choice and matches how the class itself is applied).

## Steps

1. In `src/pages/Inventory/index.jsx`:
   - Replace `closeDetail`'s body with the two-function split shown in Target (`closeDetail` just sets `detailExiting = true`; a new `handleDetailAnimationEnd` does the actual `setDetailRecord(null); setDetailExiting(false)`).
   - Find where `RecordDrawer` is rendered (search for `<RecordDrawer`) and add `onExitAnimationEnd={handleDetailAnimationEnd}`.
   - Do the same restructuring for `exitUndoBanner`: split into `exitUndoBanner(afterExit)` (sets `undoBannerExiting = true`, stashes `afterExit` in a ref since it's a per-call argument, e.g. `afterExitRef.current = afterExit`) and a `handleUndoBannerAnimationEnd` that reads `afterExitRef.current`, calls it, then resets state. Find the undo banner's JSX (search for `undoBannerExiting`) and attach the new handler to whichever element carries its exit animation class.

2. In `src/pages/Tracking/index.jsx`, apply the identical split to `closeLogDrawer` → `closeLogDrawer` (sets `logDrawerExiting = true`) + `handleLogDrawerAnimationEnd` (does the actual `setDetailLog(null); setLogDrawerExiting(false)`). Wire `onExitAnimationEnd={handleLogDrawerAnimationEnd}` onto `<LogDrawer>`.

3. In `RecordDrawer.jsx` and `LogDrawer.jsx`, add the new `onExitAnimationEnd` prop and attach it as `onAnimationEnd={exiting ? onExitAnimationEnd : undefined}` on the panel element (the one with the `animate-slide-out-drawer`/`animate-slide-in-drawer` conditional class), guarding with `exiting ?` so the handler only fires during the close animation, not the open one (both use the same CSS `animationend` event, and firing the "close" cleanup logic after the *open* animation finishes would be wrong).

4. If the undo banner's exit uses a `transition` (not a `@keyframes` animation). Check its actual className in `Inventory/index.jsx` before assuming `onAnimationEnd` is correct; if it's transition-based, use `onTransitionEnd` instead. Report which one it actually is in your final summary.

## Boundaries

- Do NOT change the animation durations or curves themselves (`slideOutDrawer`'s 220ms, the undo banner's 180ms). This plan only changes *how* the resulting state cleanup is triggered, not the timing.
- Do NOT touch `AssetDrawer.jsx` in this plan, plan 004 handles giving it animation in the first place, using the simpler `setTimeout` pattern this plan is replacing elsewhere; do not retrofit plan 004's drawer with this plan's `transitionend` approach unless explicitly asked in a follow-up (avoids a merge conflict between the two plans if both are executed).
- Do NOT remove the generation-counter safety net idea if you find a genuine risk of stale closures, if `afterExitRef` or similar ref-based state isn't sufficient to prevent a stale callback from firing for a since-replaced record, stop and describe the race condition you found rather than shipping a subtly broken fix.

## Verification

- **Mechanical**: `cd frontend_sj/frontend && npm run build`, clean build.
- **Feel check**:
  - Open an Inventory record's detail drawer, close it normally, confirm it still slides out and disappears at the same visual timing as before.
  - Open a record, close it, and **immediately** open a different record before the first close's animation would have finished (i.e. click a new row within ~150ms of clicking close on the old one), confirm the new drawer's content is correct and doesn't get nulled out by a stale timer from the previous close.
  - Delete an Inventory record, confirm the undo banner appears; click "Undo" and confirm the banner exits cleanly; separately, let the undo banner's own countdown expire naturally and confirm it also exits cleanly via the same code path.
  - Repeat both checks on the Tracking page's log drawer.
- **Done when**: no `setTimeout` remains driving the actual state cleanup for these three interactions (only `setExiting(true)` remains synchronous; the cleanup is triggered by the real animation event), and rapidly reopening a drawer mid-close no longer risks a stale timer clobbering the new instance's state.
