import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'assistant_executor.dart';
import 'database_helper.dart';
import '../data/models/task.dart';
import '../models/execution_result.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    DartPluginRegistrant.ensureInitialized();
    await NotificationService.initialize(isHeadless: true);

    if ((response.actionId == 'reply_action' ||
            response.actionId == 'reply_action_v2') &&
        response.input != null) {
      final userInput = response.input!;

      // Immediately acknowledge the action so Android can release the input UI.
      await NotificationService.showProcessingNotification(userInput);

      // Defer database and NLP initialization until after the acknowledgement.
      await DatabaseHelper.instance.database;
      final result =
          await AssistantExecutor.instance.executeVoiceCommand(userInput);

      await NotificationService.showPersistentInputNotification(isHeadless: true);
      await NotificationService.showAssistantFeedback(result);
    }

    final payload = response.payload;
    if (payload != null && payload.startsWith('task_')) {
      final taskId = payload.replaceFirst('task_', '');

      await DatabaseHelper.instance.database;

      if (response.actionId == 'mark_done') {
        await DatabaseHelper.instance.updateTaskStatus(taskId, 'COMPLETED');
      } else if (response.actionId == 'mark_missed') {
        await DatabaseHelper.instance.updateTaskStatus(taskId, 'MISSED');
      }

      if (response.id != null &&
          (response.actionId == 'mark_done' ||
              response.actionId == 'mark_missed')) {
        await NotificationService.cancel(response.id!);
      }
    }
  } catch (error, stackTrace) {
    debugPrint('Background notification isolate failed: $error');
    debugPrintStack(stackTrace: stackTrace);

    await NotificationService.showPersistentInputNotification(isHeadless: true);
    await NotificationService.showIsolateCrash(error.toString());
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize({bool isHeadless = false}) async {
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

      if (!isHeadless) {
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
      }

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

  static Future<void> showPersistentInputNotification({bool isHeadless = false}) async {
    final androidImplementation = _androidImplementation;
    if (androidImplementation != null && !isHeadless) {
      await _requestAndroidNotificationPermission(androidImplementation);
    }

    const AndroidNotificationAction replyAction = AndroidNotificationAction(
      'reply_action',
      'Add Task',
      inputs: [
        AndroidNotificationActionInput(
          label: 'e.g. Call mom at 7:30',
        ),
      ],
      allowGeneratedReplies: true,
      cancelNotification: false,
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
      'What needs to be done?',
      const NotificationDetails(android: androidDetails),
    );
  }

  static Future<void> showProcessingNotification(String input) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'persistent_channel',
      'Assistant Overlay',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      indeterminate: true,
    );

    await _notifications.show(
      0,
      'Processing Command...',
      '"$input"',
      const NotificationDetails(android: androidDetails),
    );
  }

  static Future<void> showAssistantFeedback(ExecutionResult result) async {
    final taskTitle = result.affectedTasks.isNotEmpty
        ? result.affectedTasks.first['title']?.toString()
        : null;
    final title = taskTitle == null || taskTitle.trim().isEmpty
        ? 'Noted'
        : 'Noted $taskTitle';

    await _notifications.show(
      DateTime.now().microsecondsSinceEpoch.remainder(1 << 31),
      title,
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

  static Future<void> showIsolateCrash(String error) async {
    await _notifications.show(
      9999,
      'Isolate Crash',
      error,
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

  static Future<void> cancel(int notificationId) =>
      _notifications.cancel(notificationId);

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
