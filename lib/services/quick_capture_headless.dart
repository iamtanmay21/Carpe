import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/execution_result.dart';
import 'assistant_executor.dart';
import 'database_helper.dart';
import 'notification_service.dart';

const _quickCaptureWorkerChannel = MethodChannel(
  'com.local.carpe/quick_capture_worker',
);

/// Processes captures inserted by the native quick-capture activity.
@pragma('vm:entry-point')
Future<void> quickCaptureHeadlessMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  try {
    final db = await DatabaseHelper.instance.database;
    await NotificationService.initialize(isHeadless: true);
    final captures = await db.query(
      'capture_inbox',
      where: 'status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'created_at ASC',
    );

    for (final capture in captures) {
      final ExecutionResult result =
          await AssistantExecutor.instance.executeVoiceCommand(
        capture['raw_text'] as String,
        referenceDate: DateTime.fromMillisecondsSinceEpoch(
          capture['created_at'] as int,
        ),
      );
      await db.update(
        'capture_inbox',
        {'status': 'DONE'},
        where: 'id = ?',
        whereArgs: [capture['id']],
      );
      await NotificationService.showAssistantFeedback(result);
    }

    await _quickCaptureWorkerChannel.invokeMethod<void>('success');
  } catch (_) {
    await _quickCaptureWorkerChannel.invokeMethod<void>('retry');
  }
}
