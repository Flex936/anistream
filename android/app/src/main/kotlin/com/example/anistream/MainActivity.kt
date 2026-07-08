package com.example.anistream

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "anistream/device_mode"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTelevision" -> result.success(isRunningOnTv())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Two independent signals, checked together:
     *  • UiModeManager reports UI_MODE_TYPE_TELEVISION on Android TV /
     *    Google TV — the most direct signal, but a handful of OEM TV boxes
     *    don't set it correctly.
     *  • FEATURE_LEANBACK is the platform feature every device shipping
     *    the Android TV launcher declares — a reliable fallback for those
     *    OEM cases.
     * True if either one says TV.
     */
    private fun isRunningOnTv(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        val isUiModeTv = uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
        val hasLeanback = packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        return isUiModeTv || hasLeanback
    }
}