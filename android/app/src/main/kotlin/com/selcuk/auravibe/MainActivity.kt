package com.selcuk.auravibe

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity

/**
 * Extends [AudioServiceActivity] rather than `FlutterActivity`: audio_service needs to own the
 * Flutter engine so its foreground service can keep running the same isolate after the activity
 * is backgrounded or destroyed. A plain FlutterActivity tears the engine down with itself, which
 * is exactly the case background playback has to survive.
 */
class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermissionIfNeeded()
    }

    /**
     * From Android 13 the playback notification is only shown if POST_NOTIFICATIONS was granted.
     * The foreground service itself starts either way, so a refusal costs the lock-screen and
     * notification controls, not background playback — which is why this asks once and never
     * insists.
     */
    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    private companion object {
        const val NOTIFICATION_PERMISSION_REQUEST = 1001
    }
}
