package uk.jentejan.chudder

import BatteryOptimizationPigeon
import FlutterError
import NativeVideoActivity
import PlayerSettingsPigeon
import StartResult
import TranslationsPigeon
import VideoPlayerApi
import VideoPlayerControlsCallback
import VideoPlayerListenerCallback
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.net.Uri
import android.util.Log
import android.provider.Settings
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.google.android.gms.cast.Cast
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import uk.jentejan.chudder.objects.PlayerSettingsObject
import uk.jentejan.chudder.objects.TranslationsMessenger
import uk.jentejan.chudder.objects.VideoPlayerObject
import uk.jentejan.chudder.utility.leanBackEnabled
import androidx.core.net.toUri
import uk.jentejan.chudder.wallpaper.WallpaperApi
import uk.jentejan.chudder.wallpaper.WallpaperApiUtility
import java.io.File
import java.util.Objects

class WallpaperFileProvider : FileProvider()

class MainActivity : AudioServiceFragmentActivity(), NativeVideoActivity {
    private lateinit var videoPlayerLauncher: ActivityResultLauncher<Intent>
    private var videoPlayerCallback: ((Result<StartResult>) -> Unit)? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var castChannel: MethodChannel? = null
    private var localNetworkPermissionResult: MethodChannel.Result? = null

    // PiP window controls. The pip plugin only manages aspect ratio and
    // auto-enter; the RemoteActions (play/pause, next episode) are layered on
    // here. Dart pushes {hasNext, playing} through the channel, taps come back
    // as "action" invocations.
    private var pipActionsChannel: MethodChannel? = null
    private var pipHasNext = false
    private var pipPlaying = false
    private var pipActionReceiver: BroadcastReceiver? = null

