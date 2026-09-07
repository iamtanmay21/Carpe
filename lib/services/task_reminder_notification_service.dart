import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../data/models/task.dart';
import 'database_helper.dart';

/// Local notifications for scheduled task reminders only.
///
/// Native Android owns quick capture so reminder notifications cannot replace
/// its persistent notification, channel, or notification ID.
class TaskReminderNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    tz.initializeTimeZones();

    const androidInitialization =
        AndroidInitializationSettings('@drawable/ic_notification');
    await _notifications.initialize(
      const InitializationSettings(android: androidInitialization),
      onDidReceiveNotificationResponse: taskReminderNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          taskReminderNotificationResponse,
    );

    final androidImplementation = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation == null) return;

    await androidImplementation.requestNotificationsPermission();
    await androidImplementation.requestExactAlarmsPermission();
    await androidImplementation.createNotificationChannel(_taskChannel);
  }

  static Future<void> cancel(int notificationId) =>
      _notifications.cancel(notificationId);

  static Future<void> scheduleTaskReminder(Task task) async {
    final scheduledDate = tz.TZDateTime.fromMillisecondsSinceEpoch(
      tz.local,
      task.dueTimestamp,
    );
    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) return;

    await _notifications.zonedSchedule(
      task.id.hashCode,
      'Task Reminder',
      task.title,
      scheduledDate,
      const NotificationDetails(android: _taskDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'task_${task.id}',
    );
  }

  static const AndroidNotificationChannel _taskChannel =
      AndroidNotificationChannel(
    'task_reminders',
    'Task Reminders',
    description: 'High priority alerts for task deadlines.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationDetails _taskDetails =
      AndroidNotificationDetails(
    'task_reminders',
    'Task Reminders',
    importance: Importance.max,
    priority: Priority.max,
    actions: <AndroidNotificationAction>[
      AndroidNotificationAction('mark_done', 'Done', showsUserInterface: false),
      AndroidNotificationAction(
        'mark_missed',
        'Missed',
        showsUserInterface: false,
      ),
    ],
  );
}

/// Handles task-reminder actions in either the UI or background isolate.
@pragma('vm:entry-point')
Future<void> taskReminderNotificationResponse(NotificationResponse response) async {
  final payload = response.payload;
  if (payload == null || !payload.startsWith('task_')) return;

  final status = switch (response.actionId) {
    'mark_done' => 'COMPLETED',
    'mark_missed' => 'MISSED',
    _ => null,
  };
  if (status == null) return;

  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await DatabaseHelper.instance.database;
  await DatabaseHelper.instance
      .updateTaskStatus(payload.replaceFirst('task_', ''), status);
  if (response.id != null) {
    await TaskReminderNotificationService.cancel(response.id!);
  }
}
