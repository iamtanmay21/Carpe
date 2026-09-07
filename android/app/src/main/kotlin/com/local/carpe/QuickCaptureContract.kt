package com.local.carpe

/**
 * Wire contract for Android's notification quick-capture flow.
 *
 * Keep the values in this object synchronized with
 * `lib/services/quick_capture_contract.dart`. Changing one side without the
 * other breaks pending notification actions and MethodChannel messages.
 *
 * Notification state machine:
 *  1. [STATE_READY] displays the persistent notification with inline input.
 *  2. [STATE_PROCESSING] replaces it as soon as Android receives a reply.
 *  3. Return to [STATE_READY] after processing succeeds or fails recoverably.
 *
 * A [QuickCaptureRequest.requestId] is the idempotency key. Preserve it when
 * Android redelivers an intent or WorkManager retries work so Dart can avoid
 * creating the same task more than once.
 */
object QuickCaptureContract {
    const val NOTIFICATION_CHANNEL_ID = "carpe_direct_reply"
    const val NOTIFICATION_ID = 4100
    const val REPLY_ACTION_ID = "carpe_direct_reply_action"
    const val REMOTE_INPUT_RESULT_KEY = "carpe_direct_reply_text"

    const val METHOD_CHANNEL_NAME = "com.local.carpe/quick_capture"
    const val METHOD_PROCESS_QUICK_CAPTURE = "processQuickCapture"

    const val ARG_REQUEST_ID = "requestId"
    const val ARG_TEXT = "text"
    const val ARG_SUBMITTED_AT = "submittedAt"

    const val RESPONSE_SUCCESS = "success"
    const val RESPONSE_RETRYABLE = "retryable"
    const val RESPONSE_MESSAGE = "message"
    const val RESPONSE_TASK_ID = "taskId"
    const val RESPONSE_TASK_IDS = "taskIds"

    const val STATE_READY = "ready"
    const val STATE_PROCESSING = "processing"
}

/**
 * Payload sent from Kotlin to Dart via `processQuickCapture`.
 *
 * [submittedAt] is Unix time in milliseconds. It records when Android accepted
 * the reply; it is not a task due date.
 */
data class QuickCaptureRequest(
    val requestId: String,
    val text: String,
    val submittedAt: Long,
) {
    fun toMethodChannelArguments(): Map<String, Any> = mapOf(
        QuickCaptureContract.ARG_REQUEST_ID to requestId,
        QuickCaptureContract.ARG_TEXT to text,
        QuickCaptureContract.ARG_SUBMITTED_AT to submittedAt,
    )
}
