package com.sanjose.san_jose_eam_mobile

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

// FLAG_SECURE blocks screenshots and screen recording system-wide for this
// activity, and blanks the app's thumbnail in the recent-apps switcher — asset
// data (property records, accountable persons, contact info) must not leave
// the device via a captured image, regardless of account role.
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        super.onCreate(savedInstanceState)
    }
}
