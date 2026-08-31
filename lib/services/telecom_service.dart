import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../data/models/task.dart';

class TelecomService {
  static const MethodChannel _channel = MethodChannel('com.local.carpe/telecom');

  static Future<void> scheduleNativeAlarm(Task task) async {
    // Never hand Android a past timestamp, which AlarmManager fires immediately.
    if (task.dueDateTime.isBefore(DateTime.now()) || task.isNonPriority) {
      return;
    }

    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('scheduleAlarm', {
        'id': task.id,
        'name': task.contactName ?? task.title,
        'number': task.contactNumber ?? 'Carpe Diem',
        'audioPath': task.audioPath,
        'timestamp': task.dueTimestamp,
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to schedule alarm: '${e.message}'.");
    }
  }

  // --- NEW: Kills background alarms when a task is deleted or rescheduled ---
  static Future<void> cancelNativeAlarm(String taskId) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('cancelAlarm', {'id': taskId});
    } on PlatformException catch (e) {
      debugPrint("Failed to cancel alarm: '${e.message}'.");
    }
  }

  static Future<void> triggerCall(Task task) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('triggerCall', {
        'id': task.id,
        'name': task.contactName ?? task.title,
        'number': task.contactNumber ?? 'Carpe Diem',
        'audioPath': task.audioPath,
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to trigger call: '${e.message}'.");
    }
  }

  static Future<bool> isPhoneAccountEnabled() async {
    if (kIsWeb) return true;
    try {
      return await _channel.invokeMethod('isPhoneAccountEnabled');
    } catch (_) {
      return false;
    }
  }

  static Future<void> openTelecomSettings() async {
    if (kIsWeb) return;
    try { await _channel.invokeMethod('openTelecomSettings'); } catch (_) {}
  }

  static Future<void> openAutoStartSettings() async {
    if (kIsWeb) return;
    try { await _channel.invokeMethod('openAutoStartSettings'); } catch (_) {}
  }

  // --- BRIDGES FOR TTS & STT ---
  static Future<void> openPlayStoreForSpeechServices() async {
    if (kIsWeb) return;
    try { await _channel.invokeMethod('openPlayStoreForSpeechServices'); } catch (_) {}
  }

  static Future<void> openTTSSettings() async {
    if (kIsWeb) return;
    try { await _channel.invokeMethod('openTTSSettings'); } catch (_) {}
  }
}
