import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

class NotificationsService {
  static final _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'sleep_channel',
            'Sleep Reminders',
            importance: Importance.max,
          ),
        );

    await _notifications.initialize(settings);
  }

  static Future<bool?> requestAndroidPermissions() async {
    return await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  static Future<void> showTestNotification() async {
    print("Тестовое уведомление отправлено");
    final time = DateTime.now().add(Duration(seconds: 10));
    await _notifications.zonedSchedule(
      0,
      "Тест",
      "Крутая проверка",
      tz.TZDateTime.from(time, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          'sleep_channel',
          'Sleep Reminders',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  static Future<bool?> requestIOSPermissions() async {
    return await _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<void> openAppSettings() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final packageName = packageInfo.packageName;

      if (Platform.isAndroid) {
        try {
          final intent = AndroidIntent(
            action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
            data: 'package:$packageName',
          );
          await intent.launch();
          return;
        } catch (e) {
          print("Intent Failed: $e");
        }
      }
      if (Platform.isIOS) {
        try {
          await launchUrl(
            Uri.parse('app-settings://'),
            mode: LaunchMode.externalApplication,
          );
          return;
        } catch (e) {
          print("iOs deep link failed: $e");
        }
      }

      await launchUrl(
        Uri.parse('package:$packageName'),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      print("all method failed: $e");
    }
  }

  static Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);

    for (int i = 1; i <= 7; i++) {
      await _notifications.cancel(id + i + 1499);
    }
  }

  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required List<int> days,
  }) async {
    await cancelNotification(id);
    print("Notification: $scheduledTime");

    if (days.length == 7) {
      print("ЕЖЕДНЕВНОЕ УВЕДОМЛЕНИЕ");
      final scheduled = tz.TZDateTime.from(scheduledTime, tz.local);

      await _notifications.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'sleep_channel',
            'Sleep Reminders',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            showWhen: true,
          ),
          iOS: DarwinNotificationDetails(
            sound: 'default',
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } else if (days.isNotEmpty) {
      for (final weekday in days) {
        var scheduled = tz.TZDateTime.from(scheduledTime, tz.local);

        while (scheduled.weekday != weekday) {
          scheduled = scheduled.add(Duration(days: 1));
        }

        print("$weekday: $scheduled");

        await _notifications.zonedSchedule(
          id + weekday + 1499,
          title,
          body,
          scheduled,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'sleep_channel',
              'Sleep Reminders',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              showWhen: true,
            ),
            iOS: DarwinNotificationDetails(
              sound: 'default',
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
    } else {
      var tzTime = tz.TZDateTime.from(scheduledTime, tz.local);

      while (tzTime.isBefore(tz.TZDateTime.now(tz.local))) {
        tzTime = tzTime.add(Duration(days: 1));
      }
      await _notifications.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'sleep_channel',
            'Sleep Reminders',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            showWhen: true,
          ),
          iOS: DarwinNotificationDetails(
            sound: 'default',
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }
}
