package com.local.carpe

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.local.carpe/telecom"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Native telecom calls are handled by CarpeTelecomPlugin. Keeping this
        // sender allows QuickCaptureTileService intents to open the UI sheet.
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Register as soon as the user opens the app so Android surfaces Carpe
        // in Calling Accounts before the first alarm or incoming call.
        CallManager.registerAccount(this)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        if (intent.getBooleanExtra("OPEN_CAPTURE_SHEET", false)) {
            methodChannel?.invokeMethod("openCaptureSheet", null)
        }
    }
}
