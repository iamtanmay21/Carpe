package com.local.carpe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log

class CarpeAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Grab a WakeLock to ensure the CPU doesn't fall asleep while initializing the call
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "CarpeDiem::AlarmWakeLock")
        wakeLock.acquire(10000) // Hold CPU awake for 10 seconds max
        
        val taskId = intent.getStringExtra("EXTRA_TASK_ID") ?: return
        val name = intent.getStringExtra("EXTRA_CALLER_NAME") ?: "Carpe Diem"
        val number = intent.getStringExtra("EXTRA_CALLER_NUMBER") ?: "Reminder"
        val audioPath = intent.getStringExtra("EXTRA_AUDIO_PATH")

        Log.d("CarpeAlarmReceiver", "Native Alarm Triggered for Task: $taskId")
        CallManager.triggerIncomingCall(context, taskId, name, number, audioPath)
    }
}
