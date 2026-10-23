---
name: San Jose GSO Enterprise Asset Management
description: Government asset-tracking system for GSO staff, efficient, trustworthy, never intimidating
colors:
  seal-green: "#1fad55"
  seal-green-deep: "#126e36"
  seal-green-hover: "#11572c"
  seal-green-tint: "#edfcf2"
  seal-green-shadow: "#0e4824"
  paper-white: "#ffffff"
  ink-slate: "#0f172a"
  slate-border: "#e2e8f0"
  slate-muted: "#94a3b8"
  near-black-zinc: "#09090b"
  zinc-panel: "#18181b"
  zinc-border: "#27272a"
  zinc-border-hover: "#3f3f46"
  status-serviceable: "#10b981"
  status-repairable: "#f59e0b"
  status-unserviceable: "#ef4444"
  status-registered: "#3b82f6"
  status-transferred: "#f97316"
  status-archived: "#71717a"
typography:
  display:
    fontFamily: "Inter, system-ui, sans-serif"
    fontSize: "1.875rem"
    fontWeight: 800
    lineHeight: 1.2
    letterSpacing: "-0.01em"
  headline:
    fontFamily: "Inter, system-ui, sans-serif"
    fontSize: "1.5rem"
    fontWeight: 700
    lineHeight: 1.3
    letterSpacing: "-0.01em"
  title:
    fontFamily: "Inter, system-ui, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 600
    lineHeight: 1.4
  body:
    fontFamily: "Inter, system-ui, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "Inter, system-ui, sans-serif"
    fontSize: "0.6875rem"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "0.1em"
rounded:
  sm: "6px"
  md: "8px"
  lg: "12px"
  full: "9999px"
spacing:
  xs: "6px"
  sm: "10px"
  md: "16px"
  lg: "24px"
components:
  button-primary:
    backgroundColor: "{colors.seal-green-deep}"
    textColor: "{colors.paper-white}"
    rounded: "{rounded.md}"
    padding: "8px 14px"
  button-primary-hover:
    backgroundColor: "{colors.seal-green-hover}"
  button-secondary:
    backgroundColor: "#f1f5f9"
    textColor: "#334155"
    rounded: "{rounded.md}"
    padding: "8px 14px"
  button-danger:
    backgroundColor: "#dc2626"
    textColor: "{colors.paper-white}"
    rounded: "{rounded.md}"
    padding: "8px 14px"
  input-field:
    backgroundColor: "{colors.paper-white}"
    textColor: "{colors.ink-slate}"
    rounded: "{rounded.md}"
    padding: "10px 14px"
  badge-status:
    rounded: "{rounded.full}"
    padding: "2px 10px"
  modal-panel:
    backgroundColor: "{colors.paper-white}"
    rounded: "{rounded.lg}"
    padding: "24px"
---

# Design System: San Jose GSO Enterprise Asset Management

## 1. Overview

**Creative North Star: "The Custodian's Desk"**

GSO staff are property custodians first, software operators second. The interface is built like a well-organized desk in a municipal records office: everything has a border and a place, nothing floats or glows without reason, and the one accent color present is the same green on the seal hanging on the wall behind them. It opens in daylight (light mode is the default) because that's when the desk work happens; a dark mode exists as a full first-class alternate, not an afterthought, for evening sessions or personal preference.

The system explicitly rejects the look of old government portals (dense, flat hierarchy, no visual prioritization), generic Bootstrap admin templates (CoreUI/AdminLTE off-the-shelf blue-and-white), consumer-app playfulness (illustration, saturated gradients, social energy), and SAP-style heavy enterprise density (stacked modals, training-required navigation). Every screen should look like it was built specifically for this office, not skinned from a template.

AI-generated content (lifecycle recommendations, disposal justifications, audit digests) is visually set apart as advisory, not authoritative: it reads like a colleague's note attached to a record, never like the record itself.

**Key Characteristics:**
- Light-by-default, dark as an equally complete alternate, never forced
- One accent color (seal green), used sparingly against slate/zinc neutrals
- Flat, bordered surfaces; shadow is reserved for things that temporarily float
- A six-color status vocabulary carries all condition/lifecycle meaning, always paired with text, never color alone
- Inter throughout, one typeface, hierarchy built from weight and size, not font-switching

## 2. Colors

Restrained strategy: tinted neutrals carry nearly the entire surface, with Municipal Seal Green appearing only at points of action or brand presence. A six-color status vocabulary is the one deliberate exception, used exclusively for condition/lifecycle state, never decoratively.

