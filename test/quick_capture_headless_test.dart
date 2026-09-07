import 'dart:io';

import 'package:carpediem/services/database_helper.dart';
import 'package:carpediem/services/quick_capture_contract.dart';
import 'package:carpediem/services/quick_capture_headless.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DatabaseHelper database;

  setUp(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('quick_capture_test_');
    database = DatabaseHelper.forTesting(
      factory: databaseFactoryFfi,
      path: '${directory.path}/carpe.db',
    );
    DatabaseHelper.installForTesting(database);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.local.carpe/telecom'),
            (call) async => null);
  });

  tearDown(() async {
    await (await database.database).close();
    DatabaseHelper.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.local.carpe/telecom'), null);
    await directory.delete(recursive: true);
  });

  test('rejects malformed and empty native payloads without a durable claim', () async {
    for (final payload in <Object?>[
      null,
      <String, Object>{},
      <String, Object>{
        QuickCaptureContract.requestIdKey: 'request',
        QuickCaptureContract.textKey: '   ',
        QuickCaptureContract.submittedAtKey: 1,
      },
    ]) {
      final result = await processQuickCapture(payload);
      expect(result[QuickCaptureContract.successKey], isFalse);
      expect(result[QuickCaptureContract.retryableKey], isFalse);
    }
    expect(await (await database.database).query('quick_capture_requests'), isEmpty);
  });

  test('headless MethodChannel creates one task for repeated request delivery', () async {
    const channel = MethodChannel(QuickCaptureContract.methodChannelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) => processQuickCapture(call.arguments));
    final payload = <String, Object>{
      QuickCaptureContract.requestIdKey: 'method-channel-request',
      QuickCaptureContract.textKey: 'add buy milk tomorrow',
      QuickCaptureContract.submittedAtKey: DateTime.now().millisecondsSinceEpoch,
      QuickCaptureContract.metadataKey: '{"source":"test"}',
    };

    final first = await channel.invokeMethod<Map<Object?, Object>>(
      QuickCaptureContract.processQuickCaptureMethod,
      payload,
    );
    final second = await channel.invokeMethod<Map<Object?, Object>>(
      QuickCaptureContract.processQuickCaptureMethod,
      payload,
    );

    expect(first?[QuickCaptureContract.successKey], isTrue);
    expect(second?[QuickCaptureContract.successKey], isTrue);
    expect(await (await database.database).query('tasks'), hasLength(1));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
