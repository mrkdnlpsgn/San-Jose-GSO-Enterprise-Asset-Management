import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which list a notification points into.
enum HighlightTarget { assets, requests, accounts }

/// The records a notification is about, set when it's opened (NotificationsScreen) so the
/// screen it opens can tint them and list them first, until cleared or replaced.
/// [ids] are what that screen keys its rows by: asset ids, "KIND-recordId" requests, user ids.
class Highlight {
  final HighlightTarget target;
  final Set<String> ids;
  final String title;
  const Highlight(this.target, this.ids, this.title);

  bool has(Object? id) => id != null && ids.contains('$id');
}

final highlightProvider = StateProvider<Highlight?>((ref) => null);

/// The current highlight if it is for [target].
Highlight? highlightFor(WidgetRef ref, HighlightTarget target) {
  final h = ref.watch(highlightProvider);
  return h != null && h.target == target ? h : null;
}

/// [items] with the highlighted ones first, otherwise in the same order.
List<T> highlightedFirst<T>(List<T> items, Highlight? h, Object? Function(T) idOf) {
  if (h == null) return items;
  final hit = <T>[];
  final rest = <T>[];
  for (final x in items) {
    (h.has(idOf(x)) ? hit : rest).add(x);
  }
  return hit.isEmpty ? items : [...hit, ...rest];
}
