/// Shared wire contract for Android's notification quick-capture flow.
///
/// **Keep every constant in this file synchronized with**
/// `android/app/src/main/kotlin/com/local/carpe/QuickCaptureContract.kt`.
/// Pending notification actions and MethodChannel calls can outlive an app
/// update, so changing a value requires a coordinated Android and Dart change.
library;

/// Names and values shared between Android notification code and Dart.
abstract final class QuickCaptureContract {
  static const String notificationChannelId = 'carpe_direct_reply';
  static const int notificationId = 4100;
  static const String replyActionId = 'carpe_direct_reply_action';
  static const String remoteInputResultKey = 'carpe_direct_reply_text';

  static const String methodChannelName = 'com.local.carpe/quick_capture';
  static const String processQuickCaptureMethod = 'processQuickCapture';

  static const String requestIdKey = 'requestId';
  static const String textKey = 'text';
  static const String submittedAtKey = 'submittedAt';
  static const String metadataKey = 'metadata';

  /// Dart invokes this on the shared channel once the headless isolate can
  /// receive [processQuickCaptureMethod].
  static const String dartReadyMethod = 'quickCaptureReady';

  static const String successKey = 'success';
  static const String retryableKey = 'retryable';
  static const String messageKey = 'message';
  static const String taskIdKey = 'taskId';
  static const String taskIdsKey = 'taskIds';

  /// Notification state machine: show [readyState] with inline input; replace
  /// it with [processingState] immediately after a reply; then return to
  /// [readyState] after success or a recoverable failure.
  static const String readyState = 'ready';
  static const String processingState = 'processing';
}

/// Kotlin-to-Dart payload for `processQuickCapture`.
///
/// [requestId] is an idempotency key: Android must reuse it for intent
/// redelivery and WorkManager retries. [submittedAt] is when Android received
/// the reply, encoded as Unix milliseconds.
final class QuickCaptureRequest {
  const QuickCaptureRequest({
    required this.requestId,
    required this.text,
    required this.submittedAt,
    this.metadata,
  });

  factory QuickCaptureRequest.fromMethodCall(Map<Object?, Object?> arguments) {
    final requestId = arguments[QuickCaptureContract.requestIdKey];
    final text = arguments[QuickCaptureContract.textKey];
    final submittedAt = arguments[QuickCaptureContract.submittedAtKey];

    if (requestId is! String || text is! String || submittedAt is! num) {
      throw ArgumentError.value(
        arguments,
        'arguments',
        'processQuickCapture requires requestId, text, and submittedAt.',
      );
    }

    return QuickCaptureRequest(
      requestId: requestId,
      text: text,
      submittedAt: DateTime.fromMillisecondsSinceEpoch(submittedAt.toInt()),
      metadata: arguments[QuickCaptureContract.metadataKey] as String?,
    );
  }

  final String requestId;
  final String text;
  final DateTime submittedAt;
  /// Opaque Android delivery context. It is intentionally not persisted by
  /// Kotlin; Dart remains the only database owner.
  final String? metadata;

  Map<String, Object> toMethodChannelArguments() {
    final arguments = <String, Object>{
      QuickCaptureContract.requestIdKey: requestId,
      QuickCaptureContract.textKey: text,
      QuickCaptureContract.submittedAtKey: submittedAt.millisecondsSinceEpoch,
    };
    if (metadata != null) arguments[QuickCaptureContract.metadataKey] = metadata!;
    return arguments;
  }
}

/// Structured response returned to Android after `processQuickCapture`.
///
/// When [success] is false, Android retries only if [retryable] is true. A
/// success response may identify one task with [taskId], several with
/// [taskIds], or neither when no task identifier is available.
final class QuickCaptureResponse {
  const QuickCaptureResponse({
    required this.success,
    required this.retryable,
    required this.message,
    this.taskId,
    this.taskIds,
  });

  final bool success;
  final bool retryable;
  final String message;
  final String? taskId;
  final List<String>? taskIds;

  Map<String, Object> toMethodChannelResult() {
    final result = <String, Object>{
      QuickCaptureContract.successKey: success,
      QuickCaptureContract.retryableKey: retryable,
      QuickCaptureContract.messageKey: message,
    };
    if (taskId != null) result[QuickCaptureContract.taskIdKey] = taskId!;
    if (taskIds != null) result[QuickCaptureContract.taskIdsKey] = taskIds!;
    return result;
  }
}
