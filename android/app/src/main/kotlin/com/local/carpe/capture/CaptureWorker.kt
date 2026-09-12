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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

class CaptureWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        val completion = CompletableDeferred<Result>()
        var engine: FlutterEngine? = null
        var channel: MethodChannel? = null

        // 1. Initialize Flutter on the Main Thread so native plugins work
        withContext(Dispatchers.Main) {
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)

                engine = FlutterEngine(applicationContext)
                GeneratedPluginRegister.registerGeneratedPlugins(engine!!)

                channel = MethodChannel(
                    engine!!.dartExecutor.binaryMessenger,
                    "com.local.carpe/quick_capture_worker"
                )
                
                channel?.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "success", "done" -> {
                            completion.complete(Result.success())
                            result.success(null)
                        }
                        "retry" -> {
                            completion.complete(Result.retry())
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }

                engine!!.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        "quickCaptureHeadlessMain"
                    )
                )
            } catch (e: Exception) {
                e.printStackTrace()
                completion.complete(Result.failure())
            }
        }

        // 2. Wait for Dart on a Background Thread to prevent deadlocks
        val finalResult = withTimeoutOrNull(60_000L) { completion.await() } ?: Result.retry()

        // 3. Clean up memory on the Main Thread
        withContext(Dispatchers.Main) {
            channel?.setMethodCallHandler(null)
            engine?.destroy()
        }

        return finalResult
    }
}
