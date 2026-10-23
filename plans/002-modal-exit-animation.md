# 002 - Add a real exit animation to the shared Modal component

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: HIGH
- **Category**: Interruptibility / Physicality
- **Estimated scope**: 1 file (`frontend_sj/frontend/src/components/common/Modal.jsx`). No call-site changes required if Steps 1-3 are followed exactly (the delayed-unmount lives entirely inside `Modal.jsx`).

## Problem

`Modal.jsx` animates in with `animate-fade-slide` but has no exit path. Every consumer conditionally renders it (`{show && <Modal .../>}`), so React unmounts the DOM node the instant `onClose` fires. This affects effectively every dialog in the app: `AddAssetModal`, `UserModal`, `ImportModal`, `QRModal`, `AddRecordModal`, `AddMaintenanceModal`, `AddDisposalModal`, `ResetPasswordModal`, `ForgotPasswordModal`, `LogEntryModal`, and more. All built on this one shared component.

```jsx
// src/components/common/Modal.jsx:1-58 - current (full file)
import { useEffect } from 'react'
import { createPortal } from 'react-dom'

function Modal({ title, subtitle, children, onClose, size = 'lg' }) {
  const widths = { md: 'max-w-lg', lg: 'max-w-2xl', xl: 'max-w-4xl' }

  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose() }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [onClose])

  return createPortal(
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 animate-fade-slide"
      role="dialog"
      aria-modal="true"
      aria-label={title}
    >
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/30 dark:bg-zinc-950/80"
        onClick={onClose}
      />

      {/* Panel */}
      <div className={`
        relative bg-white dark:bg-zinc-900 border border-slate-200 dark:border-zinc-700
        rounded-xl shadow-2xl shadow-black/10 dark:shadow-black/60
        w-full ${widths[size]} flex flex-col max-h-[90vh]
      `}>
        {/* Header */}
        <div className="flex items-start justify-between px-6 py-4 border-b border-slate-200 dark:border-zinc-800">
          <div>
            <h2 className="text-sm font-semibold text-slate-900 dark:text-white">{title}</h2>
            {subtitle && (
              <p className="text-xs text-slate-400 dark:text-zinc-500 mt-0.5">{subtitle}</p>
            )}
          </div>
          <button
            onClick={onClose}
            className="ml-4 p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150 active:scale-95"
          >
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" />
            </svg>
          </button>
        </div>

        {/* Body */}
        <div className="px-6 py-4 overflow-y-auto">
          {children}
        </div>
      </div>
    </div>,
    document.body
  )
}

export default Modal
```

Note: `animate-fade-slide` is `fadeSlide 0.28s cubic-bezier(0.16, 1, 0.3, 1)`: `0% {opacity:0, translateY(10px)} → 100% {opacity:1, translateY(0)}` (from `tailwind.config.js`).

## Target

Make `Modal.jsx` own its own exit animation internally, so **every** consumer gets a proper close animation for free with zero call-site changes: on `onClose`, don't call the parent's close handler immediately, flip an internal `closing` state, play a ~180ms fade+scale-down exit, then call the real `onClose` after the transition completes.

```jsx
// src/components/common/Modal.jsx - target (full file)
import { useEffect, useState } from 'react'
import { createPortal } from 'react-dom'

const EXIT_MS = 180

function Modal({ title, subtitle, children, onClose, size = 'lg' }) {
  const widths = { md: 'max-w-lg', lg: 'max-w-2xl', xl: 'max-w-4xl' }
  const [closing, setClosing] = useState(false)

  const requestClose = () => {
    if (closing) return
    setClosing(true)
    setTimeout(onClose, EXIT_MS)
  }

  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') requestClose() }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return createPortal(
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      role="dialog"
      aria-modal="true"
      aria-label={title}
    >
      {/* Backdrop */}
      <div
        className={`absolute inset-0 bg-black/30 dark:bg-zinc-950/80 transition-opacity duration-[180ms] ease-[cubic-bezier(0.25,1,0.5,1)] ${closing ? 'opacity-0' : 'opacity-100'}`}
        onClick={requestClose}
      />

      {/* Panel */}
      <div className={`
        relative bg-white dark:bg-zinc-900 border border-slate-200 dark:border-zinc-700
        rounded-xl shadow-2xl shadow-black/10 dark:shadow-black/60
        w-full ${widths[size]} flex flex-col max-h-[90vh]
        transition-[opacity,transform] duration-[180ms] ease-[cubic-bezier(0.25,1,0.5,1)]
        ${closing ? 'opacity-0 scale-95 translate-y-2' : 'opacity-100 scale-100 translate-y-0'}
      `}>
        {/* Header */}
        <div className="flex items-start justify-between px-6 py-4 border-b border-slate-200 dark:border-zinc-800">
          <div>
            <h2 className="text-sm font-semibold text-slate-900 dark:text-white">{title}</h2>
            {subtitle && (
              <p className="text-xs text-slate-400 dark:text-zinc-500 mt-0.5">{subtitle}</p>
            )}
          </div>
          <button
            onClick={requestClose}
            className="ml-4 p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150 active:scale-95"
          >
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" />
            </svg>
          </button>
        </div>

        {/* Body */}
        <div className="px-6 py-4 overflow-y-auto">
          {children}
        </div>
      </div>
    </div>,
    document.body
  )
}

export default Modal
```

