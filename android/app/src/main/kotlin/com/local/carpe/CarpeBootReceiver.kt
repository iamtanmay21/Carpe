package com.local.carpe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.util.Log

class CarpeBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("CarpeBootReceiver", "Device booted or app updated. Action: ${intent.action}")
        
        // Re-register Telecom Account instantly on boot
        CallManager.registerAccount(context)

        try {
            val dbFile = context.getDatabasePath("carpe_diem.db")
            if (dbFile.exists()) {
                val db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY)
                // Fetch both pending AND snoozed tasks
                val cursor = db.rawQuery("SELECT id, title, contact_name, contact_number, audio_path, due_date FROM tasks WHERE status = 'PENDING' OR status = 'SNOOZED'", null)
                
                val now = System.currentTimeMillis()
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0)
                    val title = cursor.getString(1)
                    val name = cursor.getString(2) ?: title
                    val number = cursor.getString(3) ?: "Reminder"
                    val audioPath = cursor.getString(4)
                    val timestamp = cursor.getLong(5)
                    
                    // If the phone was off when the alarm was supposed to go off, ring it 30 seconds after booting
                    val scheduleTime = if (timestamp < now) now + 30000 else timestamp
                    
                    CallManager.scheduleNativeAlarm(context, id, name, number, audioPath, scheduleTime)
                }
                cursor.close()
                db.close()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
