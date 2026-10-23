---
name: San Jose GSO Mobile (Flutter)
description: Field companion app for GSO custodians: QR-driven asset lookup on the go, with a full light/dark theme choice
colors:
  seal-green: "#1FAD55"
  seal-green-forest: "#178A44"
  seal-green-button: "#126E36"
  near-black-zinc: "#09090B"
  zinc-panel: "#18181B"
  zinc-border: "#27272A"
  paper-white: "#FFFFFF"
  ink-slate: "#0F172A"
  slate-border: "#E2E8F0"
  status-serviceable: "#1FAD55"
  status-repairable: "#F59E0B"
  status-unserviceable: "#EF4444"
  status-maintenance: "#F59E0B"
  status-disposed: "#EF4444"
  status-registered-mobile: "#6B7280"
  status-assigned-mobile: "#3B82F6"
  status-transferred-mobile: "#60A5FA"
  status-archived-mobile: "#757575"
typography:
  headline:
    fontFamily: "platform default (Roboto on Android, SF Pro on iOS)"
    fontSize: "1.5rem"
    fontWeight: 700
  body:
    fontFamily: "platform default"
    fontSize: "0.875rem"
    fontWeight: 400
  label:
    fontFamily: "platform default"
    fontSize: "0.75rem"
    fontWeight: 600
rounded:
  sm: "8px"
  lg: "12px"
  chip: "6px"
spacing:
  sm: "16px"
  md: "24px"
  lg: "40px"
components:
  button-primary:
    backgroundColor: "{colors.seal-green-button}"
    textColor: "#ffffff"
    rounded: "{rounded.sm}"
    padding: "14px 0"
  input-field:
    backgroundColor: "{colors.zinc-panel}"
    textColor: "#ffffff"
    rounded: "{rounded.sm}"
  card:
    backgroundColor: "{colors.zinc-panel}"
    rounded: "{rounded.lg}"
  badge-status:
    rounded: "{rounded.chip}"
    padding: "4px 10px"
---

# Design System: San Jose GSO Mobile (Flutter)

## 1. Overview

**Creative North Star: "The Custodian's Desk" - Field Edition**

This is the same desk, taken into the field. The brand, the personality, the "efficient, approachable, reliable" voice from PRODUCT.md are identical to the web app. This isn't a different product, it's the same GSO custodian's toolkit with a QR scanner in their pocket instead of a monitor in front of them. Mobile now offers the same choice web does: light by default expectation aside, the user picks Light, Dark, or System from Settings, and the whole app, chrome and body text alike, follows that choice immediately, because every screen reads its neutrals through a `ThemeExtension` (`AppColors`, accessed via `context.colors`) rather than a fixed value.

That said, this scan surfaced real gaps between the two clients that are not intentional design decisions. They're drift from building the two apps somewhat independently. They're documented honestly below and flagged in Do's and Don'ts rather than smoothed over, because closing them is a straightforward follow-up, not a redesign.

**Key Characteristics:**
- Full light/dark theme support, user-selectable in Settings (Light / Dark / System), persisted across restarts, closes what used to be mobile's biggest gap from web
- Same brand green (`#1FAD55`), same flat-and-bordered elevation philosophy as web (`elevation: 0` + a border on every card), in both themes
- Platform-default typography (Roboto / SF Pro) rather than web's Inter, still a real gap, not a deliberate mobile-native choice
- Text size is user-adjustable (Small / Default / Large) via a global `TextScaler`, another capability web doesn't yet have
- Condition badges (serviceable/repairable/unserviceable) already match web's color meanings; lifecycle badges (registered/assigned/transferred) currently do not. See Section 2

## 2. Colors

Restrained strategy, same as web: tinted neutrals carry the surface, with Seal Green appearing only at points of action or brand presence. Unlike before, the neutrals are no longer a single fixed set. They're a `ThemeExtension` (`AppColors`) with a dark and a light instance, resolved at runtime via `context.colors`, so the same widget code renders correctly in either theme.

### Primary (theme-invariant - same in light and dark)
- **Municipal Seal Green** (`#1FAD55`): identical value to web's brand color. Used for the login icon tile, focused input borders, and accents. No longer used for solid button fills, since that failed contrast in either theme.
- **Seal Green Deep / `brandButton`** (`#126E36`): the actual button-fill color, matching web's identical token exactly. Passes AA (6.3:1) against white button text regardless of the surrounding theme, since button contrast is about the button's own fill/text pair, not the page background.
- **Brand Dark Accent** (`#178A44`): a secondary, sparingly-used accent seen only in two places (dashboard highlight, a report-definition color).

