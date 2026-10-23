# 016 - Confirm a successful report export, not just a failed one

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: LOW
- **Category**: Missed opportunity
- **Estimated scope**: 1 file (`mobile_sj/lib/features/reports/screens/report_preview_screen.dart`)

## Problem

```dart
// mobile_sj/lib/features/reports/screens/report_preview_screen.dart:25-40 - current
Future<void> _export(Future<void> Function() action) async {
  setState(() => _exporting = true);
  try {
    await action();
  } catch (e) {
    debugPrint('Report export failed: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Export failed. Please try again.'),
        backgroundColor: Colors.red.shade800,
      ));
    }
  } finally {
    if (mounted) setState(() => _exporting = false);
  }
}
```

Failure shows a `SnackBar`; success shows nothing beyond the button/spinner reverting to its resting state. A successful PDF/Excel export. A rare, "did this actually work?" moment (the file may have been saved to a downloads folder or shared via a share sheet the user might dismiss without reading), gives no explicit confirmation.

## Target

```dart
// target
Future<void> _export(Future<void> Function() action) async {
  setState(() => _exporting = true);
  try {
    await action();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Export ready.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  } catch (e) {
    debugPrint('Report export failed: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Export failed. Please try again.'),
        backgroundColor: Colors.red.shade800,
      ));
    }
  } finally {
    if (mounted) setState(() => _exporting = false);
  }
}
```

The success `SnackBar` deliberately omits `backgroundColor` (uses the theme default) to visually read as neutral/positive, distinct from the red error variant, matching this app's general convention of only tinting `SnackBar`s red for errors (check a couple of other `ScaffoldMessenger.of(context).showSnackBar` call sites elsewhere in the app, e.g. `mobile_sj/lib/features/settings/screens/change_password_screen.dart`, to confirm this convention before finalizing wording/styling).

## Repo conventions to follow

- Confirm the exact success-snackbar wording convention used elsewhere in the app (e.g. `change_password_screen.dart`'s `'Password updated successfully.'` with `behavior: SnackBarBehavior.floating` and no custom `backgroundColor`) and match that style/tone rather than inventing new phrasing patterns.

## Steps

1. In `mobile_sj/lib/features/reports/screens/report_preview_screen.dart`, locate the `_export` method (around lines 25-40).
2. Add a success `ScaffoldMessenger.of(context).showSnackBar(...)` call immediately after `await action();` succeeds (inside the `try` block, after the awaited call, before the `catch`), using the exact wording/styling convention confirmed in the Repo Conventions step above.

## Boundaries

- Do NOT change the export action functions themselves (`export_excel.dart`/`export_pdf.dart`) or the `_exporting` loading-state logic. Only add the one success snackbar.
- Do NOT add a haptic or sound to this. A report export is a background/administrative action, not a high-emotion moment; a `SnackBar` alone is proportionate per AUDIT's utility principle.

## Verification

- **Mechanical**: `flutter analyze` (from `mobile_sj/`), clean.
- **Feel check**: export a report as both PDF and Excel (whichever formats this screen supports) and confirm a "Export ready" (or whatever wording matches the codebase convention) snackbar appears on success, styled consistently with other success snackbars elsewhere in the app; confirm the existing failure path (e.g. simulate an error) still shows the red error snackbar unchanged.
- **Done when**: a successful export shows an explicit, styled-consistent confirmation, matching the app's existing success-snackbar convention.
