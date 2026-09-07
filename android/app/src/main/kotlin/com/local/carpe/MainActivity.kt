package com.local.carpe

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val telecomChannel = "com.local.carpe/telecom"
    private val overlayChannel = "com.local.carpe/overlay"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Native telecom calls are handled by CarpeTelecomPlugin. Keeping this
        // sender allows QuickCaptureTileService intents to open the UI sheet.
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, telecomChannel)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, overlayChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "showPersistentNotification") {
                    showPersistentNotification()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
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

    private fun showPersistentNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    "persistent_channel",
                    "Assistant",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }

        val intent = FlutterActivity.withNewEngine()
            .initialRoute("/quick_capture")
            .backgroundMode(FlutterActivityLaunchConfigs.BackgroundMode.transparent)
            .build(this)
        val pendingIntent = PendingIntent.getActivity(
            this,
            100,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val action = NotificationCompat.Action.Builder(0, "Add Task", pendingIntent).build()
        val iconId = resources.getIdentifier("ic_notification", "drawable", packageName)

        val notification = NotificationCompat.Builder(this, "persistent_channel")
            .setSmallIcon(if (iconId != 0) iconId else R.mipmap.ic_launcher)
            .setContentTitle("Carpe Diem")
            .setContentText("What needs to be done?")
            .setOngoing(true)
            .addAction(action)
            .setContentIntent(pendingIntent)
            .build()

        manager.notify(0, notification)
    }
}
