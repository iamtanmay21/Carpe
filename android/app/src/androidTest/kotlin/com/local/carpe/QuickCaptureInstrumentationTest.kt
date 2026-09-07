package com.local.carpe

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.os.Bundle
import androidx.core.app.RemoteInput
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/** Runs on API 24+; notification permission state does not affect construction. */
@RunWith(AndroidJUnit4::class)
class QuickCaptureInstrumentationTest {
    @Test
    fun replyExtractionTrimsBoundsAndRejectsEmptyPayloads() {
        val intent = Intent(QuickCaptureContract.REPLY_ACTION_ID)
        val input = RemoteInput.Builder(QuickCaptureContract.REMOTE_INPUT_RESULT_KEY).build()
        RemoteInput.addResultsToIntent(
            arrayOf(input),
            intent,
            android.os.Bundle().apply {
                putCharSequence(QuickCaptureContract.REMOTE_INPUT_RESULT_KEY, "  capture this  ")
            },
        )
        assertEquals("capture this", extractQuickCaptureReply(intent))
        assertNull(extractQuickCaptureReply(Intent(QuickCaptureContract.REPLY_ACTION_ID)))
    }

    @Test
    fun readyProcessingReadyStateKeepsPrimaryActionInline() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val ready = QuickCaptureNotification.readyNotification(context)
        val processing = QuickCaptureNotification.processingNotification(context)
        val restored = QuickCaptureNotification.readyNotification(context)

        assertEquals(1, ready.actions.size)
        assertEquals(0, processing.actions.size)
        assertEquals(1, restored.actions.size)
        assertNotNull(restored.actions.single().remoteInputs.single())
        assertNull("No content activity is configured for quick capture", restored.contentIntent)
    }

    @Test
    fun primaryReplyActionDoesNotStartAnActivity() {
        val application = ApplicationProvider.getApplicationContext<Application>()
        var startedActivities = 0
        val callbacks = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, state: Bundle?) { startedActivities++ }
            override fun onActivityStarted(activity: Activity) = Unit
            override fun onActivityResumed(activity: Activity) = Unit
            override fun onActivityPaused(activity: Activity) = Unit
            override fun onActivityStopped(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) = Unit
            override fun onActivityDestroyed(activity: Activity) = Unit
        }
        application.registerActivityLifecycleCallbacks(callbacks)
        try {
            QuickCaptureNotification.readyNotification(application)
                .actions
                .single()
                .actionIntent
                .send()
            assertEquals(0, startedActivities)
        } finally {
            application.unregisterActivityLifecycleCallbacks(callbacks)
        }
    }
}
