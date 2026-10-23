# 003 - Replace `transition-all` on layout properties with GPU-only transitions

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: MEDIUM
- **Category**: Performance
- **Estimated scope**: 2 files (`frontend_sj/frontend/src/components/layout/Sidebar.jsx`, `frontend_sj/frontend/src/pages/Dashboard/index.jsx`)

## Problem

**Sidebar collapse** - `src/components/layout/Sidebar.jsx:211-219`:

```jsx
// current
<aside
  className={`
    fixed lg:relative inset-y-0 left-0 z-40 lg:z-auto
    w-60 ${isCollapsed ? 'lg:w-[60px]' : 'lg:w-60'}
    ${isMobileOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'}
    h-full bg-white dark:bg-zinc-950 border-r border-slate-200 dark:border-zinc-800
    flex flex-col flex-shrink-0 overflow-x-hidden
    transition-transform lg:transition-all duration-300 ease-in-out
  `}
>
```

On desktop (`lg:`), `transition-all` is watching every animatable property for changes, but the property that's actually changing here is `width` (`w-60` ↔ `lg:w-[60px]`), which triggers layout + paint + composite on every frame of the 300ms transition, not just a GPU composite.

**Dashboard distribution bars** - `src/pages/Dashboard/index.jsx:263` (and identically at lines 411, 449, 536, 641 for other distribution cards):

```jsx
// current
<div
  key={cond}
  className={`h-full ${CONDITION_CFG[cond].bar} transition-all duration-700`}
  style={{ width: `${(count / total) * 100}%` }}
  title={`${CONDITION_CFG[cond].label}: ${count}`}
/>
```

Same issue: `transition-all` on an element whose `style.width` is what's actually animating, plus 700ms/500ms durations, both well past the "UI animations stay under 300ms" budget in AUDIT.md #2 (this one is a data-reveal bar, not marketing/explanatory content, so the budget applies).

## Target

**Sidebar** - since the container must actually resize (not just visually translate - content reflows around it), keep `width` as the animated property but scope the transition to only it (stop watching every property), and separately transition `transform` for the mobile slide-in:

```jsx
// target
<aside
  className={`
    fixed lg:relative inset-y-0 left-0 z-40 lg:z-auto
    w-60 ${isCollapsed ? 'lg:w-[60px]' : 'lg:w-60'}
    ${isMobileOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'}
    h-full bg-white dark:bg-zinc-950 border-r border-slate-200 dark:border-zinc-800
    flex flex-col flex-shrink-0 overflow-x-hidden
    transition-[transform,width] duration-300 ease-in-out
  `}
>
```

(This does not make the width change GPU-only: `width` can never be, but it stops the browser from also watching `background-color`, `border-color`, `box-shadow`, etc. on every hover/theme-change while the sidebar exists, which is the concrete, actionable part of this finding. A true GPU-only collapse would require restructuring the sidebar to animate `transform: scaleX()`/clip instead of `width`, which is a larger change, out of scope for this plan; note it as a follow-up if the executor wants to flag it, but do not attempt it here.)

**Dashboard bars** - animate only `transform` via `scaleX` instead of `width`, which IS fully GPU-accelerable, and cut duration to within budget:

```jsx
// target
<div
  key={cond}
  className={`h-full ${CONDITION_CFG[cond].bar} origin-left transition-transform duration-[250ms] ease-out`}
  style={{ transform: `scaleX(${count / total})` }}
  title={`${CONDITION_CFG[cond].label}: ${count}`}
/>
```

`origin-left` is required so the bar grows from the left edge (matching the old `width` growth direction) rather than from center (Tailwind's `transform` default origin).

## Repo conventions to follow

- This codebase already uses Tailwind's bracket arbitrary-value syntax elsewhere (e.g. `duration-[220ms]` pattern introduced in plans 001/002). Use `duration-[250ms]` here for consistency, even though `duration-300`/`duration-200` are also valid literal Tailwind classes; either is fine, prefer whichever matches the exact target duration.
- The 5 distribution-bar instances (lines 263, 411, 449, 536, 641 in `Dashboard/index.jsx`) are structurally identical, apply the same `scaleX`/`origin-left` change to all 5, not just the first one you find.

## Steps

1. In `Sidebar.jsx:218`, change `transition-transform lg:transition-all duration-300 ease-in-out` to `transition-[transform,width] duration-300 ease-in-out`.

2. In `Dashboard/index.jsx`, find all 5 occurrences of the distribution-bar pattern (`transition-all duration-700` or `duration-500` on a `div` with `style={{ width: ... }}`). For each:
   - Change the className's `transition-all duration-700` (or `duration-500`) to `origin-left transition-transform duration-[250ms] ease-out`.
   - Change `style={{ width: `${...}%` }}` to `style={{ transform: `scaleX(${count / total})` }}`, note this changes from a percentage string to a raw 0-1 fraction; find the exact variable used at each of the 5 sites (they may differ slightly, e.g. `count / total` vs a pre-computed percentage variable) and adapt the expression to produce a 0-1 fraction, not a 0-100 percentage, for `scaleX`.
   - If any of the 5 sites computes width from something other than a simple `value / total` ratio (e.g. involves a minimum-visible-width clamp for very small slices), STOP and report that site instead of guessing. A clamped minimum width doesn't translate directly to a `scaleX` fraction and needs a different approach (e.g. a minimum `scaleX` floor).

## Boundaries

- Do NOT touch the sidebar's mobile overlay (`translate-x-0`/`-translate-x-full` logic) beyond the transition-property change in Step 1. The slide direction/logic itself is correct and out of scope.
- Do NOT attempt to convert the sidebar's width collapse into a transform-based approach in this plan. That's a larger structural change (would need the sidebar's children to also handle overflow differently). Flag it as a future idea in your final report, don't implement it.
- Do NOT change the distribution bars' colors, labels, or the surrounding `<div className="flex h-2.5 rounded-full overflow-hidden mb-4 gap-px ...">` container. Only the per-segment transition/style.

## Verification

- **Mechanical**: `cd frontend_sj/frontend && npm run build`, clean build, no new console warnings about `width` vs `transform`.
- **Feel check**:
  - Toggle the sidebar collapse button on desktop, confirm it still smoothly resizes over ~300ms with no visual regression (icons/labels still hide/show correctly).
  - Open the Dashboard page and confirm the Asset Condition distribution bar (and other distribution cards) fills to the correct proportional width, growing from the left edge, over ~250ms, not instantly, not from the center.
  - In Chrome DevTools Performance panel, record a sidebar toggle and a dashboard load; confirm the "Rendering" flame chart shows fewer/shorter purple (layout) blocks for the distribution bars specifically compared to before the fix (the sidebar will still show layout cost. That's expected and acknowledged as out of scope above).
- **Done when**: the Dashboard's distribution bars animate via `transform: scaleX()` at ≤250ms, and the Sidebar's transition property list no longer includes unrelated properties like `background-color`/`box-shadow` alongside `width`.
