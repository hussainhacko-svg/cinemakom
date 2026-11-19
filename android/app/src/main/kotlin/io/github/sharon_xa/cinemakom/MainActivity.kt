package io.github.sharon_xa.cinemakom

import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.Display
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighestRefreshRate()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // The resolution can change without a restart (configChanges), and
        // the preferred mode must have the current one.
        requestHighestRefreshRate()
    }

    /**
     * Asks for the display's fastest mode at the current resolution.
     *
     * Some vendors (OnePlus/OPPO ColorOS among them) run every app that isn't
     * on their allowlist at 60 Hz, even on a 120 Hz panel with the system set
     * to 120 Hz. Flutter draws at whatever rate the display runs, so the app
     * looked half as smooth as the rest of the phone. This is a preference,
     * not a lock: battery saver, thermal limits and the user's own refresh
     * setting still win, and it only applies while this window is in front.
     */
    private fun requestHighestRefreshRate() {
        @Suppress("DEPRECATION")
        val display: Display = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else null)
            ?: windowManager.defaultDisplay
        val current = display.mode
        val best = display.supportedModes
            .filter {
                it.physicalWidth == current.physicalWidth &&
                    it.physicalHeight == current.physicalHeight
            }
            .maxByOrNull { it.refreshRate } ?: return
        val attributes = window.attributes
        if (attributes.preferredDisplayModeId == best.modeId) return
        attributes.preferredDisplayModeId = best.modeId
        window.attributes = attributes
    }
}
