package com.local.carpe.capture

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import android.os.Bundle
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import com.local.carpe.R
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class QuickCaptureActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_quick_capture)
        
        // Dismiss Activity if the user taps the dark background
        findViewById<android.view.View>(R.id.scrimBackground).setOnClickListener { 
            finish() 
        }

        val timestampText = findViewById<TextView>(R.id.timestampText)
        val taskInput = findViewById<EditText>(R.id.taskInput)
        val saveButton = findViewById<ImageButton>(R.id.saveButton)

        // Set live timestamp (e.g., "Thu, Sep 10 • 11:31 PM")
        val sdf = SimpleDateFormat("EEE, MMM d • h:mm a", Locale.getDefault())
        timestampText.text = sdf.format(Date())

        taskInput.requestFocus()

        saveButton.setOnClickListener { saveTask(taskInput.text.toString()) }
        
        taskInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND) {
                saveTask(taskInput.text.toString())
                true
            } else false
        }
    }

    private fun saveTask(text: String) {
        val trimmedText = text.trim()
        if (trimmedText.isEmpty()) {
            finish()
            return
        }

        try {
            // 1. Write directly to the SQLite file
            // DatabaseHelper stores the app database in the application's files
            // directory, rather than Android's default databases directory.
            val dbPath = File(filesDir, "carpe_diem.db").path
            val db = SQLiteDatabase.openDatabase(dbPath, null, SQLiteDatabase.OPEN_READWRITE)
            
            val values = ContentValues().apply {
                put("raw_text", trimmedText)
                put("status", "PENDING")
                put("created_at", System.currentTimeMillis())
            }
            db.insert("capture_inbox", null, values)
            db.close()

            Toast.makeText(this, "Task saved", Toast.LENGTH_SHORT).show()

            // 2. Trigger the background NLP processor.
            QuickCaptureNotifier.show(this)
            val workRequest = OneTimeWorkRequestBuilder<CaptureWorker>()
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()
            WorkManager.getInstance(this).enqueue(workRequest)
            
        } catch (e: Exception) {
            Toast.makeText(this, "Failed to save task", Toast.LENGTH_SHORT).show()
        }

        finish() // Instantly close the UI
    }
}