Note the entrance keeps `animate-fade-slide`. Wait, it was removed from the outer `<div>` in the target above because the panel and backdrop now each own their own transition-based enter+exit. To preserve the existing entrance look and feel (`fadeSlide`'s `translateY(10px)→0` at 280ms cubic-bezier(0.16,1,0.3,1)), the panel needs an entering state too, otherwise it will pop in at full opacity/scale instead of animating in. Add that in Step 2 below rather than losing the entrance animation.

## Repo conventions to follow

- Tailwind arbitrary-value syntax for one-off durations/eases (`duration-[180ms]`, `ease-[cubic-bezier(...)]`), same pattern as plan 001.
- `EXIT_MS` as a local const at the top of the file, mirrors how `ConfirmDialog.jsx` and other one-off components in this codebase keep small magic numbers local rather than in a shared config, since there's no shared token file yet (see plan 011 for consolidation).
- Every existing call site already does `{show && <Modal onClose={() => setShow(false)} ...>}` (e.g. `src/pages/Assets/index.jsx:299-307`, `src/pages/Accounts/index.jsx` similar). This plan must NOT require touching those call sites; the delay lives entirely inside `Modal.jsx`'s own `onClose` timing.

## Steps

1. Add `import { useEffect, useState } from 'react'` (add `useState` to the existing import) and the `const EXIT_MS = 180` constant at the top of the file.

2. Add an **entering** state too, so the open animation is preserved (currently provided by `animate-fade-slide` on the outer wrapper, which this plan removes since the wrapper now needs to stay static. The backdrop and panel below it own the actual visible motion):
   ```jsx
   const [entered, setEntered] = useState(false)
   useEffect(() => {
     const raf = requestAnimationFrame(() => requestAnimationFrame(() => setEntered(true)))
     return () => cancelAnimationFrame(raf)
   }, [])
   ```
   Then make the panel's className state depend on both `entered` and `closing`:
   ```jsx
   ${!entered || closing ? 'opacity-0 scale-95 translate-y-2' : 'opacity-100 scale-100 translate-y-0'}
   ```
   and the backdrop's:
   ```jsx
   ${!entered || closing ? 'opacity-0' : 'opacity-100'}
   ```
   Use `transition-[opacity,transform] duration-[220ms] ease-[cubic-bezier(0.16,1,0.3,1)]` for entry-matching duration/curve (220ms is close to the original 280ms `fadeSlide`, round to 220 as the plan's entry duration since exit is intentionally faster at 180ms per the asymmetric-timing rule in AUDIT.md #4; do not use two different transition declarations for the same element, one `transition-[...]` class covers both directions since duration/curve stay the same in and out here, which is an acceptable simplification for a first pass).

3. Wire the `requestClose` function (shown in Target) into both the backdrop's `onClick` and the header close button's `onClick`, and into the existing `Escape` keydown handler, replacing all three former direct `onClose` calls.

4. Verify no other file imports `Modal` and calls `onClose` expecting synchronous unmount (grep `<Modal` and check nothing relies on the parent's state changing before ~180ms after the click), if you find such a dependency, STOP and report rather than guessing at a fix.

## Boundaries

- Do NOT touch any of the ~15 modal call sites (`AddAssetModal.jsx`, `UserModal.jsx`, `ImportModal.jsx`, `QRModal.jsx`, `AddRecordModal.jsx`, `AddMaintenanceModal.jsx`, `AddDisposalModal.jsx`, `ResetPasswordModal.jsx`, `ForgotPasswordModal.jsx`, `LogEntryModal.jsx`, etc.). This plan is scoped to `Modal.jsx` only, and must work for all of them unmodified.
- Do NOT touch `ConfirmDialog.jsx`. It's a visually similar but separate component; if it has the same problem, that's a follow-up finding, not part of this plan.
- Do NOT add a new dependency (no Framer Motion, no `react-transition-group`), plain React state + CSS transitions only.
- If a consumer passes `onClose` as something other than a state setter (e.g. it triggers a navigation or has side effects that must happen synchronously), the ~180ms delay could visibly matter. Check the call sites for anything beyond `setShowX(false)`/`setEditing(null)` patterns before finishing, and report anything unusual rather than silently changing behavior.

## Verification

- **Mechanical**: `cd frontend_sj/frontend && npm run build`, clean build.
- **Feel check**:
  - Open any modal (e.g. "Add Asset" on the Assets page), confirm it still fades/slides in the same as before.
  - Close it via the × button, confirm it now fades and scales down slightly (not just a hard cut) before disappearing, matching timing across at least 3 different modals (AddAssetModal, ImportModal, ConfirmDialog-adjacent ResetPasswordModal) to confirm the fix applies uniformly since they all share `Modal.jsx`.
  - Close via clicking the backdrop and via pressing Escape, confirm both trigger the same exit animation, not an instant unmount.
  - In DevTools Animations panel, set playback to 25% and confirm the panel doesn't flash or double-render during the exit.
  - Rapidly click the × button twice, confirm it doesn't fire `onClose` twice or restart the exit animation oddly (the `if (closing) return` guard in `requestClose` should prevent this).
- **Done when**: every modal built on `Modal.jsx` visibly animates out (fade + slight scale-down) before being removed from the DOM, with no call-site code changes required.
