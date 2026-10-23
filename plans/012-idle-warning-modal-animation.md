# 012 - Give the idle-session warning the same entrance as every other modal

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: LOW
- **Category**: Cohesion
- **Estimated scope**: 1 file (`frontend_sj/frontend/src/components/common/IdleWarningModal.jsx`)

## Problem

```jsx
// frontend_sj/frontend/src/components/common/IdleWarningModal.jsx:18 - current
return (
  <div className="fixed inset-0 z-50 flex items-center justify-center bg-zinc-950/80">
    <div className="bg-white dark:bg-zinc-900 border border-slate-200 dark:border-zinc-700 rounded-xl shadow-2xl w-full max-w-sm mx-4 p-6">
```

No `animate-*` class anywhere in this file. It's the one modal-like component in the app with zero entrance animation, snapping in instantly. Every other modal in the codebase (built on `Modal.jsx`, see plan 002) enters with `animate-fade-slide`. This is arguably the moment MOST deserving a smooth, non-alarming appearance (a session-timeout warning popping in harshly could read as more alarming than intended), yet it's the one place motion is entirely absent. An inconsistency with the app's own established modal convention.

## Target

```jsx
// target
return (
  <div className="fixed inset-0 z-50 flex items-center justify-center bg-zinc-950/80 animate-fade-in">
    <div className="bg-white dark:bg-zinc-900 border border-slate-200 dark:border-zinc-700 rounded-xl shadow-2xl w-full max-w-sm mx-4 p-6 animate-fade-slide">
```

`animate-fade-in` on the backdrop and `animate-fade-slide` on the panel matches exactly how `Modal.jsx` currently animates its own backdrop/panel pair (see plan 002's Problem section for `Modal.jsx`'s pre-fix structure. This component doesn't use `Modal.jsx` itself, it's a hand-rolled full-screen overlay, but should visually match its entrance).

## Repo conventions to follow

- `animate-fade-in` (`fadeIn 0.2s cubic-bezier(0.25, 1, 0.5, 1) both`) and `animate-fade-slide` (`fadeSlide 0.28s cubic-bezier(0.16, 1, 0.3, 1)`) already exist in `tailwind.config.js`, reuse them exactly, do not define new keyframes.
- This component doesn't currently import/use `Modal.jsx`. This plan does NOT migrate it onto the shared `Modal` component (that would change its close/backdrop-click behavior and is a bigger structural change); it only adds the two existing utility classes to match the visual entrance.

## Steps

1. In `frontend_sj/frontend/src/components/common/IdleWarningModal.jsx`, add `animate-fade-in` to the outer backdrop `div`'s className (line 18).
2. Add `animate-fade-slide` to the inner panel `div`'s className (line 19).

## Boundaries

- Do NOT migrate this component onto `Modal.jsx` or change its countdown/logout logic (lines 6-15), its buttons, or its backdrop-click behavior (it currently has none, clicking the backdrop does nothing, which is intentional for a session-timeout warning the user must explicitly act on; do not add a backdrop `onClick` in this plan).
- Do NOT add an exit animation in this plan. That's covered by plan 002's broader `Modal.jsx` fix if this component is ever migrated onto it; for now this plan only adds the entrance to match the rest of the app.

## Verification

- **Mechanical**: `cd frontend_sj/frontend && npm run build`, clean build.
- **Feel check**: trigger the idle warning (or temporarily lower `WARNING_SECONDS`/the idle-detection threshold locally to test faster) and confirm the backdrop fades in and the panel fades+slides in, matching the entrance feel of any other modal in the app (e.g. compare directly against opening "Add Asset").
- **Done when**: `IdleWarningModal` enters with `animate-fade-in`/`animate-fade-slide`, visually consistent with the rest of the app's modals.
