import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'database_helper.dart';
import 'assistant_executor.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
Future<void> quickCaptureHeadlessMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  const channel = MethodChannel('com.local.carpe/quick_capture_worker');

  try {
    // 1. Initialize notifications to allow background feedback
    await NotificationService.initialize(isHeadless: true);
    
    final db = await DatabaseHelper.instance.database;
    
    // 2. Fetch pending tasks from the Kotlin UI
    final pending = await db.query(
      'capture_inbox',
      where: 'status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'created_at ASC',
    );

    for (final capture in pending) {
      final id = capture['id'];
      final text = capture['raw_text'] as String;
      final timestamp = capture['created_at'] as int;
      
      // 3. Inject the exact UI submission time to fix relative NLP rounding
      final refDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final result = await AssistantExecutor.instance.executeVoiceCommand(text, referenceDate: refDate);
      
      // 4. Mark as processed
      await db.update(
        'capture_inbox',
        {'status': 'DONE'},
        where: 'id = ?',
        whereArgs: [id],
      );
      
      // 5. Fire the success notification
      await NotificationService.showAssistantFeedback(result);
    }

    // 6. Signal Kotlin to close the background worker
    await channel.invokeMethod<void>('success');
  } catch (e, stacktrace) {
    debugPrint('Headless processing failed: $e\n$stacktrace');
    await channel.invokeMethod<void>('retry');
  }
}
