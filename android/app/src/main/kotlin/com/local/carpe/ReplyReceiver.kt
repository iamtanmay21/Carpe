package com.local.carpe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.RemoteInput
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import java.util.UUID

/** Receives inline notification replies without launching any activity. */
class ReplyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != QuickCaptureContract.REPLY_ACTION_ID) return

        val reply = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(QuickCaptureContract.REMOTE_INPUT_RESULT_KEY)
            ?.toString()
            ?.trim()
            ?.take(QuickCaptureContract.MAX_REPLY_LENGTH)
            ?: return
        if (reply.isEmpty()) return

        val requestId = UUID.randomUUID().toString()
        val submittedAt = System.currentTimeMillis()
        QuickCaptureNotification.showProcessing(context)

        val input = Data.Builder()
            .putString(QuickCaptureContract.WORK_INPUT_REQUEST_ID, requestId)
            .putString(QuickCaptureContract.WORK_INPUT_TEXT, reply)
            .putLong(QuickCaptureContract.WORK_INPUT_SUBMITTED_AT, submittedAt)
            .build()
        val request = OneTimeWorkRequestBuilder<QuickCaptureWorker>()
            .setInputData(input)
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .addTag("quick-capture-$requestId")
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            "quick-capture-$requestId",
            ExistingWorkPolicy.KEEP,
            request,
        )
    }
}
