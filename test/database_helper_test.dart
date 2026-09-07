import 'dart:io';

import 'package:carpediem/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDirectory;
  late DatabaseHelper helper;

  setUp(() async {
    sqfliteFfiInit();
    tempDirectory = await Directory.systemTemp.createTemp('carpe_database_test_');
    helper = DatabaseHelper.forTesting(
      factory: databaseFactoryFfi,
      path: '${tempDirectory.path}/carpe_diem.db',
    );
  });

  tearDown(() async {
    final database = await helper.database;
    await database.close();
    await tempDirectory.delete(recursive: true);
  });

  test('database initialization is single-flight for simultaneous callers', () async {
    final databases = await Future.wait(List.generate(20, (_) => helper.database));

    expect(databases.toSet(), hasLength(1));
    expect(await databases.first.rawQuery('PRAGMA busy_timeout'), [
      {'timeout': 5000},
    ]);
    expect(await databases.first.rawQuery('PRAGMA journal_mode'), [
      {'journal_mode': 'wal'},
    ]);
  });

  test('duplicate quick capture request IDs have one durable claim', () async {
    final claims = await Future.wait(
      List.generate(20, (_) => helper.claimQuickCaptureRequest('same-request')),
    );

    expect(claims.where((claim) => claim), hasLength(1));
    expect(
      (await helper.getQuickCaptureRequest('same-request'))?['status'],
      'PROCESSING',
    );
  });

  test('retryable quick capture requests can be claimed again', () async {
    expect(await helper.claimQuickCaptureRequest('retry-request'), isTrue);
    await helper.completeQuickCaptureRequest(
      'retry-request',
      status: 'RETRYABLE',
      message: 'Temporary failure.',
    );

    expect(await helper.claimQuickCaptureRequest('retry-request'), isTrue);
    expect(
      (await helper.getQuickCaptureRequest('retry-request'))?['status'],
      'PROCESSING',
    );
  });

  test('concurrent foreground and headless writes mutate one task per request', () async {
    final headlessHelper = DatabaseHelper.forTesting(
      factory: databaseFactoryFfi,
      path: '${tempDirectory.path}/carpe_diem.db',
    );

    Future<void> process(
      DatabaseHelper engine,
      String requestId,
      String taskId,
    ) async {
      if (!await engine.claimQuickCaptureRequest(requestId)) return;
      final database = await engine.database;
      await database.transaction((transaction) async {
        await transaction.insert('tasks', {
          'id': taskId,
          'title': 'Captured task',
          'due_date': DateTime.now().millisecondsSinceEpoch,
        });
      });
      await engine.completeQuickCaptureRequest(
        requestId,
        status: 'COMPLETED',
        taskIds: '["$taskId"]',
        message: 'Created task.',
      );
    }

    await Future.wait([
      process(helper, 'notification-request', 'foreground-task'),
      process(headlessHelper, 'notification-request', 'headless-task'),
    ]);

    final rows = await (await helper.database).query('tasks');
    expect(rows, hasLength(1));
    expect(rows.single['id'], anyOf('foreground-task', 'headless-task'));
    await (await headlessHelper.database).close();
  });
}
