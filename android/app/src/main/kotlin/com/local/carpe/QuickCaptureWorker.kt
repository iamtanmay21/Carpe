package com.local.carpe

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlin.coroutines.resume

/**
 * Runs one durable quick-capture request in a dedicated, headless Flutter
 * isolate. Kotlin deliberately only transports the request: Dart remains the
 * sole owner of the Flutter-managed SQLite database and idempotency records.
 */
class QuickCaptureWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val requestId = inputData.getString(QuickCaptureContract.WORK_INPUT_REQUEST_ID)
        val text = inputData.getString(QuickCaptureContract.WORK_INPUT_TEXT)
        val submittedAt = inputData.getLong(QuickCaptureContract.WORK_INPUT_SUBMITTED_AT, 0L)
        val metadata = inputData.getString(QuickCaptureContract.WORK_INPUT_METADATA)
        if (requestId.isNullOrBlank() || text.isNullOrBlank() || submittedAt <= 0L || metadata == null) {
            QuickCaptureNotification.showCaptureMessage(applicationContext, "Could not add task. Try again.")
            return Result.failure()
        }

        val request = QuickCaptureRequest(requestId, text, submittedAt, metadata)
        return try {
            engineMutex.withLock {
                withTimeout(BRIDGE_TIMEOUT_MS) {
                    HeadlessQuickCaptureBridge(applicationContext).process(request)
                }
            }.toWorkResult(applicationContext)
        } catch (_: TimeoutCancellationException) {
            QuickCaptureNotification.showCaptureMessage(applicationContext, "Still trying to add your task.")
            Result.retry()
        } catch (_: Exception) {
            // Engine startup and platform-channel failures are normally
            // transient (for example while Flutter is loading after process death).
            QuickCaptureNotification.showCaptureMessage(applicationContext, "Could not add task yet. It will retry.")
            Result.retry()
        }
    }

    private fun DartResponse.toWorkResult(context: Context): Result = when {
        success -> {
            QuickCaptureNotification.showReady(context)
            Result.success()
        }
        retryable -> {
            QuickCaptureNotification.showCaptureMessage(context, message.ifBlank { "Could not add task yet. It will retry." })
            Result.retry()
        }
        else -> {
            // The reply action stays attached so the user can immediately
            // submit a corrected task without launching any UI.
            QuickCaptureNotification.showCaptureMessage(context, message.ifBlank { "Could not add task. Try again." })
            Result.failure()
        }
    }

    private companion object {
        const val BRIDGE_TIMEOUT_MS = 25_000L
        val engineMutex = Mutex()
    }
}

private data class DartResponse(val success: Boolean, val retryable: Boolean, val message: String)

/** One-use bridge: the engine is always destroyed after Dart's explicit result. */
private class HeadlessQuickCaptureBridge(private val context: Context) {
    suspend fun process(request: QuickCaptureRequest): DartResponse = withContext(Dispatchers.Main.immediate) {
        FlutterInjector.instance().flutterLoader().apply {
            startInitialization(context)
            ensureInitializationComplete(context, null)
        }

        val engine = FlutterEngine(context)
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, QuickCaptureContract.METHOD_CHANNEL_NAME)
        try {
            val ready = kotlinx.coroutines.CompletableDeferred<Unit>()
            channel.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                if (call.method == QuickCaptureContract.METHOD_DART_READY) {
                    ready.complete(Unit)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    "quickCaptureEntrypoint",
                ),
            )
            withTimeout(READY_TIMEOUT_MS) { ready.await() }
            channel.invokeForResponse(QuickCaptureContract.METHOD_PROCESS_QUICK_CAPTURE, request.toMethodChannelArguments())
        } finally {
            channel.setMethodCallHandler(null)
            engine.destroy()
        }
    }

    private suspend fun MethodChannel.invokeForResponse(method: String, arguments: Map<String, Any>): DartResponse =
        suspendCancellableCoroutine { continuation ->
            invokeMethod(method, arguments, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (!continuation.isActive) return
                    val payload = result as? Map<*, *>
                    val success = payload?.get(QuickCaptureContract.RESPONSE_SUCCESS) as? Boolean
                    val retryable = payload?.get(QuickCaptureContract.RESPONSE_RETRYABLE) as? Boolean
                    val message = payload?.get(QuickCaptureContract.RESPONSE_MESSAGE) as? String ?: ""
                    if (success == null || retryable == null) {
                        continuation.resume(DartResponse(false, false, "Quick capture returned an invalid response."))
                    } else {
                        continuation.resume(DartResponse(success, retryable, message))
                    }
                }

                override fun error(code: String, message: String?, details: Any?) {
                    if (!continuation.isActive) return
                    // A Dart-side platform error means no structured outcome was
                    // returned; allow WorkManager's bounded retry policy to recover.
                    continuation.resume(DartResponse(false, true, message ?: "Quick capture bridge error: $code"))
                }

                override fun notImplemented() {
                    if (!continuation.isActive) return
                    continuation.resume(DartResponse(false, false, "Quick capture is unavailable in this app version."))
                }
            })
        }

    private companion object {
        const val READY_TIMEOUT_MS = 8_000L
    }
}