    private fun updatePipActions() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            // Mirrors the floating player's transport (play/pause, next,
            // close) with the app's own Material icons instead of the dated
            // holo ic_media_* set. Expand is the PiP window's built-in.
            val actions = mutableListOf<RemoteAction>()
            actions += pipRemoteAction(
                if (pipPlaying) R.drawable.ic_pip_pause else R.drawable.ic_pip_play,
                if (pipPlaying) "Pause" else "Play",
                PIP_ACTION_PLAY_PAUSE
            )
            if (pipHasNext) {
                actions += pipRemoteAction(R.drawable.ic_pip_next, "Next episode", PIP_ACTION_NEXT)
            }
            actions += pipRemoteAction(R.drawable.ic_pip_stop, "Stop", PIP_ACTION_STOP)
            // Builder fields left unset keep whatever the pip plugin already
            // applied (aspect ratio, auto-enter) — only the actions change.
            setPictureInPictureParams(PictureInPictureParams.Builder().setActions(actions).build())
        } catch (e: Exception) {
            Log.w("FladderPip", "failed to set PiP actions: ${e.message}")
        }
    }

    private fun pipRemoteAction(iconRes: Int, title: String, requestCode: Int): RemoteAction {
        val pendingIntent = PendingIntent.getBroadcast(
            this, requestCode,
            Intent(PIP_ACTION_INTENT).setPackage(packageName).putExtra(PIP_ACTION_EXTRA, requestCode),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return RemoteAction(Icon.createWithResource(this, iconRes), title, title, pendingIntent)
    }

    private fun registerPipActionReceiver() {
        if (pipActionReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = when (intent?.getIntExtra(PIP_ACTION_EXTRA, -1)) {
                    PIP_ACTION_PLAY_PAUSE -> "playPause"
                    PIP_ACTION_NEXT -> "next"
                    PIP_ACTION_STOP -> "stop"
                    else -> return
                }
                runOnUiThread { pipActionsChannel?.invokeMethod("action", action) }
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, IntentFilter(PIP_ACTION_INTENT), Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, IntentFilter(PIP_ACTION_INTENT))
        }
        pipActionReceiver = receiver
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (isInPictureInPictureMode) {
            registerPipActionReceiver()
            updatePipActions()
        } else {
            pipActionReceiver?.let {
                try {
                    unregisterReceiver(it)
                } catch (_: Exception) {
                }
            }
            pipActionReceiver = null
        }
    }

    // Granular Cast session lifecycle relay (mirrors the official jellyfin-android
    // ChromecastConnection): the SDK's callbacks are the single source of truth
    // for connection state on the Dart side. Registered once via
    // `startSessionMonitoring` (the CastContext must already be initialized by
    // flutter_chrome_cast before the session manager exists).
    private var castSessionListener: SessionManagerListener<CastSession>? = null

    // The custom namespace Dart asked for, so message callbacks can be
    // re-attached whenever the session (re)connects — a resumed session drops
    // previously registered callbacks (same pattern as ChromecastSession.setSession).
    private var castNamespace: String? = null

    private fun attachCastNamespace(session: CastSession) {
        val namespace = castNamespace ?: return
        try {
            session.setMessageReceivedCallbacks(
                namespace,
                Cast.MessageReceivedCallback { _, ns, message ->
                    Log.d("FladderCast", "received on $ns: $message")
                    runOnUiThread {
                        castChannel?.invokeMethod(
                            "onCastMessage",
                            mapOf("namespace" to ns, "message" to message)
                        )
                    }
                }
            )
            Log.d("FladderCast", "namespace $namespace attached to session")
        } catch (e: Exception) {
            Log.w("FladderCast", "failed to attach namespace: ${e.message}")
        }
    }

    private fun sendCastSessionEvent(event: String, detail: Any? = null) {
        Log.d("FladderCast", "session event: $event ($detail)")
        runOnUiThread {
            castChannel?.invokeMethod("onSessionEvent", mapOf("event" to event, "detail" to detail))
        }
    }

    private fun startCastSessionMonitoring() {
        if (castSessionListener != null) return
        val listener = object : SessionManagerListener<CastSession> {
            override fun onSessionStarting(session: CastSession) {}
            override fun onSessionStarted(session: CastSession, sessionId: String) {
                attachCastNamespace(session)
                sendCastSessionEvent("started")
            }

            override fun onSessionStartFailed(session: CastSession, error: Int) =
                sendCastSessionEvent("startFailed", error)

            override fun onSessionEnding(session: CastSession) {}
            override fun onSessionEnded(session: CastSession, error: Int) =
                sendCastSessionEvent("ended", error)

            override fun onSessionResuming(session: CastSession, sessionId: String) {}
            override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
                attachCastNamespace(session)
                sendCastSessionEvent("resumed", wasSuspended)
            }

            override fun onSessionResumeFailed(session: CastSession, error: Int) =
                sendCastSessionEvent("resumeFailed", error)

            override fun onSessionSuspended(session: CastSession, reason: Int) =
                sendCastSessionEvent("suspended", reason)
        }
        CastContext.getSharedInstance(applicationContext).sessionManager
            .addSessionManagerListener(listener, CastSession::class.java)
        castSessionListener = listener
        Log.d("FladderCast", "session monitoring started")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Custom-namespace messaging over the active Cast session, so we can talk
        // to the Jellyfin Cast receiver (which uses its own protocol rather than
        // the default media receiver). Uses the same CastContext singleton that
        // flutter_chrome_cast manages, so `currentCastSession` is the live session.
        castChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "uk.jentejan.chudder/cast")
        castChannel!!.setMethodCallHandler { call, result ->
            val session = try {
                CastContext.getSharedInstance(applicationContext).sessionManager.currentCastSession
            } catch (e: Exception) {
                null
            }
            when (call.method) {
                "sendMessage" -> {
                    val namespace = call.argument<String>("namespace")
                    val message = call.argument<String>("message")
                    if (session == null || namespace == null || message == null) {
                        Log.w("FladderCast", "sendMessage: no session (${session != null})")
                        result.error("NO_SESSION", "No active cast session", null)
                    } else {
                        session.sendMessage(namespace, message).setResultCallback { status ->
                            Log.d("FladderCast", "sendMessage success=${status.isSuccess} ${status.statusMessage ?: ""}")
                            if (status.isSuccess) result.success(true)
                            else result.error("SEND_FAILED", status.statusMessage, null)
                        }
                    }
                }
                "registerNamespace" -> {
                    val namespace = call.argument<String>("namespace")
                    if (session == null || namespace == null) {
                        Log.w("FladderCast", "registerNamespace: no session")
                        result.error("NO_SESSION", "No active cast session", null)
                    } else {
                        Log.d("FladderCast", "registerNamespace $namespace on session")
                        castNamespace = namespace
                        attachCastNamespace(session)
                        result.success(true)
                    }
                }
                "startSessionMonitoring" -> {
                    try {
                        startCastSessionMonitoring()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MONITOR_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        pipActionsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "uk.jentejan.chudder/pip_actions")
        pipActionsChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateState" -> {
                    pipHasNext = call.argument<Boolean>("hasNext") ?: false
                    pipPlaying = call.argument<Boolean>("playing") ?: false
                    // Applying before PiP is entered is fine — the params are
                    // remembered and used the moment the window appears.
                    updatePipActions()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Multicast lock so Chromecast (mDNS) discovery can receive responses over Wi-Fi.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "uk.jentejan.chudder/multicast")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        try {
                            if (multicastLock == null) {
                                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                                multicastLock = wifi.createMulticastLock("fladder-cast").apply {
                                    setReferenceCounted(false)
                                }
                            }
                            multicastLock?.acquire()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("MULTICAST_LOCK", e.message, null)
                        }
                    }
                    "release" -> {
                        try {
                            if (multicastLock?.isHeld == true) multicastLock?.release()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("MULTICAST_LOCK", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Local-network access gate. Android 17 (targetSdk 37+) puts raw
        // local-network sockets behind a runtime permission; until it's granted
        // both mDNS (Chromecast) and SSDP (DLNA) discovery come back empty
        // instead of throwing, so the app has to ask before scanning.
        // permission_handler has no binding for this permission yet, hence the
        // channel.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "uk.jentejan.chudder/local_network")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "required" -> result.success(localNetworkPermissionRequired())
                    "granted" -> result.success(hasLocalNetworkPermission())
                    "request" -> requestLocalNetworkPermission(result)
                    else -> result.notImplemented()
                }
            }

        val videoPlayerHost = VideoPlayerObject
        NativeVideoActivity.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            this
        )
        WallpaperApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            WallpaperApiUtility(this, wallpaperLauncher)
        )
        VideoPlayerApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            videoPlayerHost.implementation
        )
        videoPlayerHost.videoPlayerListener =
            VideoPlayerListenerCallback(flutterEngine.dartExecutor.binaryMessenger)

        videoPlayerHost.videoPlayerControls =
            VideoPlayerControlsCallback(flutterEngine.dartExecutor.binaryMessenger)

        TranslationsMessenger.translation =
            TranslationsPigeon(flutterEngine.dartExecutor.binaryMessenger)

        PlayerSettingsPigeon.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            api = PlayerSettingsObject
        )

        BatteryOptimizationPigeon.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            api = object : BatteryOptimizationPigeon {
                override fun isIgnoringBatteryOptimizations(): Boolean {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    return pm.isIgnoringBatteryOptimizations(packageName)
                }

                override fun openBatteryOptimizationSettings() {
                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                }
            }
        )

        videoPlayerLauncher = registerForActivityResult(
            ActivityResultContracts.StartActivityForResult()
        ) { result ->
            val callback = videoPlayerCallback
            videoPlayerCallback = null

            val startResult = if (result.resultCode == RESULT_OK) {
                StartResult(resultValue = result.data?.getStringExtra("result") ?: "Finished")
            } else {
                StartResult(resultValue = "Cancelled")
            }

            VideoPlayerObject.implementation.player?.stop()
            VideoPlayerObject.implementation.player?.release()
            callback?.invoke(Result.success(startResult))
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Ensure the Activity's intent is updated so Flutter (and plugins / AutoRoute) receive runtime deep-links.
        setIntent(intent)
    }

    private val wallpaperLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        // Handle the result of the wallpaper intent if needed
    }

    // Registered as a property initializer (like wallpaperLauncher) so it's in
    // place before the Activity reaches STARTED, which registerForActivityResult
    // requires.
    private val localNetworkPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        localNetworkPermissionResult?.success(granted)
        localNetworkPermissionResult = null
    }

    /** Whether this device+build actually enforces [ACCESS_LOCAL_NETWORK]. */
    private fun localNetworkPermissionRequired(): Boolean =
        Build.VERSION.SDK_INT >= LOCAL_NETWORK_SDK &&
            applicationInfo.targetSdkVersion >= LOCAL_NETWORK_SDK

    private fun hasLocalNetworkPermission(): Boolean =
        !localNetworkPermissionRequired() ||
            ContextCompat.checkSelfPermission(this, ACCESS_LOCAL_NETWORK) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestLocalNetworkPermission(result: MethodChannel.Result) {
        if (hasLocalNetworkPermission()) {
            result.success(true)
            return
        }
        // A second request while the system dialog is still up would drop the
        // first Result without a reply and hang that Dart future.
        if (localNetworkPermissionResult != null) {
            result.error("IN_PROGRESS", "A local network permission request is already in flight", null)
            return
        }
        localNetworkPermissionResult = result
        localNetworkPermissionLauncher.launch(ACCESS_LOCAL_NETWORK)
    }

    private companion object {
        // Android 17. Not in Manifest.permission until compileSdk 37, so it's
        // spelled out rather than referenced.
        const val ACCESS_LOCAL_NETWORK = "android.permission.ACCESS_LOCAL_NETWORK"
        const val LOCAL_NETWORK_SDK = 37

        const val PIP_ACTION_INTENT = "uk.jentejan.chudder.PIP_ACTION"
        const val PIP_ACTION_EXTRA = "pip_action"
        const val PIP_ACTION_PLAY_PAUSE = 1
        const val PIP_ACTION_NEXT = 2
        const val PIP_ACTION_STOP = 3
    }

    override fun launchActivity(callback: (Result<StartResult>) -> Unit) {
        try {
            videoPlayerCallback = callback
            val intent = Intent(this, VideoPlayerActivity::class.java)
            videoPlayerLauncher.launch(intent)
        } catch (e: Exception) {
            e.printStackTrace()
            callback(Result.failure(e))
        }
    }

    override fun disposeActivity() {
        VideoPlayerObject.implementation.player?.stop()
        VideoPlayerObject.implementation.player?.release()
        VideoPlayerObject.currentActivity?.finish()
    }

    override fun isLeanBackEnabled(): Boolean = leanBackEnabled(applicationContext)
}
