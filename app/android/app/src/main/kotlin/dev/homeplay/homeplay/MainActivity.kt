package dev.homeplay.homeplay

import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.media.audiofx.DynamicsProcessing
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.util.Rational
import androidx.lifecycle.Lifecycle
import com.ryanheise.audioservice.AudioService
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// audio_service keeps the Flutter engine alive for background playback.
class MainActivity : AudioServiceActivity() {
    private var pip: MethodChannel? = null

    // Picture-in-picture when the user leaves the app: on while a video plays.
    private var autoPip = false
    private var pipRatio = Rational(16, 9)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Full screen in landscape the picture goes under the camera cutout too. By default Android
        // kept that strip black and the video sat beside it, its far edge cut off.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        if (showsWallpaper()) window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WALLPAPER)
    }

    // With the home screen wallpaper as the background, Flutter draws on a clear window and
    // Android puts the wallpaper under it. Only then: a clear window costs a little more to draw.
    override fun getBackgroundMode(): BackgroundMode =
        if (showsWallpaper()) BackgroundMode.transparent else BackgroundMode.opaque

    private fun windowPrefs() = getSharedPreferences("homeplay_window", Context.MODE_PRIVATE)

    private fun showsWallpaper() = windowPrefs().getBoolean("wallpaper", false)

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
                "keepControls" -> result.success(keepControls())
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "homeplay/window").setMethodCallHandler { call, result ->
            when (call.method) {
                // The drawing mode is fixed when the window is made, so a change makes it anew.
                // The Flutter engine lives on with audio_service: the app and playback go on.
                "showWallpaper" -> {
                    val show = call.arguments == true
                    result.success(null)
                    if (show != showsWallpaper()) {
                        windowPrefs().edit().putBoolean("wallpaper", show).commit()
                        recreate()
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "homeplay/eq").setMethodCallHandler { call, result ->
            when (call.method) {
                "session" -> result.success(audioSession())
                "apply" -> {
                    val enabled = call.argument<Boolean>("enabled") == true
                    val gains = call.argument<List<Double>>("gains") ?: emptyList()
                    val cutoffs = call.argument<List<Double>>("cutoffs") ?: emptyList()
                    result.success(applyEqualizer(enabled, gains, cutoffs))
                }
                else -> result.notImplemented()
            }
        }
        pip = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "homeplay/pip").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "available" -> result.success(pipAvailable())
                    "enter" -> {
                        ratio(call.argument<Int>("width"), call.argument<Int>("height"))
                        result.success(enterPip())
                    }
                    "setAuto" -> {
                        autoPip = call.argument<Boolean>("enabled") == true
                        ratio(call.argument<Int>("width"), call.argument<Int>("height"))
                        updateParams()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun pipAvailable() =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    // Android refuses shapes outside 1:2.39 .. 2.39:1.
    private fun ratio(width: Int?, height: Int?) {
        if (width == null || height == null || width <= 0 || height <= 0) return
        val r = width.toDouble() / height
        pipRatio = when {
            r > 2.39 -> Rational(239, 100)
            r < 1 / 2.39 -> Rational(100, 239)
            else -> Rational(width, height)
        }
    }

    private fun params(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val b = PictureInPictureParams.Builder().setAspectRatio(pipRatio)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            b.setAutoEnterEnabled(autoPip).setSeamlessResizeEnabled(false)
        }
        return b.build()
    }

    private fun updateParams() {
        if (!pipAvailable()) return
        try {
            setPictureInPictureParams(params()!!)
        } catch (e: IllegalStateException) {
            // Not allowed in the current state; the next update tries again.
        }
    }

    private fun enterPip(): Boolean {
        if (!pipAvailable()) return false
        return try {
            enterPictureInPictureMode(params()!!)
        } catch (e: IllegalStateException) {
            false
        }
    }

    // Android 12+ enters by itself (setAutoEnterEnabled); older versions are asked here.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPip && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enterPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pip?.invokeMethod("changed", isInPictureInPictureMode)
        // Leaving the small window with the activity stopped means it was closed, not
        // expanded back to full screen.
        if (!isInPictureInPictureMode && lifecycle.currentState == Lifecycle.State.CREATED) {
            pip?.invokeMethod("closed", null)
        }
    }

    // The player's audio session: mpv's AudioTrack joins it, and the equalizer works on it.
    private fun audioSession(): Int {
        if (session == 0) {
            session = (applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager).generateAudioSessionId()
        }
        return session
    }

    /**
     * Android's own equalizer on the player's session: [gains] in dB for bands ending at
     * [cutoffs] Hz, then a limiter that only catches the peaks the raised bands push over full
     * scale, so the sound keeps its level and does not crackle. False where it is not available
     * (before Android 9, or the effect refused); the player then uses its own filters.
     */
    private fun applyEqualizer(enabled: Boolean, gains: List<Double>, cutoffs: List<Double>): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || gains.isEmpty() || gains.size != cutoffs.size) return false
        return try {
            val d = dynamics?.takeIf { bands == gains.size } ?: run {
                dynamics?.release()
                val config = DynamicsProcessing.Config.Builder(
                    DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION, 2,
                    true, gains.size, false, 0, false, 0, true,
                ).setPreferredFrameDuration(10f).build()
                DynamicsProcessing(0, audioSession(), config).also {
                    dynamics = it
                    bands = gains.size
                }
            }
            for (i in gains.indices) {
                d.setPreEqBandAllChannelsTo(i, DynamicsProcessing.EqBand(true, cutoffs[i].toFloat(), gains[i].toFloat()))
            }
            // Attack 1 ms, release 60 ms, ratio 10:1 above -1 dBFS, no make-up gain.
            d.setLimiterAllChannelsTo(DynamicsProcessing.Limiter(true, true, 0, 1f, 60f, 10f, -1f, 0f))
            d.setEnabled(enabled)
            true
        } catch (e: Exception) {
            android.util.Log.w("homeplay", "equalizer: ${e.javaClass.simpleName}")
            dynamics?.release()
            dynamics = null
            false
        }
    }

    /**
     * audio_service forgets where to send the notification's and the headset's buttons when Android
     * destroys its service (AudioService.onDestroy clears its static listener), and only sets it
     * again for a new Flutter engine: after the service came back, Pause, Next and Stop in the
     * notification did nothing. Remembers the listener while it is set and puts it back when it
     * is gone. True when it had to be put back.
     */
    private fun keepControls(): Boolean = try {
        val field = AudioService::class.java.getDeclaredField("listener").apply { isAccessible = true }
        val current = field.get(null)
        when {
            current != null -> {
                controlsListener = current
                false
            }
            controlsListener != null -> {
                field.set(null, controlsListener)
                android.util.Log.i("homeplay", "media controls reconnected")
                true
            }
            else -> false
        }
    } catch (e: Exception) {
        android.util.Log.w("homeplay", "media controls check failed: ${e.javaClass.simpleName}")
        false
    }

    companion object {
        // NOTIFICATION_ID in audio_service's AudioService.java (0.18).
        const val AUDIO_SERVICE_NOTIFICATION_ID = 1124

        private var controlsListener: Any? = null

        // Outlive the activity: the music plays on in the service when it is closed.
        private var session = 0
        private var dynamics: DynamicsProcessing? = null
        private var bands = 0
    }
}
