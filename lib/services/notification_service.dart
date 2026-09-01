import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'assistant_executor.dart';
import 'database_helper.dart';
import '../data/models/task.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  await DatabaseHelper.instance.database;

  // Handle persistent text input without requiring the application UI to open.
  if (response.actionId == 'reply_action' && response.input != null) {
    final result =
        await AssistantExecutor.instance.executeVoiceCommand(response.input!);
    final FlutterLocalNotificationsPlugin flnp =
        FlutterLocalNotificationsPlugin();
    await flnp.show(
      DateTime.now().millisecond,
      'Carpe Diem',
      result.feedbackMessage,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'feedback_channel',
          'Feedback',
          importance: Importance.high,
        ),
      ),
    );
  }

  // Handle task reminder actions without requiring the application UI to open.
  final payload = response.payload;
  if (payload != null && payload.startsWith('task_')) {
    final taskId = payload.replaceFirst('task_', '');

    if (response.actionId == 'mark_done') {
      await DatabaseHelper.instance.updateTaskStatus(taskId, 'COMPLETED');
    } else if (response.actionId == 'mark_missed') {
      await DatabaseHelper.instance.updateTaskStatus(taskId, 'MISSED');
    }

    // Both task actions are terminal, so remove the reminder once processed.
    if (response.id != null &&
        (response.actionId == 'mark_done' ||
            response.actionId == 'mark_missed')) {
      final FlutterLocalNotificationsPlugin flnp =
          FlutterLocalNotificationsPlugin();
      await flnp.cancel(response.id!);
    }
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    try {
      // Use the launcher icon until a dedicated transparent notification icon
      // is added under android/app/src/main/res/drawable/.
      const AndroidInitializationSettings androidInitializationSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: androidInitializationSettings);

      await _notifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: notificationTapBackground,
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );

      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation == null) {
        return;
      }

      // Android 13+ requires notification permission at runtime. Exact-alarm
      // permission is required for time-sensitive scheduled task reminders.
      await androidImplementation.requestNotificationsPermission();
      await androidImplementation.requestExactAlarmsPermission();

      const AndroidNotificationChannel taskChannel = AndroidNotificationChannel(
        'task_reminders',
        'Task Reminders',
        description: 'High priority alerts for task deadlines.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      const AndroidNotificationChannel feedbackChannel =
          AndroidNotificationChannel(
        'feedback_channel',
        'Assistant Feedback',
        description: 'Persistent background assistant.',
        importance: Importance.high,
      );

      await androidImplementation.createNotificationChannel(taskChannel);
      await androidImplementation.createNotificationChannel(feedbackChannel);
    } catch (error, stackTrace) {
      debugPrint('Notification initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<void> showPersistentInputNotification() async {
    const AndroidNotificationAction replyAction = AndroidNotificationAction(
      'reply_action',
      'Add Task',
      inputs: [
        AndroidNotificationActionInput(
          label: 'Type task... e.g. Buy milk tomorrow',
        ),
      ],
      allowGeneratedReplies: true,
    );
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'persistent_channel',
      'Assistant Overlay',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      actions: [replyAction],
    );
    await _notifications.show(
      0,
      'Carpe Diem',
      'Assistant is ready',
      const NotificationDetails(android: androidDetails),
    );
  }

  /// Shows the actionable notification delivered when a task reminder fires.
  static Future<void> showTaskReminder(Task task) async {
    const androidDetails = AndroidNotificationDetails(
      'task_reminders',
      'Task Reminders',
      importance: Importance.max,
      priority: Priority.max,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'mark_done',
          'Done',
          showsUserInterface: false,
        ),
        AndroidNotificationAction(
          'mark_missed',
          'Missed',
          showsUserInterface: false,
        ),
      ],
    );

    await _notifications.show(
      task.id.hashCode,
      'Task Reminder',
      task.title,
      const NotificationDetails(android: androidDetails),
      payload: 'task_${task.id}',
    );
  }
}
