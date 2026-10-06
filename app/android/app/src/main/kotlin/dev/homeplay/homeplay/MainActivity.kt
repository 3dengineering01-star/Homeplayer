package dev.homeplay.homeplay

import android.app.NotificationManager
import android.content.Context
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// audio_service keeps the Flutter engine alive for background playback.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "homeplay/playback").setMethodCallHandler { call, result ->
            when (call.method) {
                // audio_service's own cancel comes right after it detaches the notification
                // from the service, and Android may drop it then: the notification stayed after
                // Stop. Playback asks again once things have settled.
                "cancelNotification" -> {
                    val notifications = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notifications.cancel(AUDIO_SERVICE_NOTIFICATION_ID)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        // NOTIFICATION_ID in audio_service's AudioService.java (0.18).
        const val AUDIO_SERVICE_NOTIFICATION_ID = 1124
    }
}
