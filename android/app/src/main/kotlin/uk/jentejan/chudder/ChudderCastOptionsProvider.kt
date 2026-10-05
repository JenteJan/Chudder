package uk.jentejan.chudder

import android.content.Context
import com.google.android.gms.cast.LaunchOptions
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider

/**
 * Cast SDK options, built from the receiver app the user picked (stored by
 * [storeReceiverAppId]) rather than from what Dart hands flutter_chrome_cast.
 *
 * The SDK asks for its options whenever the CastContext is first created, and
 * that is not always from Dart: a tap on the SDK's own media notification can
 * restart a killed app natively, before the Flutter side has run. The plugin's
 * provider only has options once Dart set them and crashes the app otherwise;
 * this one always has them.
 */
class ChudderCastOptionsProvider : OptionsProvider {
    companion object {
        private const val PREFS = "chudder_cast"
        private const val KEY_APP_ID = "receiverAppId"

        /** Jellyfin's stable Cast receiver. */
        const val DEFAULT_APP_ID = "F007D354"

        fun receiverAppId(context: Context): String =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_APP_ID, null) ?: DEFAULT_APP_ID

        fun storeReceiverAppId(context: Context, appId: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_APP_ID, appId).apply()
        }
    }

    override fun getCastOptions(context: Context): CastOptions =
        CastOptions.Builder()
            .setReceiverApplicationId(receiverAppId(context))
            // Lets Android TV receivers (Cast Connect) answer as well.
            .setLaunchOptions(LaunchOptions.Builder().setAndroidReceiverCompatible(true).build())
            // Rejoin the session after the app was closed or killed, and hold
            // it through Wi-Fi drops and the app being in the background.
            .setResumeSavedSession(true)
            .setEnableReconnectionService(true)
            .build()

    override fun getAdditionalSessionProviders(context: Context): MutableList<SessionProvider>? = null
}
