package com.local.carpe.telecom

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
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
            "isPhoneAccountEnabled" -> result.success(
                applicationContext.getSystemService(TelecomManager::class.java)
                    ?.callCapablePhoneAccounts
                    ?.isNotEmpty() == true,
            )
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
    }
}
