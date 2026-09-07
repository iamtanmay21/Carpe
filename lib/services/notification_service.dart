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
  void trace(String step) {
    debugPrint('[CARPE_TRACE ${DateTime.now().toIso8601String()}] $step');
  }

  trace('1. Background callback entered (actionId: ${response.actionId})');
  WidgetsFlutterBinding.ensureInitialized();

  try {
    trace('2. DartPluginRegistrant initializing');
    DartPluginRegistrant.ensureInitialized();

    trace('3. NotificationService initializing');
    await NotificationService.initialize(isHeadless: true);

    if ((response.actionId == 'reply_action' ||
            response.actionId == 'reply_action_v2') &&
        response.input != null) {
      final userInput = response.input!;
      trace('4. RemoteInput received: "$userInput"');

      // Immediately acknowledge the action so Android can release the input UI.
      trace('5. Showing Processing notification');
      await NotificationService.showProcessingNotification(userInput);

      // Defer database and NLP initialization until after the acknowledgement.
      trace('6. Loading database');
      await DatabaseHelper.instance.database;

      trace('7. Executing assistant command');
      final result =
          await AssistantExecutor.instance.executeVoiceCommand(userInput);

      trace('8. Clearing processing notification');
      await NotificationService.cancel(999);

      trace('9. Reposting persistent notification');
      await NotificationService.showPersistentInputNotification(isHeadless: true);

      trace('10. Showing assistant feedback');
      await NotificationService.showAssistantFeedback(result);
      trace('11. Background sequence completed successfully');
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

      if (response.id != null) {
        await NotificationService.cancel(response.id!);
      }
    }
  } catch (error, stackTrace) {
    trace('CRASH in isolate: $error');
    debugPrint('Background notification isolate failed: $error');
    debugPrintStack(stackTrace: stackTrace);

    // Ensure a processing notification cannot remain stranded after a failure.
    await NotificationService.cancel(999);
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
    const AndroidNotificationAction replyAction = AndroidNotificationAction(
      'reply_action_test',
      'Add Task',
      inputs: [
        AndroidNotificationActionInput(
          label: 'Type test task here...',
        ),
      ],
      allowGeneratedReplies: true,
      cancelNotification: false, // Prevent plugin from deleting it on empty clicks
    );

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'ui_test_channel_v1', // BRAND NEW ID so Android doesn't use the old Low-Importance cache
      'UI Test Channel',
      importance: Importance.max, // Force MIUI to respect the UI overlay
      priority: Priority.max,
      ongoing: false, // Turn off persistent lock to test MIUI's keyboard rendering
      autoCancel: false,
      actions: [replyAction],
    );

    await _notifications.show(
      888, // Unique ID
      'Carpe Diem UI Test',
      'Can you open the keyboard?',
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
      999,
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
