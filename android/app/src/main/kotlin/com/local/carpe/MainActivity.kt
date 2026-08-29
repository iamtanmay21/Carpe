package com.local.carpe

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.telecom.TelecomManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.local.carpe/telecom"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleAlarm" -> {
                    val taskId = call.argument<String>("id") ?: ""
                    val name = call.argument<String>("name") ?: "Carpe Diem"
                    val number = call.argument<String>("number") ?: "Reminder"
                    val audioPath = call.argument<String>("audioPath")
                    val timestamp = call.argument<Long>("timestamp") ?: (System.currentTimeMillis() + 60000)

                    CallManager.scheduleNativeAlarm(this@MainActivity, taskId, name, number, audioPath, timestamp)
                    result.success(true)
                }
                "cancelAlarm" -> {
                    val taskId = call.argument<String>("id") ?: ""
                    CallManager.cancelNativeAlarm(this@MainActivity, taskId)
                    result.success(true)
                }
                "triggerCall" -> {
                    val taskId = call.argument<String>("id") ?: ""
                    val name = call.argument<String>("name") ?: "Unknown Caller"
                    val number = call.argument<String>("number") ?: "Carpe Diem"
                    val audioPath = call.argument<String>("audioPath")
                    
                    try {
                        CallManager.triggerIncomingCall(this@MainActivity, taskId, name, number, audioPath)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("TELECOM_ERROR", e.message, null)
                    }
                }
                "isPhoneAccountEnabled" -> {
                    val isEnabled = CallManager.isAccountEnabled(this@MainActivity)
                    result.success(isEnabled)
                }
                "openTelecomSettings" -> {
                    val telecomIntent = Intent(TelecomManager.ACTION_CHANGE_PHONE_ACCOUNTS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    this@MainActivity.startActivity(telecomIntent)
                    result.success(true)
                }
                "openAutoStartSettings" -> {
                    try {
                        val intent = Intent()
                        val manufacturer = android.os.Build.MANUFACTURER.lowercase()
                        when {
                            manufacturer.contains("xiaomi") || manufacturer.contains("redmi") || manufacturer.contains("poco") -> {
                                intent.component = android.content.ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")
                            }
                            manufacturer.contains("oppo") || manufacturer.contains("realme") -> {
                                intent.component = android.content.ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")
                            }
                            manufacturer.contains("vivo") -> {
                                intent.component = android.content.ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")
                            }
                            manufacturer.contains("huawei") || manufacturer.contains("honor") -> {
                                intent.component = android.content.ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")
                            }
                            manufacturer.contains("samsung") -> {
                                intent.component = android.content.ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity")
                            }
                            else -> {
                                intent.action = android.provider.Settings.ACTION_SETTINGS
                            }
                        }
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        this@MainActivity.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        val intent = Intent(android.provider.Settings.ACTION_SETTINGS)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        this@MainActivity.startActivity(intent)
                        result.success(false)
                    }
                }
                "openPlayStoreForSpeechServices" -> {
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=com.google.android.tts"))
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        this@MainActivity.startActivity(intent)
                    } catch (e: Exception) {}
                    result.success(true)
                }
                "openTTSSettings" -> {
                    try {
                        val intent = Intent("com.android.settings.TTS_SETTINGS")
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        this@MainActivity.startActivity(intent)
                    } catch (e: Exception) {}
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
