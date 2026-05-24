package com.lockly.securebox

import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import android.view.autofill.AutofillManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val autofillChannel = "lockly/autofill"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, autofillChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAutofillStatus" -> result.success(autofillStatus())
                    "openAutofillSettings" -> {
                        openAutofillSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun autofillStatus(): Map<String, Boolean> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return mapOf("supported" to false, "enabled" to false)
        }
        val manager = getSystemService(AutofillManager::class.java)
        val supported = manager?.isAutofillSupported == true
        val enabledService = Settings.Secure.getString(contentResolver, "autofill_service")
        return mapOf(
            "supported" to supported,
            "enabled" to (enabledService == locklyAutofillComponent())
        )
    }

    private fun openAutofillSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
            return
        }

        val requestIntent = Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE).apply {
            putExtra("android.provider.extra.AUTOFILL_SERVICE", locklyAutofillComponent())
        }
        try {
            startActivity(requestIntent)
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }

    private fun locklyAutofillComponent(): String {
        return ComponentName(this, LocklyAutofillService::class.java)
            .flattenToString()
    }
}
