# 001 - Make toast enter/exit interruptible (stop the dismiss-snap)

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: HIGH
- **Category**: Interruptibility
- **Estimated scope**: 1 file (`frontend_sj/frontend/src/context/ToastContext.jsx`)

## Problem

Toasts fire on nearly every CRUD action in the app (create/update/delete across Assets, Inventory, Maintenance, Disposal, Accounts, Categories, Offices). The enter and exit animations are two independent `@keyframes` (defined in `tailwind.config.js`), swapped via a ternary class:

```jsx
// src/context/ToastContext.jsx:41-51 - current
<div
  className={`
    flex items-start gap-3 px-4 py-3.5 rounded-xl border
    ${s.wrap}
    bg-zinc-900/90 backdrop-blur-md
    shadow-2xl shadow-black/60
    w-[340px] max-w-[calc(100vw-2rem)]
    ${toast.exiting ? 'animate-toast-out' : 'animate-slide-in-right'}
    pointer-events-auto
  `}
>
```

```jsx
// src/context/ToastContext.jsx:79-84 - current
const dismiss = useCallback((id) => {
  setToasts((prev) => prev.map((t) => t.id === id ? { ...t, exiting: true } : t))
  setTimeout(() => {
    setToasts((prev) => prev.filter((t) => t.id !== id))
  }, 210)
}, [])
```

`animate-slide-in-right` is `slideInRight 0.32s cubic-bezier(0.16, 1, 0.3, 1)` (0% `{opacity:0, translateX(28px)}` → 100% `{opacity:1, translateX(0)}`). `animate-toast-out` is `toastOut 0.2s cubic-bezier(0.25, 1, 0.5, 1)` (0% `{opacity:1, translateX(0)}` → 100% `{opacity:0, translateX(28px)}`).

