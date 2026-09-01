package com.local.carpe

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Bundle
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log

object CallManager {
    private var lastCallTime: Long = 0

    fun registerAccount(context: Context) {
        val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val componentName = ComponentName(context, CarpeConnectionService::class.java)
        val handle = PhoneAccountHandle(componentName, "CarpeDiemAccount")
        
        val account = PhoneAccount.builder(handle, "Carpe Diem")
            .setCapabilities(PhoneAccount.CAPABILITY_CALL_PROVIDER or PhoneAccount.CAPABILITY_CONNECTION_MANAGER)
            .setIcon(Icon.createWithResource(context, R.mipmap.ic_launcher))
            .setShortDescription("Carpe Diem Tasks")
            .build()
            
        telecomManager.registerPhoneAccount(account)
    }

    fun isAccountEnabled(context: Context): Boolean {
        registerAccount(context)
        val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val componentName = ComponentName(context, CarpeConnectionService::class.java)
        val handle = PhoneAccountHandle(componentName, "CarpeDiemAccount")
        return telecomManager.getPhoneAccount(handle)?.isEnabled == true
    }

    fun scheduleNativeAlarm(
        context: Context,
        taskId: String,
        name: String,
        number: String,
        audioPath: String?,
        timestampMs: Long
    ) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, CarpeAlarmReceiver::class.java).apply {
            action = "com.local.carpe.ALARM_TRIGGER"
            putExtra("EXTRA_TASK_ID", taskId)
            putExtra("EXTRA_CALLER_NAME", name)
            putExtra("EXTRA_CALLER_NUMBER", number)
            putExtra("EXTRA_AUDIO_PATH", audioPath)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            taskId.hashCode() and 0x7FFFFFFF,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val alarmClockInfo = AlarmManager.AlarmClockInfo(timestampMs, pendingIntent)
        alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
    }

    fun cancelNativeAlarm(context: Context, taskId: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, CarpeAlarmReceiver::class.java).apply {
            action = "com.local.carpe.ALARM_TRIGGER"
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            taskId.hashCode() and 0x7FFFFFFF,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
    }

    fun triggerIncomingCall(context: Context, taskId: String, name: String, number: String, audioPath: String?) {
        val now = System.currentTimeMillis()
        
        if (now - lastCallTime < 10000) {
            Log.w("CallManager", "Duplicate call blocked by debounce lock.")
            return
        }
        lastCallTime = now

        registerAccount(context)
        
        val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val componentName = ComponentName(context, CarpeConnectionService::class.java)
        val handle = PhoneAccountHandle(componentName, "CarpeDiemAccount")
        
        val cleanNumber = number.replace(Regex("[^0-9+]"), "")
        
        // Populate nested call extras for Telecom compliance
        val callExtras = Bundle().apply {
            putString("EXTRA_CALLER_NAME", name)
            putString("EXTRA_TASK_ID", taskId)
            putString("EXTRA_AUDIO_PATH", audioPath)
        }

        val bundle = Bundle().apply {
            putParcelable(TelecomManager.EXTRA_INCOMING_CALL_ADDRESS, Uri.parse("tel:${if (cleanNumber.isEmpty()) "12345" else cleanNumber}"))
            putString("EXTRA_CALLER_NAME", name)
            putString("EXTRA_TASK_ID", taskId)
            putString("EXTRA_AUDIO_PATH", audioPath)
            putBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS, callExtras)
        }
        
        telecomManager.addNewIncomingCall(handle, bundle)
    }
}
