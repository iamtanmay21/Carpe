import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'assistant_executor.dart';
import 'database_helper.dart';

const String _notificationChannelId = 'carpe_direct_reply';
const int _notificationId = 4100;
const String _directReplyActionId = 'carpe_direct_reply_action';

final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();

/// Configures the Android foreground service and persistent notification that
/// lets users create tasks without opening the Flutter UI.
Future<void> initializeBackgroundDirectReplyNotification() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initializeLocalNotifications();

  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: directReplyBackgroundServiceEntryPoint,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: _notificationChannelId,
      initialNotificationTitle: 'Carpe Diem quick capture',
      initialNotificationContent: 'Reply here to create a task',
      foregroundServiceNotificationId: _notificationId,
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );

  await service.startService();
  await showDirectReplyNotification();
}

@pragma('vm:entry-point')
Future<void> directReplyBackgroundServiceEntryPoint(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  await _initializeLocalNotifications();
  await DatabaseHelper.instance.database;

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
    await showDirectReplyNotification();
  }

  service.on('directReply').listen((event) async {
    final text = event?['text'] as String?;
    if (text != null) {
      await handleNotificationDirectReply(text);
    }
  });
}

Future<void> _initializeLocalNotifications() async {
  const androidInitialization = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initializationSettings = InitializationSettings(android: androidInitialization);

  await _notifications.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: notificationDirectReplyCallback,
    onDidReceiveBackgroundNotificationResponse: notificationDirectReplyCallback,
  );

  final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      _notificationChannelId,
      'Carpe direct reply',
      description: 'Persistent notification for background task capture.',
      importance: Importance.low,
    ),
  );
}

Future<void> showDirectReplyNotification() async {
  const androidDetails = AndroidNotificationDetails(
    _notificationChannelId,
    'Carpe direct reply',
    channelDescription: 'Persistent notification for background task capture.',
    importance: Importance.low,
    priority: Priority.low,
    ongoing: true,
    autoCancel: false,
    onlyAlertOnce: true,
    category: AndroidNotificationCategory.service,
    actions: <AndroidNotificationAction>[
      AndroidNotificationAction(
        _directReplyActionId,
        'Add task',
        showsUserInterface: false,
        inputs: <AndroidNotificationActionInput>[
          AndroidNotificationActionInput(
            label: 'Type a task for Carpe Diem',
            allowFreeFormInput: true,
          ),
        ],
      ),
    ],
  );

  await _notifications.show(
    _notificationId,
    'Carpe Diem quick capture',
    'Reply here to create a task',
    const NotificationDetails(android: androidDetails),
  );
}

/// Entry point invoked by flutter_local_notifications when Android delivers a
/// NotificationCompat.Action RemoteInput result while the app UI is absent.
@pragma('vm:entry-point')
Future<void> notificationDirectReplyCallback(NotificationResponse response) async {
  if (response.actionId != _directReplyActionId) return;

  final text = response.input?.trim();
  if (text == null || text.isEmpty) return;

  await handleNotificationDirectReply(text);
}

/// Creates or updates tasks silently from notification tray text input.
@pragma('vm:entry-point')
Future<void> handleNotificationDirectReply(String text) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  await DatabaseHelper.instance.database;
  await AssistantExecutor.instance.executeVoiceCommand(text);
  await showDirectReplyNotification();
}