### Neutral - Dark (`AppColors.dark`)
- **Near-Black Zinc** (`#09090B`): scaffold background, identical value to web's dark-mode token of the same name.
- **Zinc Panel** (`#18181B`): card and input fill surface, identical to web's dark-mode card color.
- **Zinc Border** (`#27272A`): card and divider borders, identical to web's dark-mode border color.
- **`textSecondary`** (`Colors.white70`, ≈9.7:1) / **`textTertiary`** (`Colors.white54`, ≈6.1:1): both clear WCAG AA against Near-Black Zinc.

### Neutral - Light (`AppColors.light`)
- **Paper White** (`#FFFFFF`): scaffold background and card surface, identical value to web's light-mode token of the same name; mobile relies on the same border-only separation web does, not a tinted card background.
- **Slate Border** (`#E2E8F0`): card and divider borders, identical to web's light-mode border token.
- **`textPrimary`** (`#0F172A`, Ink Slate) / **`textSecondary`** (`#334155`, ≈12.6:1) / **`textTertiary`** (`#64748B`, ≈4.76:1): the light-mode text tiers. `textTertiary`'s exact shade is the same slate-500 web's own login page was fixed to use earlier, one deliberate point of cross-platform token reuse, not a coincidence.

Access pattern: `context.colors.bg` / `.surface` / `.border` / `.textPrimary` / `.textSecondary` / `.textTertiary`, never a bare `Colors.whiteXX` literal or a static `AppTheme` field, since those can't react to a theme change at runtime.

### Status Vocabulary - Condition (matches web)
- **Serviceable**: Seal Green: matches web's meaning (web uses a separate emerald; same "good" meaning, different exact hue).
- **Repairable**, amber (`#F59E0B`): exact match to web.
- **Unserviceable**, red (`#EF4444`): exact match to web.

### Status Vocabulary - Lifecycle (does NOT match web)
- **Registered**, gray (`#6B7280`) on mobile vs. **blue** on web.
- **Assigned**, blue (`#3B82F6`) on mobile vs. **emerald** on web.
- **Transferred**, light blue (`#60A5FA`) on mobile vs. **orange** on web.
- **Under Maintenance**, amber: matches web.
- **Disposed**, red: matches web.
- **Archived**, raw Material `Colors.grey.shade600` (not a themed token) vs. web's zinc-based token; conceptually both gray, but mobile's isn't drawn from the app's own color system.

### Named Rules
**The One Desk Rule.** Seal Green means the same thing on both clients: brand identity and primary action, never decoration. Everything else in this section inherits web's palette values exactly where the code already does (near-black-zinc, zinc-panel, zinc-border, paper-white, slate-border) - new mobile screens should reach for those before inventing a new gray.

**The No Static Neutral Rule.** Neutrals live only in `AppColors`, read via `context.colors`. A `Colors.white54` or `AppTheme.bg`-style literal reintroduces the exact bug this pass fixed: a value that can't respond when the user switches themes in Settings.

## 3. Typography

**Font:** Platform default - Roboto on Android, SF Pro on iOS. No custom font family is set anywhere in `app_theme.dart`.

**Character:** Currently there isn't a deliberate typographic character - the app inherits whatever the OS provides, which means the same screen looks subtly different on Android vs. iOS, and neither matches web's Inter. This is the clearest concrete gap between the two clients.

### Hierarchy
- **Headline** (bold 700, ~1.5rem): screen titles like "San Jose GSO" on the login screen.
- **Body** (regular 400, ~0.875rem): form labels, list content, most on-screen text.
- **Label** (semibold 600, ~0.75rem): status badge text, small captions.

### Named Rules
**The Borrowed Type Rule (gap, not policy).** Unlike web's deliberate "One Typeface" rule, mobile's current type system is simply whatever Flutter's Material defaults provide. This is not a considered choice worth preserving - see Do's and Don'ts.

## 4. Elevation

Flat-by-default, same philosophy as web: `CardThemeData` sets `elevation: 0` everywhere and relies on a 1px border (Zinc Border in dark, Slate Border in light) for separation instead of shadow. `AppBarTheme` also sets `elevation: 0` in both themes. This is the one area where mobile and web are already in complete agreement without anyone having coordinated it, worth protecting as new screens are added.

### Named Rules
**The Floating-Only Rule (shared with web).** No resting shadows on cards, list tiles, or app bars. If a future component needs to look "elevated," reach for a border or a tonal surface shift, not a shadow.

## 5. Components

### Buttons
- **Shape:** 8px corner radius, full-width, 14px vertical padding, no horizontal padding constraint (buttons stretch to their container).
- **Primary:** `AppTheme.brandButton` (`#126E36`) fill with white text, deliberately the exact same hex as web's Seal Green Deep, passing WCAG AA at 6.3:1. `AppTheme.brand` (`#1FAD55`) stays reserved for accents/icons, matching web's split between the bright accent and the deep button-fill shade.
- **Disabled:** `brandButton` at 40% alpha.

