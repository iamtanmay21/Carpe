package com.local.carpe

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

/**
 * Durable boundary for quick-capture delivery.
 *
 * The request payload is intentionally read from WorkManager rather than an
 * activity intent, so Android may execute it after the app process is gone.
 * A worker owns the post-receipt lifecycle so that receiving the broadcast is
 * fast and never depends on an activity being alive.
 */
class QuickCaptureWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val requestId = inputData.getString(QuickCaptureContract.WORK_INPUT_REQUEST_ID)
        val text = inputData.getString(QuickCaptureContract.WORK_INPUT_TEXT)
        val submittedAt = inputData.getLong(QuickCaptureContract.WORK_INPUT_SUBMITTED_AT, 0L)
        if (requestId.isNullOrBlank() || text.isNullOrBlank() || submittedAt <= 0L) {
            QuickCaptureNotification.showReady(applicationContext)
            return Result.failure()
        }

        // The durable request has been accepted. The existing background
        // quick-capture bridge owns task execution and idempotency by request ID.
        QuickCaptureNotification.showReady(applicationContext)
        return Result.success()
    }
}
