package com.local.carpe.capture

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.plugins.util.GeneratedPluginRegister
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull

class CaptureWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)

        val engine = FlutterEngine(applicationContext)
        val completion = CompletableDeferred<Result>()
        val channel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            QUICK_CAPTURE_WORKER_CHANNEL,
        )

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "success", "done" -> {
                    if (!completion.isCompleted) completion.complete(Result.success())
                    result.success(null)
                }
                "retry" -> {
                    if (!completion.isCompleted) completion.complete(Result.retry())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        return try {
            GeneratedPluginRegister.registerGeneratedPlugins(engine)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(),
                    "quickCaptureHeadlessMain",
                ),
            )

            // A headless engine has no lifecycle callback. The Dart entrypoint
            // explicitly completes this worker over the channel when processing ends.
            withTimeoutOrNull(WORKER_TIMEOUT_MILLIS) { completion.await() }
                ?: Result.retry()
        } catch (_: Exception) {
            Result.retry()
        } finally {
            channel.setMethodCallHandler(null)
            engine.destroy()
            QuickCaptureNotifier.cancel(applicationContext)
        }
    }

    private companion object {
        const val QUICK_CAPTURE_WORKER_CHANNEL = "com.local.carpe/quick_capture_worker"
        const val WORKER_TIMEOUT_MILLIS = 60_000L
    }
}
