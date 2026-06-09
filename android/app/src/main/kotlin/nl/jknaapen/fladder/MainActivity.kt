package nl.jknaapen.fladder

import BatteryOptimizationPigeon
import NativeVideoActivity
import PlayerSettingsPigeon
import StartResult
import TranslationsPigeon
import VideoPlayerApi
import VideoPlayerControlsCallback
import VideoPlayerListenerCallback
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.PowerManager
import android.net.Uri
import android.util.Log
import android.provider.Settings
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import com.google.android.gms.cast.Cast
import com.google.android.gms.cast.framework.CastContext
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import nl.jknaapen.fladder.objects.PlayerSettingsObject
import nl.jknaapen.fladder.objects.TranslationsMessenger
import nl.jknaapen.fladder.objects.VideoPlayerObject
import nl.jknaapen.fladder.utility.leanBackEnabled
import androidx.core.net.toUri

class MainActivity : AudioServiceFragmentActivity(), NativeVideoActivity {
    private lateinit var videoPlayerLauncher: ActivityResultLauncher<Intent>
    private var videoPlayerCallback: ((Result<StartResult>) -> Unit)? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var castChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Custom-namespace messaging over the active Cast session, so we can talk
        // to the Jellyfin Cast receiver (which uses its own protocol rather than
        // the default media receiver). Uses the same CastContext singleton that
        // flutter_chrome_cast manages, so `currentCastSession` is the live session.
        castChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nl.jknaapen.fladder/cast")
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
                        result.error("NO_SESSION", "No active cast session", null)
                    } else {
                        session.sendMessage(namespace, message).setResultCallback { status ->
                            if (status.isSuccess) result.success(true)
                            else result.error("SEND_FAILED", status.statusMessage, null)
                        }
                    }
                }
                "registerNamespace" -> {
                    val namespace = call.argument<String>("namespace")
                    if (session == null || namespace == null) {
                        result.error("NO_SESSION", "No active cast session", null)
                    } else {
                        try {
                            session.setMessageReceivedCallbacks(
                                namespace,
                                Cast.MessageReceivedCallback { _, ns, message ->
                                    runOnUiThread {
                                        castChannel?.invokeMethod(
                                            "onCastMessage",
                                            mapOf("namespace" to ns, "message" to message)
                                        )
                                    }
                                }
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("REGISTER_FAILED", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Multicast lock so Chromecast (mDNS) discovery can receive responses over Wi-Fi.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nl.jknaapen.fladder/multicast")
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

        val videoPlayerHost = VideoPlayerObject
        NativeVideoActivity.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            this
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
