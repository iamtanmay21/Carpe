package com.local.carpe.telecom

import android.content.Context
import android.content.ComponentName
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import android.provider.Settings
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Registers the telecom channel with every FlutterEngine.
 *
 * Notification action callbacks run in a headless engine, where an Activity's
 * configureFlutterEngine is never called. A FlutterPlugin is registered by the
 * generated plugin registrant for both UI and headless engines.
 */
class CarpeTelecomPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var applicationContext: Context
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        registerPhoneAccount()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scheduleAlarm" -> scheduleAlarm(call, result)
            "cancelAlarm" -> {
                sendCommand(COMMAND_CANCEL, call)
                result.success(true)
            }
            "triggerCall" -> triggerCall(call, result)
            "isPhoneAccountEnabled" -> result.success(isPhoneAccountEnabled())
            "openTelecomSettings" -> openTelecomSettings(result)
            "openAutoStartSettings" -> openAutoStartSettings(result)
            "openPlayStoreForSpeechServices" -> openPlayStore(result)
            "openTTSSettings" -> openTtsSettings(result)
            else -> result.notImplemented()
        }
    }

    private fun scheduleAlarm(call: MethodCall, result: MethodChannel.Result) {
        sendCommand(COMMAND_SCHEDULE, call)
        result.success(true)
    }

    private fun triggerCall(call: MethodCall, result: MethodChannel.Result) {
        sendCommand(COMMAND_TRIGGER, call)
        result.success(true)
    }

    private fun isPhoneAccountEnabled(): Boolean {
        registerPhoneAccount()
        val telecomManager = applicationContext.getSystemService(TelecomManager::class.java)
            ?: return false
        val componentName = ComponentName(
            applicationContext.packageName,
            CONNECTION_SERVICE_CLASS,
        )
        val accountHandle = PhoneAccountHandle(componentName, ACCOUNT_ID)
        return telecomManager.getPhoneAccount(accountHandle)?.isEnabled == true
    }

    /**
     * This module has its own Gradle namespace, so use the app's concrete
     * ConnectionService class name when creating the PhoneAccountHandle.
     */
    private fun registerPhoneAccount() {
        val telecomManager = applicationContext.getSystemService(TelecomManager::class.java)
            ?: return
        val componentName = ComponentName(
            applicationContext.packageName,
            CONNECTION_SERVICE_CLASS,
        )
        val accountHandle = PhoneAccountHandle(componentName, ACCOUNT_ID)
        val account = PhoneAccount.builder(accountHandle, "Carpe Diem")
            .setCapabilities(
                PhoneAccount.CAPABILITY_CALL_PROVIDER or
                    PhoneAccount.CAPABILITY_CONNECTION_MANAGER,
            )
            .setIcon(
                Icon.createWithResource(
                    applicationContext,
                    applicationContext.applicationInfo.icon,
                ),
            )
            .setShortDescription("Carpe Diem Tasks")
            .build()
        telecomManager.registerPhoneAccount(account)
    }

    private fun sendCommand(command: String, call: MethodCall) {
        applicationContext.sendBroadcast(
            Intent(ACTION_TELECOM_COMMAND)
                .setPackage(applicationContext.packageName)
                .putExtra(EXTRA_COMMAND, command)
                .putExtra("id", call.argument<String>("id"))
                .putExtra("name", call.argument<String>("name"))
                .putExtra("number", call.argument<String>("number"))
                .putExtra("audioPath", call.argument<String>("audioPath"))
                .putExtra("timestamp", call.argument<Long>("timestamp")),
        )
    }

    private fun openTelecomSettings(result: MethodChannel.Result) {
        applicationContext.startActivity(Intent(TelecomManager.ACTION_CHANGE_PHONE_ACCOUNTS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        result.success(true)
    }

    private fun openAutoStartSettings(result: MethodChannel.Result) {
        applicationContext.startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        result.success(true)
    }

    private fun openPlayStore(result: MethodChannel.Result) {
        applicationContext.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=com.google.android.tts")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        result.success(true)
    }

    private fun openTtsSettings(result: MethodChannel.Result) {
        applicationContext.startActivity(Intent("com.android.settings.TTS_SETTINGS").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        result.success(true)
    }

    private companion object {
        const val CHANNEL = "com.local.carpe/telecom"
        const val ACTION_TELECOM_COMMAND = "com.local.carpe.TELECOM_COMMAND"
        const val EXTRA_COMMAND = "command"
        const val COMMAND_SCHEDULE = "schedule"
        const val COMMAND_CANCEL = "cancel"
        const val COMMAND_TRIGGER = "trigger"
        const val CONNECTION_SERVICE_CLASS = "com.local.carpe.CarpeConnectionService"
        const val ACCOUNT_ID = "CarpeDiemAccount"
    }
}
