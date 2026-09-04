import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'assistant_executor.dart';
import 'database_helper.dart';
import '../data/models/task.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  await DatabaseHelper.instance.database;

  if (response.actionId == 'reply_action' && response.input != null) {
    final result = await AssistantExecutor.instance.executeVoiceCommand(response.input!);
    final FlutterLocalNotificationsPlugin flnp = FlutterLocalNotificationsPlugin();
    await flnp.show(
      DateTime.now().millisecond,
      'Carpe Diem',
      result.feedbackMessage,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'feedback_channel',
          'Assistant Feedback',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  final payload = response.payload;
  if (payload != null && payload.startsWith('task_')) {
    final taskId = payload.replaceFirst('task_', '');

    if (response.actionId == 'mark_done') {
      await DatabaseHelper.instance.updateTaskStatus(taskId, 'COMPLETED');
    } else if (response.actionId == 'mark_missed') {
      await DatabaseHelper.instance.updateTaskStatus(taskId, 'MISSED');
    }

    if (response.id != null &&
        (response.actionId == 'mark_done' || response.actionId == 'mark_missed')) {
      final FlutterLocalNotificationsPlugin flnp = FlutterLocalNotificationsPlugin();
      await flnp.cancel(response.id!);
    }
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    try {
      tz.initializeTimeZones();

      const AndroidInitializationSettings androidInitSettings =
          AndroidInitializationSettings('@drawable/ic_notification');
      const InitializationSettings initSettings =
          InitializationSettings(android: androidInitSettings);

      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: notificationTapBackground,
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );

      final androidImplementation = _androidImplementation;

      if (androidImplementation == null) return;

      // Request this before any notification is shown, including the persistent
      // input notification that is displayed immediately after initialization.
      final notificationPermissionGranted =
          await _requestAndroidNotificationPermission(androidImplementation);
      if (notificationPermissionGranted != true) {
        debugPrint(
          'CRITICAL: Notification permission was not granted; aborting notification channel creation.',
        );
        return;
      }
      await androidImplementation.requestExactAlarmsPermission();

      const AndroidNotificationChannel taskChannel = AndroidNotificationChannel(
        'task_reminders',
        'Task Reminders',
        description: 'High priority alerts for task deadlines.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      const AndroidNotificationChannel feedbackChannel = AndroidNotificationChannel(
        'feedback_channel',
        'Assistant Feedback',
        description: 'Persistent background assistant feedback.',
        importance: Importance.high,
      );

      const AndroidNotificationChannel persistentChannel = AndroidNotificationChannel(
        'persistent_channel',
        'Assistant Overlay',
        description: 'Ongoing background assistant bar.',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      );

      await androidImplementation.createNotificationChannel(taskChannel);
      await androidImplementation.createNotificationChannel(feedbackChannel);
      await androidImplementation.createNotificationChannel(persistentChannel);
    } catch (error, stackTrace) {
      debugPrint('Notification initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  static Future<void> showPersistentInputNotification() async {
    final androidImplementation = _androidImplementation;
    if (androidImplementation != null) {
      await _requestAndroidNotificationPermission(androidImplementation);
    }

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

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
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

  static AndroidFlutterLocalNotificationsPlugin?
      get _androidImplementation =>
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

  static Future<bool?> _requestAndroidNotificationPermission(
    AndroidFlutterLocalNotificationsPlugin androidImplementation,
  ) async {
    return androidImplementation.requestNotificationsPermission();
  }

  static Future<void> showTaskReminder(Task task) async {
    const androidDetails = AndroidNotificationDetails(
      'task_reminders',
      'Task Reminders',
      importance: Importance.max,
      priority: Priority.max,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('mark_done', 'Done', showsUserInterface: false),
        AndroidNotificationAction('mark_missed', 'Missed', showsUserInterface: false),
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

  static Future<void> scheduleTaskReminder(Task task) async {
    final scheduledDate = tz.TZDateTime.fromMillisecondsSinceEpoch(
      tz.local,
      task.dueTimestamp,
    );

    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) return;

    const androidDetails = AndroidNotificationDetails(
      'task_reminders',
      'Task Reminders',
      importance: Importance.max,
      priority: Priority.max,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('mark_done', 'Done', showsUserInterface: false),
        AndroidNotificationAction('mark_missed', 'Missed', showsUserInterface: false),
      ],
    );

    await _notifications.zonedSchedule(
      task.id.hashCode,
      'Task Reminder',
      task.title,
      scheduledDate,
      const NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'task_${task.id}',
    );
  }
}
