import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'assistant_executor.dart';
import 'database_helper.dart';

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
    final captures = await db.query(
      'capture_inbox',
      where: 'status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'created_at ASC',
    );

    for (final capture in captures) {
      await AssistantExecutor.instance.executeVoiceCommand(
        capture['raw_text'] as String,
      );
      await db.update(
        'capture_inbox',
        {'status': 'DONE'},
        where: 'id = ?',
        whereArgs: [capture['id']],
      );
    }

    await _quickCaptureWorkerChannel.invokeMethod<void>('success');
  } catch (_) {
    await _quickCaptureWorkerChannel.invokeMethod<void>('retry');
  }
}