### Status Badges (Chips)
- **Style:** 6px rounded rectangle (not a pill, unlike web's fully-rounded badge), 15%-opacity tinted background, 40%-opacity border in the same hue, full-opacity text.
- **Shape divergence from web:** web's equivalent badge is a full pill (`rounded-full`). Mobile's is a soft rectangle. Both are legitimate chip shapes; they're just not the same one.

### Cards
- **Corner Style:** 12px radius, matching web's `rounded-xl` exactly.
- **Background:** Zinc Panel.
- **Border:** 1px Zinc Border, no shadow.

### Inputs
- **Style:** filled with Zinc Panel, 8px radius, 1px Zinc Border.
- **Focus:** border shifts to Seal Green at 1.5px width, conceptually the same "green means focus" language as web, implemented as a border-weight change rather than web's border-color-plus-ring combination.
- **Error:** border shifts to plain Material red, not a token from the app's own palette.
- **Password visibility toggle:** implemented as a Material `IconButton`, which gets a 48×48 tap target for free from the framework, notably better than web's equivalent control before its own polish pass.

### Navigation
- App bars are flat (`elevation: 0`, theme-aware surface background and text color) consistent with the rest of the flat-by-default system. No bottom nav or drawer exists, screens are reached via a card grid on the Dashboard, grouped into "Overview," "Modules," and (as of this pass) "Preferences."

### Date Pickers
- `showDatePicker`'s theme override now reads `Theme.of(ctx).colorScheme.copyWith(primary: AppTheme.brand)` instead of a hardcoded `ColorScheme.dark(...)`. It inherits whichever theme is active and only overrides the accent color, so the calendar dialog is no longer stuck in dark styling when the app itself is in light mode.

### Settings Screen (new)
- Reached via a "Preferences" section card on the Dashboard (`Icons.settings_outlined`), not a profile menu. There's no existing account/profile screen to nest it in.
- **Appearance card**: a `SegmentedButton<ThemeMode>` (System / Light / Dark) and a `SegmentedButton<TextSizeOption>` (Small / Default / Large), both persisted via `shared_preferences` and applied instantly (no restart needed) since `MaterialApp.router` watches `settingsProvider` directly.
- **About card**: app name, version (via `package_info_plus`), and the same "San Jose Municipal Hall · Batangas · Republic of the Philippines" / "contact the ICT Administrator" footer language used on the login screen, for a consistent voice.

## 6. Do's and Don'ts

### Do:
- **Do** reuse Near-Black Zinc, Zinc Panel, Zinc Border, Paper White, and Slate Border exactly as coded via `context.colors`. They already match web's tokens, so any new mobile screen automatically stays cross-platform-consistent for neutrals in both themes.
- **Do** keep the flat, `elevation: 0` + border approach for every new card, list tile, or app bar. This is the one system already in silent agreement with web.
- **Do** use `context.colors.textSecondary`/`context.colors.textTertiary` for secondary/tertiary text; both pass contrast comfortably in either theme.
- **Do** give the password-visibility `IconButton` pattern (48×48 free tap target) as the reference when adding similar controls elsewhere, rather than copying web's smaller custom button.
- **Do** theme new dialogs (date pickers, bottom sheets, etc.) by reading `Theme.of(context)` and overriding only what's needed, not by hardcoding `ColorScheme.dark`/`ColorScheme.light`.

### Don't (flagged gaps, not settled style choices):
- **Don't** treat the lifecycle status color mapping as correct: Registered/Assigned/Transferred currently mean different colors on mobile than on web. A GSO staffer switching between apps will learn contradictory color associations. This needs a decision (pick one mapping, apply everywhere) before it's "the system," not two systems. **Still open.**
- ~~Don't keep shipping new primary buttons with Seal Green + white text~~, **Fixed.** `elevatedButtonTheme` now uses `AppTheme.brandButton` (`#126E36`, matching web exactly), passing AA at 6.3:1 in either theme.
- ~~Don't use Colors.white38 for real content~~, **Fixed.** Every raw `white38`/`white54` call site across the app (~20 files) now resolves through `context.colors.textSecondary`/`textTertiary`; the failing `white38` shade no longer exists anywhere in the codebase.
- ~~Don't reach for raw Colors.whiteXX values per call site~~, **Fixed and superseded.** Values were first centralized as static `AppTheme` constants, then upgraded again to a `ThemeExtension` (`context.colors.X`) so they can actually change with the theme. A static const, however centralized, still can't react to a runtime toggle.
- ~~Don't ship the app dark-only~~, **Fixed.** `AppTheme.light` now exists, mirrors web's light-mode tokens exactly, and is user-selectable (with System/Dark) from Settings.
- **Don't** treat "whatever Flutter gives you" as the mobile type system going forward. It's a gap inherited from not having set a `fontFamily` yet, not a considered "native feel" decision. Adding Inter via `google_fonts` would close the gap with web directly. **Still open.**
- **Don't** introduce a third badge shape. Mobile's 6px chip and web's full pill are already two; resolve to one before adding a third. **Still open.**
