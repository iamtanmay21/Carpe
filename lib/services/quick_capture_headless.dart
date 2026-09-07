import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'assistant_executor.dart';
import 'database_helper.dart';
import 'quick_capture_contract.dart';

const _quickCaptureChannel = MethodChannel(QuickCaptureContract.methodChannelName);

/// Starts the headless isolate used by Android's [QuickCaptureWorker].
///
/// This entrypoint deliberately performs no UI, permission, or notification
/// work. It initializes only the Flutter plugins required to open the database
/// and execute the quick-capture command.
@pragma('vm:entry-point')
void quickCaptureHeadlessMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await DatabaseHelper.instance.database;
  installQuickCaptureMethodChannelHandler();
  await _quickCaptureChannel.invokeMethod<void>(
    QuickCaptureContract.dartReadyMethod,
  );
}

/// Installs the method handler used by both the UI and headless engines.
void installQuickCaptureMethodChannelHandler() {
  _quickCaptureChannel.setMethodCallHandler((call) async {
    if (call.method != QuickCaptureContract.processQuickCaptureMethod) {
      throw MissingPluginException(
        'Unsupported quick capture method: ${call.method}',
      );
    }
    return processQuickCapture(call.arguments);
  });
}

/// Processes one native quick-capture payload.
///
/// Public for the platform-channel integration test; callers should normally
/// install [installQuickCaptureMethodChannelHandler] instead.
@visibleForTesting
Future<Map<String, Object>> processQuickCapture(Object? arguments) async {
  final request = _parseRequest(arguments);
  if (request == null) return _invalidRequestResponse();

  final database = DatabaseHelper.instance;
  final existing = await database.getQuickCaptureRequest(request.requestId);
  final existingResponse = _responseForExistingRequest(existing);
  if (existingResponse != null) return existingResponse;

  if (!await database.claimQuickCaptureRequest(request.requestId)) {
    final racedRequest =
        await database.getQuickCaptureRequest(request.requestId);
    return _responseForExistingRequest(racedRequest) ?? _retryableResponse(
      'Quick capture is already being processed.',
    );
  }

  try {
    final result = await AssistantExecutor.instance.executeVoiceCommand(
      request.text,
    );
    final taskIds = result.affectedTasks
        .map((task) => task['id']?.toString())
        .whereType<String>()
        .toList();
    final status = result.success ? 'COMPLETED' : 'FAILED';
    await database.completeQuickCaptureRequest(
      request.requestId,
      status: status,
      taskIds: jsonEncode(taskIds),
      message: result.feedbackMessage,
    );
    return QuickCaptureResponse(
      success: result.success,
      retryable: false,
      message: result.feedbackMessage,
      taskId: taskIds.length == 1 ? taskIds.single : null,
      taskIds: taskIds.length > 1 ? taskIds : null,
    ).toMethodChannelResult();
  } catch (_) {
    const message = 'Quick capture could not be processed. It will retry.';
    await database.completeQuickCaptureRequest(
      request.requestId,
      status: 'RETRYABLE',
      message: message,
    );
    return _retryableResponse(message);
  }
}

QuickCaptureRequest? _parseRequest(Object? arguments) {
  if (arguments is! Map) return null;
  try {
    final request = QuickCaptureRequest.fromMethodCall(
      Map<Object?, Object?>.from(arguments),
    );
    if (request.requestId.trim().isEmpty || request.text.trim().isEmpty) {
      return null;
    }
    return request;
  } catch (_) {
    return null;
  }
}

Map<String, Object>? _responseForExistingRequest(Map<String, Object?>? record) {
  if (record == null) return null;

  final status = record['status'];
  final message = record['result_message'] as String? ??
      'Quick capture is already being processed.';
  final taskIds = _taskIdsFromStoredResult(record['result_task_ids']);
  switch (status) {
    case 'COMPLETED':
      return _response(
        success: true,
        retryable: false,
        message: message,
        taskIds: taskIds,
      );
    case 'FAILED':
      return _response(success: false, retryable: false, message: message);
    case 'PROCESSING':
      return _retryableResponse(message);
    case 'RETRYABLE':
      return null;
    default:
      return _retryableResponse(message);
  }
}

Map<String, Object> _invalidRequestResponse() => _response(
      success: false,
      retryable: false,
      message: 'Quick capture requires a request ID and non-empty text.',
    );

Map<String, Object> _retryableResponse(String message) => _response(
      success: false,
      retryable: true,
      message: message,
    );

Map<String, Object> _response({
  required bool success,
  required bool retryable,
  required String message,
  List<String> taskIds = const [],
}) =>
    QuickCaptureResponse(
      success: success,
      retryable: retryable,
      message: message,
      taskId: taskIds.length == 1 ? taskIds.single : null,
      taskIds: taskIds.length > 1 ? taskIds : null,
    ).toMethodChannelResult();

List<String> _taskIdsFromStoredResult(Object? stored) {
  if (stored is! String) return const [];
  try {
    final decoded = jsonDecode(stored);
    return decoded is List
        ? decoded.whereType<String>().toList()
        : const <String>[];
  } on FormatException {
    return const [];
  }
}