### Primary
- **Municipal Seal Green** (`#1fad55`): the brand identity color, focus rings, the active nav-item ping, the login page's seal glow, icon-chip tints, active-state dots. Never used as a solid fill behind white text; at that weight it fails WCAG AA contrast (~2.9:1).
- **Seal Green Deep** (`#126e36`): the actual primary-button fill at rest. One step darker than Municipal Seal Green so white button text clears WCAG AA (6.3:1) while staying unmistakably the same hue.
- **Seal Green Hover** (`#11572c`): hover/active state for primary buttons. Darker still, not brighter, reinforces "pressed," not "excited."
- **Seal Green Tint** (`#edfcf2`): the faint gradient wash behind the login page's brand panel and icon chips (`bg-brand-500/10` equivalents). Barely-there presence, texture rather than color.

### Neutral
- **Paper White** (`#ffffff`): light-mode page background and card surfaces. The default state of the app.
- **Ink Slate** (`#0f172a`): primary text in light mode.
- **Slate Border** (`#e2e8f0`): card borders, dividers, input borders in light mode.
- **Slate Muted** (`#94a3b8`): placeholder text, secondary labels, disabled states.
- **Near-Black Zinc** (`#09090b`): dark-mode page background. Tinted near-black, never pure `#000`.
- **Zinc Panel** (`#18181b`): dark-mode card and modal surfaces.
- **Zinc Border** (`#27272a`): dark-mode borders and dividers; `#3f3f46` on hover.

### Status Vocabulary (Full Palette, scoped to condition/lifecycle only)
- **Serviceable / Assigned**, emerald (`#10b981`): the asset is in its intended working state.
- **Repairable / Under Maintenance**, amber (`#f59e0b`): needs attention, not yet urgent.
- **Unserviceable / Disposed**, red (`#ef4444`): end of useful life or actively broken.
- **Registered**, blue (`#3b82f6`): newly entered, not yet acted upon.
- **Transferred**, orange (`#f97316`): in motion between offices.
- **Archived**, zinc (`#71717a`): closed out, historical record only.

Each status renders as a tinted pill: 10% opacity background of its color, full-opacity text in that color, a matching 1px ring. Never a solid fill, never color alone without the label text beside it.

### Named Rules
**The One Green Rule.** Seal green (in whichever shade fits the surface - bright for accents and rings, deep for solid button fills) appears only where the user can take an action or where brand identity belongs. If a screen has more than one shade of green doing decorative work, it's wrong.

**The Tinted Neutral Rule.** No neutral in this system is pure black or pure white in *intent*, even where the literal value is `#ffffff` or near it - Paper White is a canvas for content, not a design statement, and Near-Black Zinc always carries a faint cool tint rather than true black.

## 3. Typography

**Display/Body Font:** Inter (with `system-ui, sans-serif` fallback)

**Character:** A single, highly legible grotesque carries the entire system - no serif, no mono, no second display face. Hierarchy comes entirely from weight and size steps, which keeps every screen feeling like the same tool even as density varies from a dashboard card to a login hero.

### Hierarchy
- **Display** (extrabold 800, 1.875rem–1.5rem depending on viewport, tight tracking): the login page's product name and "Sign in" heading. Used exactly twice in the whole app, entry points, not routine UI.
- **Headline** (bold 700, 1.5rem): page-level headings inside the authenticated app.
- **Title** (semibold 600, 0.875rem): card headers, modal titles, section labels.
- **Body** (regular 400, 0.875rem, 1.5 line-height): all table content, form labels, descriptions. Capped conversationally at a comfortable reading measure inside cards and drawers.
- **Label** (semibold 600, 0.6875rem, uppercase, wide tracking): nav section headers ("Main Menu", "Admin"), badge text, the smallest tier, used for structural signposting, never for content a user needs to read carefully.

### Named Rules
**The One Typeface Rule.** Inter is the only font family in the system. If a new screen needs "more personality," the answer is weight and scale, never a second typeface.

## 4. Elevation

