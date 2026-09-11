package com.local.carpe.capture

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.local.carpe.R

object QuickCaptureNotifier {
    private const val channelId = "persistent_channel"
    private const val notificationId = 1042

    fun show(context: Context) {
        createChannel(context)

        val openCaptureIntent = Intent(context, QuickCaptureActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            openCaptureIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Carpe Diem")
            .setContentText("What needs to be done?")
            .setContentIntent(contentIntent)
            .addAction(
                R.mipmap.ic_launcher,
                "Add Task",
                contentIntent,
            )
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }

    fun cancel(context: Context) {
        NotificationManagerCompat.from(context).cancel(notificationId)
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            channelId,
            "Assistant Overlay",
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.setShowBadge(false)
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