If `dismiss()` fires while `animate-slide-in-right` is still mid-playback (e.g. the user clicks the toast's own dismiss button, `ToastItem.jsx:63-70`, within the first ~320ms), the class swap removes the running keyframe animation and starts `toastOut` fresh from its own declared 0% state (`opacity:1, translateX(0)`), **regardless of the element's actual current opacity/position**. The toast visibly snaps to fully-visible, then plays the exit. This is exactly the "keyframes restart from zero" failure AUDIT.md Category 4 describes, on the single most-frequently-seen animated element in the app.

## Target

Replace both keyframe animations with a two-state CSS **transition** (interruptible, retargets from whatever the current computed style is, no snap regardless of when it's triggered) driven by a `phase` field (`'entering' | 'idle' | 'exiting'`) instead of a plain `exiting` boolean:

```jsx
// src/context/ToastContext.jsx - target
function ToastItem({ toast, onDismiss }) {
  const s = STYLES[toast.type] ?? STYLES.info
  const visible = toast.phase !== 'entering' && toast.phase !== 'exiting'

  return (
    <div
      className={`
        flex items-start gap-3 px-4 py-3.5 rounded-xl border
        ${s.wrap}
        bg-zinc-900/90 backdrop-blur-md
        shadow-2xl shadow-black/60
        w-[340px] max-w-[calc(100vw-2rem)]
        transition-[opacity,transform] duration-200 ease-[cubic-bezier(0.25,1,0.5,1)]
        ${visible ? 'opacity-100 translate-x-0' : 'opacity-0 translate-x-7'}
        pointer-events-auto
      `}
    >
```

`translate-x-7` is Tailwind's `1.75rem` (28px), matches the original keyframes' `translateX(28px)` exactly. `duration-200`/`cubic-bezier(0.25,1,0.5,1)` matches the existing `toastOut` timing exactly, so exit feels identical; entry now uses the same curve/duration (a deliberate, minor simplification. Call this out in the PR description, don't silently change `slideInRight`'s 320ms without saying so).

## Repo conventions to follow

- This app has no separate `--ease-*`/`--duration-*` CSS custom properties; timing values are hand-typed per Tailwind utility/keyframe. Follow that convention. Use Tailwind's arbitrary-value syntax (`ease-[cubic-bezier(...)]`, `duration-200`) rather than introducing a new token system in this plan (token consolidation is plan 011, a separate concern).
- `toast.exiting` boolean is replaced by `toast.phase`, update every reference in this file (there are exactly two: the `show`/`dismiss` callbacks and the `ToastItem` render).

## Steps

1. In `src/context/ToastContext.jsx`, change the `show` callback (currently around line 86-92) so a new toast is pushed with `phase: 'entering'`, then flips to `phase: 'idle'` one frame later so the transition actually plays (a toast that starts and ends in the same frame never transitions):
   ```jsx
   const show = useCallback((message, type = 'success', options = {}) => {
     const id       = crypto.randomUUID()
     const duration = options.duration ?? (type === 'error' ? 5000 : type === 'warning' ? 4000 : 3500)

     setToasts((prev) => [...prev, { id, message, type, title: options.title, phase: 'entering' }])
     requestAnimationFrame(() => requestAnimationFrame(() => {
       setToasts((prev) => prev.map((t) => t.id === id ? { ...t, phase: 'idle' } : t))
     }))
     setTimeout(() => dismiss(id), duration)
   }, [dismiss])
   ```
   (Double `requestAnimationFrame` is the standard reliable way to force a style flush between the "off" state and the "on" state across browsers. A single rAF can occasionally batch with the initial render and skip the transition.)

2. Change `dismiss` to set `phase: 'exiting'` instead of `exiting: true`:
   ```jsx
   const dismiss = useCallback((id) => {
     setToasts((prev) => prev.map((t) => t.id === id ? { ...t, phase: 'exiting' } : t))
     setTimeout(() => {
       setToasts((prev) => prev.filter((t) => t.id !== id))
     }, 210)
   }, [])
   ```
   (210ms unchanged: 10ms buffer past the 200ms transition before unmount, same as today.)

3. In `ToastItem`, replace the `toast.exiting ? 'animate-toast-out' : 'animate-slide-in-right'` line with the `visible`-derived classes shown in Target above. Add the `const visible = toast.phase !== 'entering' && toast.phase !== 'exiting'` line at the top of the function body.

4. Leave `tailwind.config.js`'s `slideInRight`/`toastOut` keyframe definitions in place even though they become unused by this component. Do not delete them in this plan (out of scope; a separate cleanup pass should confirm nothing else references `animate-slide-in-right`/`animate-toast-out` before removing them).

## Boundaries

- Do NOT touch `tailwind.config.js` in this plan.
- Do NOT change the toast's stacking/positioning container (`ToastProvider`'s fixed `div`, lines 100-105) or the icon/message markup.
- Do NOT add a new animation/motion library. This stays plain Tailwind + CSS transitions.
- If `toast.exiting` is referenced anywhere else in the codebase (grep for `\.exiting` and `animate-toast-out`/`animate-slide-in-right` before starting), STOP and report instead of guessing at other call sites. This plan assumes `ToastContext.jsx` is the only consumer.

## Verification

- **Mechanical**: `cd frontend_sj/frontend && npm run build`, expect a clean build with no new warnings.
- **Feel check**:
  - Trigger a toast (e.g. save an asset), let it fully appear, then click its own dismiss (×) button after ~2s. It should fade/slide out smoothly with no snap (baseline, should already work).
  - Trigger a toast and click its dismiss button **immediately**, within ~100-150ms of it appearing (before the entrance would have finished), confirm it smoothly reverses/exits from wherever it currently is, with no visible jump to fully-opaque before exiting. This is the actual regression this plan fixes; do this check in Chrome DevTools with the Animations panel set to 25% playback speed to see it clearly.
  - Trigger 3-4 toasts in quick succession (e.g. rapid save actions), confirm none of them snap or flicker as they stack and later exit on their timers.
  - Toggle `prefers-reduced-motion` (DevTools Rendering panel), confirm toasts still enter/exit (opacity change preserved) since global reduced-motion handling in `index.css` clamps transition-duration to near-zero (separately flagged in plan 008); no additional work needed here, just confirm it doesn't error.
- **Done when**: dismissing a toast at any point during its entrance never shows a visible snap to full opacity/zero-offset before exiting, and normal (non-interrupted) toast entry/exit still looks and times the same as before.
