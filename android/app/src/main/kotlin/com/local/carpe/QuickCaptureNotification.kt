package com.local.carpe

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput

/** Builds the single, stable notification used for notification-tray task capture. */
object QuickCaptureNotification {
    private const val REPLY_REQUEST_CODE = 0x43415054 // "CAPT"; stable and unique to this action.

    fun showReady(context: Context) {
        notificationManager(context).notify(
            QuickCaptureContract.NOTIFICATION_ID,
            readyNotification(context),
        )
    }

    fun showProcessing(context: Context) {
        notificationManager(context).notify(
            QuickCaptureContract.NOTIFICATION_ID,
            processingNotification(context),
        )
    }

    /** Kept visible to instrumentation tests of the notification state machine. */
    internal fun readyNotification(context: Context) = builder(context)
        .setContentTitle("Carpe Diem quick capture")
        .setContentText("Reply here to create a task")
        .addAction(replyAction(context))
        .build()

    /** Processing intentionally has no reply action until work completes. */
    internal fun processingNotification(context: Context) = builder(context)
        .setContentTitle("Carpe Diem quick capture")
        .setContentText("Adding your task…")
        .setProgress(0, 0, true)
        .build()

    /**
     * Restores inline capture while making a background delivery problem visible
     * without opening the app or producing a disruptive alert.
     */
    fun showCaptureMessage(context: Context, message: String) {
        notificationManager(context).notify(
            QuickCaptureContract.NOTIFICATION_ID,
            builder(context)
                .setContentTitle("Carpe Diem quick capture")
                .setContentText(message)
                .addAction(replyAction(context))
                .build(),
        )
    }

    private fun builder(context: Context): NotificationCompat.Builder {
        createChannel(context)
        val iconId = context.resources.getIdentifier("ic_notification", "drawable", context.packageName)
        return NotificationCompat.Builder(context, QuickCaptureContract.NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(if (iconId != 0) iconId else R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
    }

    private fun replyAction(context: Context): NotificationCompat.Action {
        val remoteInput = RemoteInput.Builder(QuickCaptureContract.REMOTE_INPUT_RESULT_KEY)
            .setLabel("Type a task for Carpe Diem")
            .setAllowFreeFormInput(true)
            .build()
        val intent = Intent(context, ReplyReceiver::class.java).setAction(QuickCaptureContract.REPLY_ACTION_ID)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            REPLY_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Action.Builder(0, "Add task", pendingIntent)
            .addRemoteInput(remoteInput)
            .setAllowGeneratedReplies(true)
            .build()
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager(context).createNotificationChannel(
                NotificationChannel(
                    QuickCaptureContract.NOTIFICATION_CHANNEL_ID,
                    "Carpe direct reply",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply { description = "Persistent notification for background task capture." },
            )
        }
    }

    private fun notificationManager(context: Context): NotificationManager =
        context.getSystemService(NotificationManager::class.java)
}
