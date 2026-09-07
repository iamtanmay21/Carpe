package com.local.carpe

import android.content.Intent
import androidx.core.app.RemoteInput
import androidx.test.core.app.ApplicationProvider
import androidx.work.testing.TestListenableWorkerBuilder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class QuickCaptureNotificationTest {
    @Test
    fun `ready notification exposes inline reply and processing removes it`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()

        val ready = QuickCaptureNotification.readyNotification(context)
        val processing = QuickCaptureNotification.processingNotification(context)

        assertEquals(1, ready.actions.size)
        assertEquals(0, processing.actions.size)
        assertNotNull(ready.actions.single().remoteInputs.single())
        assertNull("The notification itself has no activity content intent", ready.contentIntent)
    }

    @Test
    fun `reply extractor rejects malformed and blank RemoteInput payloads`() {
        val empty = Intent(QuickCaptureContract.REPLY_ACTION_ID)
        assertNull(extractQuickCaptureReply(empty))

        val blank = Intent(QuickCaptureContract.REPLY_ACTION_ID)
        RemoteInput.addResultsToIntent(
            arrayOf(RemoteInput.Builder(QuickCaptureContract.REMOTE_INPUT_RESULT_KEY).build()),
            blank,
            android.os.Bundle().apply { putCharSequence(QuickCaptureContract.REMOTE_INPUT_RESULT_KEY, "  ") },
        )
        assertNull(extractQuickCaptureReply(blank))
    }

    @Test
    fun `reply action targets ReplyReceiver rather than an activity`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val action = QuickCaptureNotification.readyNotification(context).actions.single()
        val savedIntent = shadowOf(action.actionIntent).savedIntent

        assertEquals(QuickCaptureContract.REPLY_ACTION_ID, savedIntent.action)
        assertEquals(ReplyReceiver::class.java.name, savedIntent.component?.className)
        assertFalse(savedIntent.component?.className == MainActivity::class.java.name)
    }

    @Test
    fun `worker classifies only explicit retryable Dart responses as retry`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val worker = TestListenableWorkerBuilder<QuickCaptureWorker>(context).build()

        val successful = worker.run { DartResponse(true, false, "done").toWorkResult(context) }
        val retryable = worker.run { DartResponse(false, true, "temporary").toWorkResult(context) }
        val terminal = worker.run { DartResponse(false, false, "bad input").toWorkResult(context) }

        assertEquals(androidx.work.ListenableWorker.Result.success(), successful)
        assertEquals(androidx.work.ListenableWorker.Result.retry(), retryable)
        assertEquals(androidx.work.ListenableWorker.Result.failure(), terminal)
    }
}
