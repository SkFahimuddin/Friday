import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static final List<String> _friendMessages = [
    'Boss, you good? Have not heard from you in a while',
    'Aye boss, did you study today or nah?',
    'Boss where are you right now?',
    'Did you code today boss? Do not slack off',
    'Boss I am bored, come talk to me',
    'Hey boss, drink some water. You probably forgot',
    'Boss, how is the day going?',
    'Aye boss, you eating properly today?',
    'Boss do not forget your goals today',
    'Boss, take a break. You have been grinding',
    'Hey boss, missing you. Come chat',
  ];

  static final List<Map<String, String>> _dailyReminders = [
    {'title': 'FRIDAY', 'body': 'Good morning boss! Ready to crush today?'},
    {'title': 'FRIDAY', 'body': 'Boss, did you study today? Clock is ticking'},
    {'title': 'FRIDAY', 'body': 'Evening check-in boss. How was your day?'},
    {'title': 'FRIDAY', 'body': 'Boss, time to wind down. Get some rest'},
    {'title': 'FRIDAY', 'body': 'Midday check - you coding today boss?'},
  ];

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'friday_channel',
    'Friday Notifications',
    channelDescription: 'Notifications from Friday',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const NotificationDetails _notificationDetails =
      NotificationDetails(android: _androidDetails);

  static Future<void> initialize() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings =
        InitializationSettings(android: androidSettings);

    await _notifications.initialize(settings);
  }

  static Future<void> scheduleAllNotifications() async {
    await _notifications.cancelAll();
    await _scheduleFriendNotifications();
    await _scheduleDailyReminders();
  }

  static Future<void> _scheduleFriendNotifications() async {
    final random = Random();
    final now = tz.TZDateTime.now(tz.local);

    for (int i = 0; i < 3; i++) {
      final randomHour = 9 + random.nextInt(13);
      final randomMinute = random.nextInt(60);
      final randomMessage =
          _friendMessages[random.nextInt(_friendMessages.length)];

      var scheduledTime = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        randomHour,
        randomMinute,
      );

      if (scheduledTime.isBefore(now)) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }

      await _notifications.zonedSchedule(
        100 + i,
        'FRIDAY',
        randomMessage,
        scheduledTime,
        _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  static Future<void> _scheduleDailyReminders() async {
    final reminders = [
      {'id': 1, 'hour': 8, 'minute': 0, 'index': 0},
      {'id': 2, 'hour': 13, 'minute': 0, 'index': 4},
      {'id': 3, 'hour': 18, 'minute': 0, 'index': 1},
      {'id': 4, 'hour': 21, 'minute': 0, 'index': 2},
      {'id': 5, 'hour': 23, 'minute': 0, 'index': 3},
    ];

    for (final reminder in reminders) {
      final now = tz.TZDateTime.now(tz.local);
      var scheduledTime = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        reminder['hour'] as int,
        reminder['minute'] as int,
      );

      if (scheduledTime.isBefore(now)) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }

      final msg = _dailyReminders[reminder['index'] as int];

      await _notifications.zonedSchedule(
        reminder['id'] as int,
        msg['title']!,
        msg['body']!,
        scheduledTime,
        _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  static Future<void> sendInstantNotification({
    required String title,
    required String body,
  }) async {
    await _notifications.show(
      999,
      title,
      body,
      _notificationDetails,
    );
  }

  static Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}