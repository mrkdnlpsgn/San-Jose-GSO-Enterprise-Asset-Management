# 011 - Consolidate the two near-identical cubic-bezier curves into named tokens

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: LOW
- **Category**: Cohesion & tokens
- **Estimated scope**: 1 file (`frontend_sj/frontend/tailwind.config.js`)

## Problem

```js
// frontend_sj/frontend/tailwind.config.js:33-42 - current
animation: {
  'fade-slide':     'fadeSlide 0.28s cubic-bezier(0.16, 1, 0.3, 1)',
  'fade-in':        'fadeIn 0.2s cubic-bezier(0.25, 1, 0.5, 1) both',
  'slide-in-right': 'slideInRight 0.32s cubic-bezier(0.16, 1, 0.3, 1)',
  'toast-out':      'toastOut 0.2s cubic-bezier(0.25, 1, 0.5, 1) forwards',
  'slide-down':     'slideDown 0.26s cubic-bezier(0.16, 1, 0.3, 1)',
  'slide-up':       'slideUp 0.18s cubic-bezier(0.25, 1, 0.5, 1) forwards',
  'scale-in':          'scaleIn 0.22s cubic-bezier(0.16, 1, 0.3, 1)',
  'slide-in-drawer':   'slideInDrawer 0.32s cubic-bezier(0.16, 1, 0.3, 1) both',
  'slide-out-drawer':  'slideOutDrawer 0.22s cubic-bezier(0.25, 1, 0.5, 1) both',
  'fade-out':          'fadeOut 0.2s cubic-bezier(0.25, 1, 0.5, 1) both',
},
```

Two hand-typed cubic-beziers are repeated 10 times with no shared name: `cubic-bezier(0.16, 1, 0.3, 1)` (used for `fade-slide`, `slide-in-right`, `slide-down`, `scale-in`, `slide-in-drawer`. All **entrances**) and `cubic-bezier(0.25, 1, 0.5, 1)` (used for `fade-in`, `toast-out`, `slide-up`, `slide-out-drawer`, `fade-out`. A mix of entrances and **exits**). AUDIT.md #7 flags exactly this pattern: "Curves and durations should live as shared tokens. Five hand-typed cubic-beziers that almost match is a consolidation finding."

## Target

Tailwind's config doesn't support named CSS-variable-style easing tokens directly inside the `animation` extend object the way plain CSS custom properties would. The cleanest fix within this config format is to hoist the two literal curve strings into named JS constants at the top of the config file and reference them by variable, so there is exactly one place to change either curve, and the naming makes the entrance/exit intent explicit:

```js
// frontend_sj/frontend/tailwind.config.js - target (top of file, before module.exports/export default)
const EASE_ENTER = 'cubic-bezier(0.16, 1, 0.3, 1)' // strong ease-out - used for every entrance animation
const EASE_EXIT  = 'cubic-bezier(0.25, 1, 0.5, 1)' // slightly softer ease-out - used for exits and a couple of fades

// ... inside theme.extend.animation:
animation: {
  'fade-slide':        `fadeSlide 0.28s ${EASE_ENTER}`,
  'fade-in':           `fadeIn 0.2s ${EASE_EXIT} both`,
  'slide-in-right':    `slideInRight 0.32s ${EASE_ENTER}`,
  'toast-out':         `toastOut 0.2s ${EASE_EXIT} forwards`,
  'slide-down':        `slideDown 0.26s ${EASE_ENTER}`,
  'slide-up':          `slideUp 0.18s ${EASE_EXIT} forwards`,
  'scale-in':          `scaleIn 0.22s ${EASE_ENTER}`,
  'slide-in-drawer':   `slideInDrawer 0.32s ${EASE_ENTER} both`,
  'slide-out-drawer':  `slideOutDrawer 0.22s ${EASE_EXIT} both`,
  'fade-out':          `fadeOut 0.2s ${EASE_EXIT} both`,
},
```

This is a naming/maintainability fix only. Every generated `@keyframes`/duration/easing value stays byte-for-byte identical to today (confirm this by comparing the built CSS before/after, see Verification), it just eliminates the 10 hand-typed repetitions of two literal strings down to 2.

## Repo conventions to follow

- `tailwind.config.js` currently uses `export default { ... }` (ES module syntax, confirmed by the file's existing structure). The two `const` declarations must go above that `export default` statement, as plain top-level module constants, not inside the exported object.
- Do not rename any of the 10 existing `animation` keys (`fade-slide`, `fade-in`, etc.). Those are referenced via `animate-*` Tailwind utility classes throughout the JSX codebase (e.g. `animate-fade-slide` in `Modal.jsx`) and renaming them would require touching every call site, which is out of scope for a token-consolidation plan.

## Steps

1. Open `frontend_sj/frontend/tailwind.config.js`. Add the two `const EASE_ENTER = ...` / `const EASE_EXIT = ...` declarations (shown in Target) directly above the `export default` (or `module.exports =`, whichever this file uses. Check first) statement.
2. Replace each of the 10 animation value strings in `theme.extend.animation` with the template-literal form shown in Target, using `EASE_ENTER` for `fade-slide`/`slide-in-right`/`slide-down`/`scale-in`/`slide-in-drawer`, and `EASE_EXIT` for `fade-in`/`toast-out`/`slide-up`/`slide-out-drawer`/`fade-out`, matching exactly which curve each currently uses (do not swap any; the mapping above must produce identical output to today).
3. After editing, run a build and diff the generated CSS's animation-related rules against a build from before your change (e.g. `git stash`, build, save output; `git stash pop`, build, diff) to confirm byte-for-byte identical `cubic-bezier(...)` values in the output. This is your safety check that the refactor introduced zero visual change.

## Boundaries

- Do NOT rename any `animation` key or touch any `@keyframes` definition in the same file (the `theme.extend.keyframes` object). Only the two hoisted constants and the 10 value strings that reference them.
- Do NOT touch any `.jsx` file. No `animate-*` class names change.
- If you find the two curves are NOT byte-for-byte the same after your edit (e.g. a typo introduces a third distinct curve), STOP and fix it before finishing. This plan must be a zero-visual-diff refactor.

## Verification

- **Mechanical**: `cd frontend_sj/frontend && npm run build`, clean build; diff generated CSS animation rules against a pre-change build (see Step 3) and confirm no differences.
- **Feel check**: not applicable in the traditional sense (this plan produces zero visual change by design), instead, spot check 2-3 animated elements (a modal opening, a toast appearing, an Inventory drawer opening) and confirm they look and time identically to before the change.
- **Done when**: `tailwind.config.js` has exactly 2 literal `cubic-bezier(...)` strings (in the two new named constants) instead of 10, and the built CSS is unchanged.
