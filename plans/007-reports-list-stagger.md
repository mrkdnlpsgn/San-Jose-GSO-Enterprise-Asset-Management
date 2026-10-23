# 007 - Add the missing entrance stagger to the Reports list

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: MEDIUM
- **Category**: Cohesion & tokens
- **Estimated scope**: 1 file (`mobile_sj/lib/features/reports/screens/reports_list_screen.dart`)

## Problem

Every other list screen in the app (Assets, Maintenance, Disposal, Accounts) goes through `PaginatedListView`, which wraps each row in `StaggeredEntrance` (`mobile_sj/lib/shared/widgets/paginated_list_view.dart:118-119`). Reports is a plain, static list (no pagination. It's a fixed list of report definitions) built directly with no stagger at all:

```dart
// mobile_sj/lib/features/reports/screens/reports_list_screen.dart:1-28 - current (full relevant excerpt)
class ReportsListScreen extends ConsumerWidget {
  const ReportsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(reportDefinitionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _ReportCard(
          report: reports[i],
          onTap: () => context.push('/reports/${reports[i].id}'),
        ),
      ),
    );
  }
}
```

All the report cards pop in at once, while switching from Assets/Maintenance/Disposal (which cascade in) feels inconsistent.

## Target

```dart
// target
itemBuilder: (context, i) => StaggeredEntrance(
  index: i,
  child: _ReportCard(
    report: reports[i],
    onTap: () => context.push('/reports/${reports[i].id}'),
  ),
),
```

## Repo conventions to follow

- `StaggeredEntrance` (`mobile_sj/lib/shared/widgets/staggered_entrance.dart`) takes `index` and `child`, exactly this shape is already used identically in `mobile_sj/lib/shared/widgets/paginated_list_view.dart:119` (`StaggeredEntrance(index: i, child: item)`), the exemplar to copy.
- Since `reports` is a static, fixed-length list (not paginated/refreshable. It comes from `reportDefinitionsProvider`, a plain provider, not a `PaginatedListNotifier`), there is no refresh/search-replay concern here like `paginated_list_view.dart` had to solve earlier this session. A plain per-`i` `StaggeredEntrance` with no "seen count" gating is correct and sufficient, since this screen's list never changes shape after first build.

## Steps

1. Add the import: `import '../../../shared/widgets/staggered_entrance.dart';` to `mobile_sj/lib/features/reports/screens/reports_list_screen.dart`.
2. Wrap the `_ReportCard(...)` returned from `itemBuilder` in `StaggeredEntrance(index: i, child: ...)` exactly as shown in Target.

## Boundaries

- Do NOT touch `_ReportCard`'s own implementation, `report_preview_screen.dart`, or `reports_provider.dart`.
- Do NOT add refresh/pagination logic to this screen. It's intentionally a static list; this plan is animation-only.

## Verification

- **Mechanical**: `flutter analyze` (from `mobile_sj/`), clean.
- **Feel check**: open the Reports tab/screen and confirm the report cards cascade in with a slight stagger (each ~25ms after the previous, capped at index 10 per `staggered_entrance.dart:22`), matching the entrance feel already present on the Assets/Maintenance/Disposal list screens.
- **Done when**: `ReportsListScreen`'s cards visibly cascade in on first view, using the existing `StaggeredEntrance` widget with no new animation code.
