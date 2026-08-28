package uk.jentejan.chudder

import android.graphics.PixelFormat
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.annotation.OptIn
import androidx.annotation.RequiresApi
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.media3.common.util.UnstableApi
import uk.jentejan.chudder.composables.controls.CustomVideoControls
import uk.jentejan.chudder.composables.overlays.screensavers.ScreenSaver
import uk.jentejan.chudder.objects.VideoPlayerObject
import uk.jentejan.chudder.player.ExoPlayer
import uk.jentejan.chudder.utility.ScaledContent
import uk.jentejan.chudder.utility.leanBackEnabled

class VideoPlayerActivity : ComponentActivity() {
    @RequiresApi(Build.VERSION_CODES.O)
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        VideoPlayerObject.currentActivity = this

        window.setFlags(
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
        )

        window.setFormat(PixelFormat.TRANSLUCENT)

        setContent {
            VideoPlayerTheme {
                VideoPlayerScreen()
            }
        }
    }

    override fun onPause() {
        super.onPause()
        VideoPlayerObject.implementation.pause()
    }
}

@OptIn(UnstableApi::class)
@Composable
fun VideoPlayerScreen(
) {
    val leanBackEnabled = leanBackEnabled(LocalContext.current)
    ScreenSaver {
        ExoPlayer { player ->
            ScaledContent(
                scale = if (leanBackEnabled) 0.75f else 1f,
                fontScale = if (leanBackEnabled) 1.2f else 1f,
            ) {
                CustomVideoControls(player)
            }
        }
    }
}
