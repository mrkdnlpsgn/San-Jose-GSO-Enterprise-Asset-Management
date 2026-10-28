package com.sanjose.san_jose_eam_mobile

import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FLAG_SECURE blocks screenshots and screen recording system-wide for this
// activity, and blanks the app's thumbnail in the recent-apps switcher - asset
// data (property records, accountable persons, contact info) must not leave
// the device via a captured image, regardless of account role.
// TEMPORARY: screenshot blocking disabled. Set to true to re-enable.
private const val SCREENSHOT_PROTECTION_ENABLED = false

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        if (SCREENSHOT_PROTECTION_ENABLED) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        }
        super.onCreate(savedInstanceState)
    }

    // "sjgso/sound" playNotification: the phone's own notification sound, for the app's
    // in-app notification ping (lib/core/platform/notification_sound.dart). Played as a
    // notification, so it follows the phone's notification volume and silent mode.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sjgso/sound").setMethodCallHandler { call, result ->
            if (call.method != "playNotification") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                val ringtone = uri?.let { RingtoneManager.getRingtone(applicationContext, it) }
                ringtone?.audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                ringtone?.play()
                result.success(ringtone != null)
            } catch (e: Exception) {
                result.success(false)
            }
        }
    }
}
