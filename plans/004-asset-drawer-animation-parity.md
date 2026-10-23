# 004 - Give AssetDrawer the same open/close animation as its sibling drawers

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: MEDIUM
- **Category**: Cohesion
- **Estimated scope**: 1 file (`frontend_sj/frontend/src/pages/Assets/AssetDrawer.jsx`) + reading 1 reference file (`frontend_sj/frontend/src/pages/Inventory/RecordDrawer.jsx`) as the exemplar to copy from.

## Problem

Three components in this codebase implement the identical UX pattern. A right-side detail drawer opened by clicking a table row, closed via an × button or backdrop click:

```jsx
// src/pages/Assets/AssetDrawer.jsx:80-84 - current
return (
  <>
    <div className="fixed inset-0 z-30 bg-zinc-950/20 backdrop-blur-sm" style={{ top: '60px' }} onClick={onClose} />
    <aside className="fixed right-0 bottom-0 z-40 w-full max-w-lg bg-white dark:bg-zinc-950 border-l border-slate-200 dark:border-zinc-800 flex flex-col shadow-2xl overflow-hidden" style={{ top: '60px' }}>
```

No `animate-*` class anywhere on either element. The drawer teleports open and closed. Compare to its sibling, which has full motion:

```jsx
// src/pages/Inventory/RecordDrawer.jsx:35,46 - reference (DO NOT MODIFY, copy the pattern from here)
className={`fixed inset-0 z-30 bg-zinc-950/20 backdrop-blur-sm ${exiting ? 'animate-fade-out' : 'animate-fade-in'}`}
...
className={`... ${exiting ? 'animate-slide-out-drawer' : 'animate-slide-in-drawer'} ...`}
```

`Tracking/LogDrawer.jsx` follows the same pattern as `RecordDrawer.jsx`. `AssetDrawer.jsx` is the odd one out, users bounce between an animated drawer (Inventory/Tracking pages) and a teleporting one (Assets page) for the exact same interaction.

## Target

Read the full `exiting`-state pattern from `RecordDrawer.jsx` (its parent, `src/pages/Inventory/index.jsx`, owns a `detailExiting` state and a `closeDetail` callback. See plan 005, which addresses the `setTimeout`-based version of that same close mechanism separately; for THIS plan, just replicate the current, existing pattern exactly as `RecordDrawer.jsx` already does it. Do not fix the `setTimeout` issue here, that's plan 005's job and touching it here would create a merge conflict between the two plans).

Add an `exiting` prop to `AssetDrawer` and use it exactly the way `RecordDrawer.jsx` does:

```jsx
// src/pages/Assets/AssetDrawer.jsx - target (signature + render, abbreviated)
export default function AssetDrawer({ asset, onClose, onEdit, isAdmin, exiting }) {
  // ...unchanged hooks/state above...

  if (!asset) return null

  return (
    <>
      <div
        className={`fixed inset-0 z-30 bg-zinc-950/20 backdrop-blur-sm ${exiting ? 'animate-fade-out' : 'animate-fade-in'}`}
        style={{ top: '60px' }}
        onClick={onClose}
      />
      <aside
        className={`fixed right-0 bottom-0 z-40 w-full max-w-lg bg-white dark:bg-zinc-950 border-l border-slate-200 dark:border-zinc-800 flex flex-col shadow-2xl overflow-hidden ${exiting ? 'animate-slide-out-drawer' : 'animate-slide-in-drawer'}`}
        style={{ top: '60px' }}
      >
```

This requires the parent (`src/pages/Assets/index.jsx`) to own an `exiting` boolean and pass it down, plus delay the actual `setSelected(null)` until the exit animation finishes, mirroring exactly how `src/pages/Inventory/index.jsx` currently wires `RecordDrawer`.

## Repo conventions to follow

- `animate-fade-in`/`animate-fade-out`/`animate-slide-in-drawer`/`animate-slide-out-drawer` already exist in `tailwind.config.js`. Do not add new keyframes, reuse these exactly.
- Read `src/pages/Inventory/index.jsx`'s `closeDetail` callback (search for `detailExiting`) as the exemplar for how the parent should manage the exiting state and timing, replicate that exact shape (a boolean state + a timed `setTimeout` matched to the drawer's exit duration) in `src/pages/Assets/index.jsx`. Do not invent a different mechanism.

## Steps

1. In `src/pages/Assets/AssetDrawer.jsx`, add `exiting` to the destructured props and apply the two conditional classNames shown in Target to the backdrop `div` and the `aside` panel.

2. In `src/pages/Assets/index.jsx`, find the `selected`/`setSelected` state (used to control `AssetDrawer`'s visibility, per `onClose={() => setSelected(null)}`). Add a sibling `exiting` boolean state, and change the close handler to:
   ```jsx
   const [assetDrawerExiting, setAssetDrawerExiting] = useState(false)

   const closeAssetDrawer = useCallback(() => {
     setAssetDrawerExiting(true)
     setTimeout(() => { setSelected(null); setAssetDrawerExiting(false) }, 220)
   }, [])
   ```
   (220ms matches `slide-out-drawer`'s duration, `slideOutDrawer 0.22s` per `tailwind.config.js`, confirm this exact value by reading the keyframe definition before finalizing; if it differs from 220ms, use the actual value instead.)

3. Update the `AssetDrawer` render call to pass `exiting={assetDrawerExiting}` and use `closeAssetDrawer` (not the raw `setSelected(null)`) for its `onClose` prop, and for the `onEdit` handler if that also currently calls `setSelected(null)` directly (check the existing `onEdit={(a) => { setEditing(a); setSelected(null) }}` call, decide whether opening the edit modal should also play the drawer's exit animation first, or close instantly since a different modal is about to cover it; if uncertain, keep `onEdit`'s immediate `setSelected(null)` as-is and only route the backdrop-click/×-button close through the new animated path. Do not guess, prefer the more conservative option of leaving `onEdit`'s behavior unchanged).

4. Double check `useCallback` is imported in `src/pages/Assets/index.jsx` (it already imports several hooks per the file's existing `import { useState, useEffect, useCallback, useMemo } from 'react'` line), if not already imported, add it.

## Boundaries

- Do NOT modify `RecordDrawer.jsx`, `LogDrawer.jsx`, or `Inventory/index.jsx`/`Tracking/index.jsx`. Those are reference-only for this plan (plan 005 addresses their own `setTimeout` correctness separately).
- Do NOT change `AssetDrawer.jsx`'s tabs, fields, or any content beyond the two className additions and the new `exiting` prop.
- Do NOT change the drawer's width, position, or the `top: '60px'` inline style.

## Verification

- **Mechanical**: `cd frontend_sj/frontend && npm run build`, clean build.
- **Feel check**:
  - Click an asset row on the Assets page, confirm the drawer now slides in from the right with a backdrop fade, matching the feel of opening an Inventory record's drawer.
  - Close it via the × button and via clicking the backdrop, confirm both now animate out (slide right + fade) instead of disappearing instantly.
  - Compare side-by-side (open Assets drawer, then navigate to Inventory and open a record drawer). The two should now feel identical in timing and motion.
- **Done when**: `AssetDrawer` opens and closes with the same `animate-slide-in-drawer`/`animate-slide-out-drawer` + `animate-fade-in`/`animate-fade-out` motion as `RecordDrawer.jsx` and `LogDrawer.jsx`, with no visible teleport in either direction.
