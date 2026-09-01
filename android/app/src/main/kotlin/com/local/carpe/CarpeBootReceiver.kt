package com.local.carpe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.io.File

class CarpeBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("CarpeBootReceiver", "Device booted or app updated. Action: ${intent.action}")
        
        CallManager.registerAccount(context)

        try {
            // FIX 1: Point strictly to the Flutter FFI database directory
            val appFlutterDir = context.getDir("flutter", Context.MODE_PRIVATE)
            val dbFile = File(appFlutterDir, "carpe_diem.db")
            
            if (dbFile.exists()) {
                // FIX 2: Enable WAL to prevent locking against the Flutter engine
                val db = SQLiteDatabase.openDatabase(
                    dbFile.absolutePath, 
                    null, 
                    SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING
                )
                
                // FIX 3: Query using the correct Flutter SQLite schema column names
                val cursor = db.rawQuery(
                    "SELECT id, title, contactName, contact_number, audioPath, due_date FROM tasks WHERE status = 'PENDING'", 
                    null
                )
                
                val now = System.currentTimeMillis()
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0)
                    val title = cursor.getString(1)
                    val name = cursor.getString(2) ?: title
                    val number = cursor.getString(3) ?: "Reminder"
                    val audioPath = cursor.getString(4)
                    val timestamp = cursor.getLong(5)
                    
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
