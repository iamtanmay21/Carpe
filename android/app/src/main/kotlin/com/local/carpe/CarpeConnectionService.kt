package com.local.carpe

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import java.util.Locale

class CarpeConnectionService : ConnectionService() {
    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val bundle = request?.extras
        val name = bundle?.getString("EXTRA_CALLER_NAME") ?: "Carpe Diem"
        val numberUri = bundle?.getParcelable<Uri>(TelecomManager.EXTRA_INCOMING_CALL_ADDRESS)
        val taskId = bundle?.getString("EXTRA_TASK_ID") ?: ""
        val audioPath = bundle?.getString("EXTRA_AUDIO_PATH")

        val connection = CarpeConnection(applicationContext, taskId, name, audioPath)
        connection.setAddress(numberUri, TelecomManager.PRESENTATION_ALLOWED)
        connection.setCallerDisplayName(name, TelecomManager.PRESENTATION_ALLOWED)
        connection.setInitializing()
        connection.setRinging()
        
        connection.audioModeIsVoip = true
        
        return connection
    }
    
    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ) {
        super.onCreateIncomingConnectionFailed(connectionManagerPhoneAccount, request)
    }
}

class CarpeConnection(
    private val context: Context,
    private val taskId: String,
    private val name: String,
    private val audioPath: String?
) : Connection() {

    private var mediaPlayer: MediaPlayer? = null
    private var tts: TextToSpeech? = null
    
    // Snooze Logic State
    private var isSnoozeMode = false
    private var snoozeInput = ""
    private val snoozeHandler = Handler(Looper.getMainLooper())
    private var snoozeRunnable: Runnable? = null

    // --- THE FIX: 45 SECOND TIMEOUT HANDLER ---
    private val ringTimeoutHandler = Handler(Looper.getMainLooper())
    private val ringTimeoutRunnable = Runnable {
        if (state == STATE_RINGING) {
            updateTaskStatusInDatabase("MISSED") // Automatically update SQLite
            setDisconnected(DisconnectCause(DisconnectCause.MISSED, "Missed reminder"))
            destroyConnection()
        }
    }

    init {
        // Start the 45-second countdown as soon as the call begins ringing
        ringTimeoutHandler.postDelayed(ringTimeoutRunnable, 45000)
    }

    override fun onAnswer() {
        super.onAnswer()
        
        // Cancel the 45-second timeout because the user picked up!
        ringTimeoutHandler.removeCallbacks(ringTimeoutRunnable)
        
        setActive()
        
        if (!audioPath.isNullOrEmpty()) {
            try {
                mediaPlayer = MediaPlayer().apply {
                    setDataSource(context, Uri.parse(audioPath))
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    prepareAsync()
                    setOnPreparedListener { start() }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        } else {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            
            var volume = 1.0f
            var speed = 0.5f 
            try {
                volume = prefs.getFloat("flutter.tts_volume", 1.0f)
                speed = prefs.getFloat("flutter.tts_speed", 0.5f) 
            } catch (e: Exception) {
                volume = prefs.getString("flutter.tts_volume", "1.0")?.toFloatOrNull() ?: 1.0f
                speed = prefs.getString("flutter.tts_speed", "0.5")?.toFloatOrNull() ?: 0.5f 
            }

            tts = TextToSpeech(context) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    tts?.language = Locale.US
                    tts?.setSpeechRate(speed)
                    
                    val audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION) 
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                    tts?.setAudioAttributes(audioAttributes)

                    val params = Bundle().apply {
                        putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
                    }

                    speak("Task: $name. Press 1 for done, 2 for missed, or 3 to snooze.", params)
                }
            }
        }
    }
    
    private fun speak(text: String, params: Bundle? = null) {
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params, "TTS_ID")
    }

    override fun onPlayDtmfTone(c: Char) {
        super.onPlayDtmfTone(c)
        
        if (isSnoozeMode) {
            if (c.isDigit()) {
                snoozeInput += c
                resetSnoozeTimer() 
            }
            return
        }

        when (c) {
            '1' -> {
                updateTaskStatusInDatabase("COMPLETED")
                endCall()
            }
            '2' -> {
                updateTaskStatusInDatabase("MISSED")
                endCall()
            }
            '3' -> {
                isSnoozeMode = true
                snoozeInput = ""
                speak("Enter minutes to snooze.")
                resetSnoozeTimer()
            }
        }
    }
    
    private fun resetSnoozeTimer() {
        snoozeRunnable?.let { snoozeHandler.removeCallbacks(it) }
        
        snoozeRunnable = Runnable {
            if (snoozeInput.isNotEmpty()) {
                val minutes = snoozeInput.toLongOrNull() ?: 0
                if (minutes > 0) {
                    val newTimeMs = System.currentTimeMillis() + (minutes * 60 * 1000)
                    snoozeTaskInDatabase(newTimeMs)
                    CallManager.scheduleNativeAlarm(context, taskId, name, "Reminder", audioPath, newTimeMs)
                    
                    speak("Snoozed for $snoozeInput minutes.")
                    Handler(Looper.getMainLooper()).postDelayed({ endCall() }, 2500)
                    return@Runnable
                }
            }
            isSnoozeMode = false
            speak("Snooze cancelled.")
        }
        
        snoozeHandler.postDelayed(snoozeRunnable!!, 5000)
    }

    private fun endCall() {
        setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
        destroyConnection()
    }

    override fun onDisconnect() {
        super.onDisconnect()
        endCall()
    }

    override fun onReject() {
        super.onReject()
        updateTaskStatusInDatabase("MISSED")
        setDisconnected(DisconnectCause(DisconnectCause.REJECTED))
        destroyConnection()
    }

    override fun onAbort() {
        super.onAbort()
        updateTaskStatusInDatabase("MISSED")
        setDisconnected(DisconnectCause(DisconnectCause.CANCELED))
        destroyConnection()
    }

    private fun destroyConnection() {
        // Safety cleanup to ensure the handler doesn't fire after the call ends
        ringTimeoutHandler.removeCallbacks(ringTimeoutRunnable)
        
        mediaPlayer?.let {
            if (it.isPlaying) it.stop()
            it.release()
        }
        mediaPlayer = null
        
        tts?.stop()
        tts?.shutdown()
        tts = null
        
        snoozeRunnable?.let { snoozeHandler.removeCallbacks(it) }
        
        destroy()
    }

    private fun updateTaskStatusInDatabase(status: String) {
        if (taskId.isEmpty()) return
        try {
            val dbFile = context.getDatabasePath("carpe_diem.db")
            if (!dbFile.exists()) return

            SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                null,
                SQLiteDatabase.OPEN_READWRITE
            ).use { db ->
                db.execSQL("UPDATE tasks SET status = ? WHERE id = ?", arrayOf(status, taskId))
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
    
    private fun snoozeTaskInDatabase(newTimestamp: Long) {
        if (taskId.isEmpty()) return
        try {
            val dbFile = context.getDatabasePath("carpe_diem.db")
            if (!dbFile.exists()) return

            SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                null,
                SQLiteDatabase.OPEN_READWRITE
            ).use { db ->
                db.execSQL(
                    "UPDATE tasks SET due_date = ?, status = 'PENDING' WHERE id = ?",
                    arrayOf(newTimestamp, taskId)
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
