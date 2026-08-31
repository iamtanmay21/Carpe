import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'assistant_executor.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();

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
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const AndroidInitializationSettings initAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(
      const InitializationSettings(android: initAndroid),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
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
}
