import 'dart:async';
import 'package:flutter/widgets.dart';

/// Wraps a screen body and periodically calls [onTick] — for silently
/// polling fresh data in the background instead of requiring a manual pull-
/// to-refresh. Pauses while the app itself is backgrounded (no point paying
/// for network requests nobody can see) and immediately ticks once on
/// returning to the foreground, so data doesn't look stale coming back.
class AutoRefreshTicker extends StatefulWidget {
  final Duration interval;
  final VoidCallback onTick;
  final Widget child;

  const AutoRefreshTicker({
    super.key,
    required this.interval,
    required this.onTick,
    required this.child,
  });

  @override
  State<AutoRefreshTicker> createState() => _AutoRefreshTickerState();
}

class _AutoRefreshTickerState extends State<AutoRefreshTicker> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) => widget.onTick());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.onTick();
      _startTimer();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
