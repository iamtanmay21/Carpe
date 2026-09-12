package com.local.carpe.capture

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
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

        withContext(Dispatchers.Main) {
            try {
                Log.d("CaptureWorker", "Initializing Flutter engine on Main thread")
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)

                engine = FlutterEngine(applicationContext)
                GeneratedPluginRegister.registerGeneratedPlugins(engine!!)

                channel = MethodChannel(engine!!.dartExecutor.binaryMessenger, "com.local.carpe/quick_capture_worker")
                channel?.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "success" -> {
                            Log.d("CaptureWorker", "Dart signaled success")
                            completion.complete(Result.success())
                            result.success(null)
                        }
                        "retry" -> {
                            Log.e("CaptureWorker", "Dart signaled retry/failure")
                            completion.complete(Result.retry())
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }

                engine!!.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "quickCaptureHeadlessMain")
                )
            } catch (e: Exception) {
                Log.e("CaptureWorker", "Flutter Boot Failed", e)
                showFailsafeNotification("Flutter Boot Failed", e.message ?: "Unknown Error")
                completion.complete(Result.failure())
            }
        }

        val finalResult = withTimeoutOrNull(30_000L) { completion.await() }
            ?: run {
                Log.e("CaptureWorker", "Dart engine timed out")
                showFailsafeNotification("Timeout", "Dart engine took too long.")
                Result.retry()
            }

        withContext(Dispatchers.Main) {
            channel?.setMethodCallHandler(null)
            engine?.destroy()
        }

        return finalResult
    }

    private fun showFailsafeNotification(title: String, message: String) {
        val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "feedback_channel",
                "Assistant Feedback",
                NotificationManager.IMPORTANCE_HIGH,
            )
            manager.createNotificationChannel(channel)
        }
        val notification = NotificationCompat.Builder(applicationContext, "feedback_channel")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        manager.notify(999, notification)
    }
}
