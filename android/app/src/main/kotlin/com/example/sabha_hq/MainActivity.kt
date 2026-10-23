package com.example.sabha_hq

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createCheckInChannel()
    }

    // Check-in push notifications (functions/src/notifications.ts) are sent
    // to this channel. Without it, Android 8+ files them under a generic
    // "Miscellaneous" channel at default importance — no heads-up banner,
    // and nothing meaningful for an admin to find in system settings if
    // they want to mute check-ins specifically. IMPORTANCE_HIGH is what
    // makes them pop up over whatever the admin is doing. Re-creating an
    // existing channel is a no-op, so this is safe on every launch.
    private fun createCheckInChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHECK_IN_CHANNEL_ID,
            "Check-ins",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "A notification every time someone checks in to one of your events"
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        // Must match ANDROID_CHANNEL_ID in functions/src/notifications.ts and
        // the default_notification_channel_id meta-data in AndroidManifest.xml.
        const val CHECK_IN_CHANNEL_ID = "check_ins"
    }
}
