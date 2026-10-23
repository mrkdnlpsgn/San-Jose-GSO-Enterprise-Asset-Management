# 010 - Fix collapsed-sidebar tooltip origin and gate it behind a hover-capable-device check

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: LOW
- **Category**: Physicality & origin / Accessibility
- **Estimated scope**: 1 file (`frontend_sj/frontend/src/components/layout/Sidebar.jsx`)

## Problem

```jsx
// frontend_sj/frontend/src/components/layout/Sidebar.jsx:176-188 - current
{isCollapsed && (
  <div className="
    hidden lg:block
    absolute left-full ml-3 top-1/2 -translate-y-1/2 z-50
    bg-slate-800 dark:bg-zinc-800 border border-slate-700 dark:border-zinc-700 text-white text-xs font-medium
    px-2.5 py-1.5 rounded-lg shadow-xl pointer-events-none whitespace-nowrap
    opacity-0 group-hover:opacity-100 scale-95 group-hover:scale-100
    transition-all duration-150
  ">
    {label}
    <span className="absolute right-full top-1/2 -translate-y-1/2 border-4 border-transparent border-r-slate-800 dark:border-r-zinc-800" />
  </div>
)}
```

Two issues:
1. **Wrong transform origin**. This is a trigger-anchored popover (a label tooltip appearing to the right of a collapsed nav icon, positioned via `absolute left-full ml-3`), but it scales `scale-95 → scale-100` with the default `transform-origin: center`, so it visibly grows from its own middle rather than from the icon that triggered it (its little arrow, the `<span>` with the border-triangle, points left toward the icon. The growth direction should match). This is a real finding per AUDIT.md #3 (modals are exempt from this rule, but this isn't a modal).
2. **Ungated hover**. No `@media (hover: hover) and (pointer: fine)` gating. On a touch device, tapping the collapsed icon can leave the `group-hover` state "stuck" active, leaving the tooltip visibly popped open until the user taps elsewhere.
3. Minor: `transition-all` here is a small, contained element (opacity + transform only actually change), lower priority than the sidebar's own `transition-all` (plan 003) but still worth tightening to `transition-[opacity,transform]` while touching this block.

## Target

```jsx
// target
{isCollapsed && (
  <div className="
    hidden lg:block
    absolute left-full ml-3 top-1/2 -translate-y-1/2 z-50
    bg-slate-800 dark:bg-zinc-800 border border-slate-700 dark:border-zinc-700 text-white text-xs font-medium
    px-2.5 py-1.5 rounded-lg shadow-xl pointer-events-none whitespace-nowrap
    opacity-0 scale-95 origin-left
    max-[1023px]:opacity-0
    [@media(hover:hover)_and_(pointer:fine)]:group-hover:opacity-100
    [@media(hover:hover)_and_(pointer:fine)]:group-hover:scale-100
    transition-[opacity,transform] duration-150
  ">
    {label}
    <span className="absolute right-full top-1/2 -translate-y-1/2 border-4 border-transparent border-r-slate-800 dark:border-r-zinc-800" />
  </div>
)}
```

`origin-left` fixes the scale direction (Tailwind's `transform-origin: left center`). The `[@media(hover:hover)_and_(pointer:fine)]:group-hover:*` arbitrary-variant syntax is Tailwind's way of writing a `group-hover` rule that's itself wrapped in a media query. This is the correct, if slightly verbose, way to express "only apply this hover-triggered style on hover-capable, fine-pointer devices" using Tailwind v3+'s arbitrary variants, since Tailwind doesn't ship a first-class `hover-hover:` variant out of the box.

## Repo conventions to follow

- Check `tailwind.config.js` first, if this project's Tailwind version/config already defines a custom `hoverable`/`hover-hover` variant (grep `screens\.hover|hover-hover|pointer-fine` in the config), use that instead of the verbose arbitrary-variant syntax shown above, since a pre-existing named variant is cleaner. If none exists, use the arbitrary-variant syntax as-is. Do not add a new named variant to the Tailwind config as part of this plan (that's a bigger, separate decision).
- `origin-left`, `origin-center`, etc. are stock Tailwind utilities. No custom config needed.

## Steps

1. Grep `frontend_sj/frontend/tailwind.config.js` for any existing hover-capable-device variant definition. If found, use it in place of the arbitrary-variant syntax in Target and note which one you used in your final report.
2. In `Sidebar.jsx`, replace the tooltip `div`'s className (lines 176-188 in Target's numbering, confirm exact current line numbers before editing since prior plans in this set may have shifted them if executed out of order) with the version shown in Target.
3. Confirm the `group` className is present on the parent element the `group-hover:` selectors target (it should already be. Check the enclosing `NavLink`/wrapper a few lines above line 176 for a `group` class; if missing, STOP and report rather than guessing where to add it).

## Boundaries

- Do NOT change the tooltip's positioning (`left-full ml-3 top-1/2 -translate-y-1/2`), its content, or the little arrow `<span>`.
- Do NOT touch the sidebar's own width-collapse transition (`aside`'s className). That's plan 003's scope.
- Do NOT add a new Tailwind config variant unless Step 1 finds the codebase already has a convention for one to reuse.

## Verification

- **Mechanical**: `cd frontend_sj/frontend && npm run build`, clean build (arbitrary variant syntax errors show up as unrecognized/unstyled classes at runtime, not build failures, so also do the feel-check below to confirm the CSS actually applied).
- **Feel check**:
  - Collapse the sidebar on desktop, hover over a nav icon with a mouse, confirm the tooltip now grows from its left edge (nearest the icon) rather than from its own center.
  - Using Chrome DevTools' device toolbar in touch-emulation mode (or an actual touch device), tap a collapsed nav icon, confirm the tooltip does NOT appear/stick open (since hover-gating should suppress it entirely on a touch-only pointer).
  - Confirm normal desktop mouse-hover behavior (tooltip appears smoothly on hover, disappears on mouse-out) is otherwise unchanged.
- **Done when**: the tooltip scales from `origin-left`, and the hover-triggered opacity/scale classes are gated so they don't visibly apply on touch/coarse-pointer devices.