Flat-by-default, shadow-as-interruption. At rest, every surface (dashboard tiles, list rows, sidebar) is a flat fill separated from its neighbors by a 1px border, never a resting shadow. Shadow is reserved for two situations only: something temporarily floating above the page (modals, the collapsed-sidebar hover tooltip), or a direct response to interaction (a primary button lifting slightly on hover, the login page's seal-icon glow). This keeps the working surface calm; when something does cast a shadow, it reads as a real signal, not decoration.

### Shadow Vocabulary
- **Modal overlay** (`box-shadow: 0 25px 50px -12px rgba(0,0,0,0.25)` light / deeper black at 60% in dark mode): the only resting shadow in the system, because a modal is genuinely floating above the page.
- **Button hover lift** (`shadow-md` tinted with `seal-green/20`): confirms a primary action is interactive, appears only on `:hover`.
- **Brand glow** (`blur-2xl` soft green bloom behind the login seal): a one-off decorative moment reserved for the login screen's brand panel, not reused elsewhere.

### Named Rules
**The Floating-Only Rule.** If an element isn't literally overlapping other content (a modal, a tooltip) or being actively interacted with (hover, active), it does not get a shadow. Borders do the separation work everywhere else.

## 5. Components

### Buttons
- **Shape:** `rounded-md` (8px), never fully rounded except icon-only variants.
- **Primary:** Seal Green Deep fill (`#126e36`), white text, semibold. The depth is deliberate: it's the shade that keeps white text at 6.3:1 contrast, not the brighter Municipal Seal Green used for accents. Hover deepens further to Seal Green Hover with a faint green-tinted shadow lift; active scales to 97%.
- **Secondary:** Slate-100 fill (light) / Zinc-800 fill (dark), bordered, for anything that isn't the page's main action.
- **Danger:** Solid red-600, reserved exclusively for destructive confirmations (delete asset, delete user).
- **Ghost:** No fill at rest, text-only, hover reveals a faint neutral background. Used for tertiary actions like "Clear" inside cards.
- All variants share the same focus ring (2px, offset, colored to match variant) and the same 150ms transition timing.

### Badges / Status Pills
- **Style:** `rounded-full`, 10%-opacity tinted background, full-opacity text, matching 1px ring, small leading dot for the general-purpose Badge component (accounts, generic states).
- **Status-specific variant:** the six-color condition/lifecycle vocabulary (Section 2), no leading dot, used in tables and drawers where space is tighter.

### Cards / Containers
- **Corner Style:** `rounded-xl` (12px), one step rounder than buttons/inputs, marking cards as containers rather than controls.
- **Background:** Paper White / Zinc Panel.
- **Shadow Strategy:** none at rest (see Elevation). Border only.
- **Border:** 1px, Slate Border / Zinc Border, brightening slightly on hover for interactive cards (quick-action tiles).
- **Internal Padding:** 16–24px depending on density; table-style cards run tighter.

### Inputs / Fields
- **Style:** `rounded-md`, 1px border (Slate Border / Zinc Border), white/zinc-800 fill.
- **Focus:** border shifts to Seal Green plus a 2px Seal Green ring. The single most saturated moment most screens ever show.
- **Error:** border and ring shift to red-500/red-400; error copy appears below in red, same position every time so the eye knows where to look.
- **Hover (idle, unfocused):** border darkens one step as an affordance hint before focus.

### Navigation
- **Style:** fixed-width sidebar (240px expanded / 60px collapsed), flat Paper White / Near-Black Zinc background, 1px right border.
- **Active item:** inverted fill, near-black background with white text in light mode, white background with near-black text in dark mode. This is the one place the system inverts rather than tints, making "you are here" unmistakable.
- **Hover (inactive):** faint neutral background tint, no color shift.
- **Mobile:** the same sidebar slides in as an overlay with a scrim backdrop, collapsing to icon-only never happens on mobile. It's expanded-or-hidden only.
- **Unread signal:** a small animated ping dot in Seal Green on the Audit Logs icon. The only place notification state appears, deliberately rare.

## 6. Do's and Don'ts

### Do:
- **Do** keep Municipal Seal Green (`#1fad55`) to accents, focus rings, and active-state dots; use Seal Green Deep (`#126e36`) for any solid button fill carrying white text, so contrast stays at 6.3:1 instead of the ~2.9:1 the brighter shade produces.
- **Do** pair every status color with its text label. Color alone never carries meaning (WCAG requirement, and the PRODUCT.md accessibility line: "no reliance on color alone to convey status").
- **Do** default new screens to light mode styling first, then add `dark:` variants, light is the app's default state, not an equal coin-flip.
- **Do** use borders for separation between flat surfaces; reach for `rounded-xl` + border before reaching for a card shadow.
- **Do** present AI-generated text (recommendations, justifications, digests) with visible rationale attached, never as a bare conclusion.

### Don't:
- **Don't** add a resting shadow to any card, list row, or sidebar. Shadow is reserved for modals and hover/active feedback only.
- **Don't** introduce a second typeface. Hierarchy is Inter's weight and size scale, full stop.
- **Don't** build anything that could pass for a "generic Bootstrap admin template" (CoreUI/AdminLTE). No default blue-and-white palette, no unstyled off-the-shelf component look.
- **Don't** reach for consumer-app patterns: illustration, playful motion, saturated gradients, social-media energy. This is an operational tool for serious daily work.
- **Don't** stack modals on modals or add fields "just in case". That's the SAP-style density this system is explicitly built against.
- **Don't** use `border-left`/`border-right` colored stripes as a status or category indicator, status is a tinted pill (Section 2/5), never a side-stripe.
- **Don't** let an AI-generated recommendation auto-execute or visually read as equal-weight to a human decision. It always sits one step below, with its reasoning visible.
