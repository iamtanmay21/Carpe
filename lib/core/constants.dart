
/// Carpe Diem — Channel Constants
/// These names MUST match exactly what the Kotlin developer uses
/// in android/app/src/main/kotlin/com/local/carpe/
library;

class AppChannels {
  AppChannels._();

  /// MethodChannel: Dart → Kotlin
  /// Used to trigger the native Android ConnectionService call screen
  /// and to disconnect it.
  static const String telephonyChannel = 'com.local.carpe/telephony';

  /// EventChannel: Kotlin → Dart
  /// The Kotlin call screen sends raw DTMF digit strings on this channel.
  /// Possible values: '0'-'9', '#', '*', 'MISSED', 'DISMISSED'
  static const String dtmfEventsChannel = 'com.local.carpe/dtmf_events';
}

/// MethodChannel method names (Dart → Kotlin)
class TelephonyMethods {
  TelephonyMethods._();

  /// Tells Kotlin to show the real Android ringing screen.
  /// Arguments: Map<String, dynamic> { 'taskId': String, 'title': String, 'audioPath': String? }
  static const String triggerIncomingCall = 'triggerIncomingCall';

  /// Tells Kotlin to hang up / dismiss the call screen.
  static const String disconnectCall = 'disconnectCall';
}

/// Task status values stored in SQLite
class TaskStatus {
  TaskStatus._();

  static const String pending = 'PENDING';
  static const String accepted = 'ACCEPTED';
  static const String snoozed = 'SNOOZED';
  static const String completed = 'COMPLETED';
  static const String missed = 'MISSED';
}