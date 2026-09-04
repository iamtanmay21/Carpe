package com.local.carpe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Receives telecom commands from any Flutter engine, including headless ones. */
class CarpeTelecomCommandReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getStringExtra(EXTRA_COMMAND)) {
            COMMAND_SCHEDULE -> CallManager.scheduleNativeAlarm(
                context,
                intent.getStringExtra("id").orEmpty(),
                intent.getStringExtra("name") ?: "Carpe Diem",
                intent.getStringExtra("number") ?: "Reminder",
                intent.getStringExtra("audioPath"),
                intent.getLongExtra("timestamp", System.currentTimeMillis() + 60_000),
            )
            COMMAND_CANCEL -> CallManager.cancelNativeAlarm(context, intent.getStringExtra("id").orEmpty())
            COMMAND_TRIGGER -> CallManager.triggerIncomingCall(
                context,
                intent.getStringExtra("id").orEmpty(),
                intent.getStringExtra("name") ?: "Unknown Caller",
                intent.getStringExtra("number") ?: "Carpe Diem",
                intent.getStringExtra("audioPath"),
            )
        }
    }

    private companion object {
        const val EXTRA_COMMAND = "command"
        const val COMMAND_SCHEDULE = "schedule"
        const val COMMAND_CANCEL = "cancel"
        const val COMMAND_TRIGGER = "trigger"
    }
}
