import 'package:flutter/widgets.dart';

/// The app's top navigator, so prompts that don't belong to one screen (the emailed-code
/// dialog the API client opens) can be shown over whatever screen is up.
final rootNavigatorKey = GlobalKey<NavigatorState>();
