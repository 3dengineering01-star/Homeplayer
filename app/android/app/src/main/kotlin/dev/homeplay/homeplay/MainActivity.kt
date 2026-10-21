package dev.homeplay.homeplay

import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import android.service.media.MediaBrowserService
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.media.audiofx.DynamicsProcessing
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import android.util.Log
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
    private var links: MethodChannel? = null
    private var playback: MethodChannel? = null

    // The link the app was opened with, handed to Flutter once.
    private var startLink: String? = null

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
        applyWallpaper(showsWallpaper())
        if (savedInstanceState == null) startLink = linkOf(intent)
    }

    // A keyboard's or a remote's own Pause and Play keys while the app is on screen. Left to the
    // media session they became audio_service's play/pause toggle: Pause started music that was
    // paused (also the queue kept from the last run). A headset's single button still toggles.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val command = when (event.keyCode) {
            KeyEvent.KEYCODE_MEDIA_PAUSE -> "pause"
            KeyEvent.KEYCODE_MEDIA_PLAY -> "play"
            else -> null
        }
        val channel = playback
        if (command == null || channel == null) return super.dispatchKeyEvent(event)
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) channel.invokeMethod(command, null)
        return true
    }

    private fun linkOf(intent: Intent?): String? =
        if (intent?.action == Intent.ACTION_VIEW) intent.dataString else null

    // Already open (singleTop): the link comes here and goes straight to Flutter.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        linkOf(intent)?.let { links?.invokeMethod("open", it) }
    }

    override fun onResume() {
        super.onResume()
        applyWallpaper(showsWallpaper())
    }

    // Flutter always draws on a clear window, so the home screen wallpaper can show under it.
    // A window made clear only when the wallpaper was chosen stayed opaque if the app had
    // started without it: the Flutter engine lives on from window to window and kept drawing
    // the opaque way.
    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    // The wallpaper shows or not by a window flag alone; when it is off, the app paints its
    // own background over the whole window.
    private fun applyWallpaper(show: Boolean) {
        val flag = WindowManager.LayoutParams.FLAG_SHOW_WALLPAPER
        if (show) window.addFlags(flag) else window.clearFlags(flag)
        Log.i("homeplay", "window: wallpaper=$show")
    }

    private fun windowPrefs() = getSharedPreferences("homeplay_window", Context.MODE_PRIVATE)

    private fun showsWallpaper() = windowPrefs().getBoolean("wallpaper", false)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        holdAudioService(applicationContext)
        playback = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "homeplay/playback")
        playback!!.setMethodCallHandler { call, result ->
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
        links = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "homeplay/links").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        result.success(startLink)
                        startLink = null
                    }
                    // Android's share sheet: messengers, mail, copy.
                    "share" -> {
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, call.argument<String>("text"))
                        }
                        startActivity(Intent.createChooser(send, call.argument<String>("title")))
                        result.success(null)
                    }
                    // A web address in the browser (the new version of the app to download).
                    "view" -> {
                        val open = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(call.arguments as String))
                        result.success(
                            try {
                                startActivity(open)
                                true
                            } catch (e: android.content.ActivityNotFoundException) {
                                false
                            }
                        )
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "homeplay/window").setMethodCallHandler { call, result ->
            when (call.method) {
                "showWallpaper" -> {
                    val show = call.arguments == true
                    windowPrefs().edit().putBoolean("wallpaper", show).apply()
                    applyWallpaper(show)
                    result.success(null)
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

        private var serviceHold: ServiceConnection? = null

        /**
         * Keeps audio_service's service alive for as long as the app's process lives.
         *
         * Paused music leaves the foreground, and about a minute after the app's screen is
         * closed Android stops such an idle service. A frozen app does it once it thaws, often
         * when the notification shade opens or one of its buttons is pressed: the notification
         * went away under the finger and the press was lost. The service's end also made
         * audio_service destroy the Flutter engine while mpv lived on; the next start of the app
         * then crashed ("Callback invoked after it has been deleted").
         *
         * Bound from the app itself, the service stays. It does not keep the process awake:
         * Android still freezes it while paused, and thaws it for a press in the notification.
         */
        private fun holdAudioService(context: Context) {
            if (serviceHold != null) return
            val hold = object : ServiceConnection {
                override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {}
                override fun onServiceDisconnected(name: ComponentName?) {}
            }
            // The media browser action: for any other intent the service has no binder to give.
            val intent = Intent(MediaBrowserService.SERVICE_INTERFACE).setClass(context, AudioService::class.java)
            try {
                if (context.bindService(intent, hold, Context.BIND_AUTO_CREATE)) serviceHold = hold
            } catch (e: Exception) {
                Log.w("homeplay", "audio service not held: ${e.javaClass.simpleName}")
            }
        }

        // Outlive the activity: the music plays on in the service when it is closed.
        private var session = 0
        private var dynamics: DynamicsProcessing? = null
        private var bands = 0
    }
}
