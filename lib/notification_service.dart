import 'dart:math';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

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

  // Generate a fresh message using Groq
  static Future<String> _generateFriendMessage() async {
    try {
      final apiKey = dotenv.env['GROQ_API_KEY'] ?? '';
      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'llama-3.3-70b-versatile',
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are Friday, a personal AI assistant and friend. Generate a single short casual message to send as a notification to your user. Call them boss. Be informal, funny, sometimes roasting, sometimes caring, sometimes random like a real friend would text. Keep it under 15 words. No quotes, no explanation, just the message itself.'
            },
            {
              'role': 'user',
              'content': 'Generate a random casual notification message for boss right now.'
            }
          ],
          'max_tokens': 50,
          'temperature': 1.0,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'].trim();
      }
    } catch (e) {
      // fallback messages if Groq fails
    }

    // Fallback messages if no internet
    final fallbacks = [
      'Boss, you good? Come chat with me',
      'Aye boss, still alive out there?',
      'Boss do not forget about me',
      'Hey boss, missing you. Come talk',
      'Boss, take a break and chat with Friday',
    ];
    return fallbacks[Random().nextInt(fallbacks.length)];
  }

  static Future<void> scheduleAllNotifications() async {
    await _notifications.cancelAll();
    await _scheduleSmartNotifications();
  }

  static Future<void> _scheduleSmartNotifications() async {
    final random = Random();
    final now = tz.TZDateTime.now(tz.local);

    // Active hours: 8am to 12am (midnight)
    // Total active minutes: 16 hours = 960 minutes
    // 20 notifications spread randomly across 960 minutes

    // Generate 20 unique random times
    final Set<int> usedMinutes = {};
    final List<int> randomMinutesFromMidnight = [];

    while (randomMinutesFromMidnight.length < 20) {
      // Random minute between 8am (480 min) and 12am (1440 min)
      final minute = 480 + random.nextInt(960);
      if (!usedMinutes.contains(minute)) {
        usedMinutes.add(minute);
        randomMinutesFromMidnight.add(minute);
      }
    }

    randomMinutesFromMidnight.sort();

    for (int i = 0; i < randomMinutesFromMidnight.length; i++) {
      final totalMinutes = randomMinutesFromMidnight[i];
      final hour = totalMinutes ~/ 60;
      final minute = totalMinutes % 60;

      var scheduledTime = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      if (scheduledTime.isBefore(now)) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }

      // Generate AI message for each notification
      final message = await _generateFriendMessage();

      await _notifications.zonedSchedule(
        200 + i,
        'FRIDAY',
        message,
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

  // Test with AI generated message
  static Future<void> sendAITestNotification() async {
    final message = await _generateFriendMessage();
    await _notifications.show(
      998,
      'FRIDAY',
      message,
      _notificationDetails,
    );
  }

  static Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}