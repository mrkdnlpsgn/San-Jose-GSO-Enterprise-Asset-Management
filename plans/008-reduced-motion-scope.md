# 008 - Scope `prefers-reduced-motion` to movement, not all transitions

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: LOW-MEDIUM
- **Category**: Accessibility
- **Estimated scope**: 1 file (`frontend_sj/frontend/src/index.css`)

## Problem

```css
/* frontend_sj/frontend/src/index.css:85-94 - current (full rule) */
@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

This is the "boilerplate CSS-Tricks snippet" version of reduced-motion handling: it clamps **every** `transition-duration` and `animation-duration` on the page to near-zero, including opacity/color transitions that aid comprehension (a hover state change, a focus ring appearing, a toast's opacity fade). AUDIT.md #6 is explicit: "Reduced motion means fewer and gentler animations, **not zero**. Keep transitions that aid comprehension, remove position changes." Right now this app removes all feedback, not just movement.

## Target

Keep the blanket zero-duration rule for anything that moves (`transform`), but exempt a short, explicit list of properties that are comprehension aids, not motion: `opacity`, `color`, `background-color`, `border-color`, `box-shadow`, by giving them a short, deliberate duration instead of near-zero:

```css
/* target */
@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }

  /* Reduced motion means gentler, not zero - keep short opacity/color
     transitions that aid comprehension (hover, focus, toast fade-in);
     only movement (transform/position) is fully suppressed above. */
  *[class*="transition-opacity"],
  *[class*="transition-colors"],
  *[class*="transition-all"] {
    transition-duration: 150ms !important;
  }
}
```

This is a pragmatic, low-risk approach given the app has no per-component reduced-motion branching in JS (unlike a React app using `useReducedMotion()` from a motion library). It works entirely at the CSS layer, matching how the existing rule already works, and only re-enables duration for the specific Tailwind utility classes already used for hover/color feedback throughout the codebase (`transition-colors`, `transition-opacity`, and the (separately flagged in plan 003) `transition-all` usages).

## Repo conventions to follow

- This is the only `prefers-reduced-motion` block in the codebase. No existing convention to extend beyond what's already here. Keep the fix inside the same `index.css` file, immediately following the existing rule, rather than creating a new CSS file.
- The app uses Tailwind utility classes almost exclusively (`transition-colors`, `transition-opacity`, `transition-all`, `transition-transform`) rather than custom CSS classes. The attribute-selector approach (`[class*="..."]`) is the only way to target "elements using this Tailwind utility" from plain CSS without modifying every component; this is a deliberate, minimal choice for this fix, not a general pattern to reuse elsewhere.

## Steps

1. Open `frontend_sj/frontend/src/index.css` and locate the existing `@media (prefers-reduced-motion: reduce)` block (lines 85-94).
2. Add the new rule shown in Target immediately after the closing `}` of the existing `*, *::before, *::after { ... }` rule, but still inside the same `@media` block.
3. Do not modify the existing four `!important` declarations. They remain the "movement suppressed" baseline; the new rule is an *additional*, more specific override for the listed selectors.

## Boundaries

- Do NOT touch any component files in this plan. This is a single CSS-file fix.
- Do NOT attempt to add JS-based reduced-motion branching (e.g. a `usePrefersReducedMotion` hook). That's a larger change affecting many components; this plan is scoped to the CSS-only fix.
- Do NOT change `scroll-behavior: auto` or the `animation-iteration-count: 1` line. Those are correct as-is (a looping animation should still only play once under reduced motion, and instant-scroll is correct, not a motion-that-aids-comprehension case).

## Verification

- **Mechanical**: `cd frontend_sj/frontend && npm run build`, clean build; visually confirm the CSS output includes the new rule (check `npm run build`'s output CSS or just re-read the source file).
- **Feel check**:
  - In Chrome DevTools, open the Rendering panel, set "Emulate CSS media feature prefers-reduced-motion" to `reduce`.
  - Hover over a sidebar link or a button, confirm the color/background transition still plays smoothly (not instant), where before this fix it would have been instant.
  - Open/close a modal, confirm the modal's slide/scale motion (transform-based) is now instant (no movement), which is correct reduced-motion behavior, while its fade (opacity, if plan 002 has been applied) still transitions briefly.
  - Trigger a toast, confirm its entrance is still perceptible as a brief fade even under reduced motion, not an instant snap.
- **Done when**: under `prefers-reduced-motion: reduce`, transform/position-based motion is suppressed to near-zero as before, but opacity/color-based feedback (hover states, toast fades, focus rings) still has a short, perceptible transition.
