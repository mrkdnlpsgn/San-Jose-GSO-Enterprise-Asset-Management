import 'package:flutter/services.dart';

/// Plays the phone's own notification sound (Android, see MainActivity.kt). It follows the
/// phone's notification volume and silent mode. Does nothing where it isn't available
/// (iOS, desktop, tests), so callers never need to care.
class NotificationSound {
  static const _channel = MethodChannel('sjgso/sound');

  static Future<void> play() async {
    try {
      await _channel.invokeMethod<bool>('playNotification');
    } on MissingPluginException {
      // not on this platform
    } on PlatformException {
      // the phone couldn't play it; the banner and the bell still show the notification
    }
  }
}
