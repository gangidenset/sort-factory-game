import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'reminder_planner.dart';

/// Platform layer for local reminder notifications.
abstract class ReminderService {
  /// False on platforms without scheduled local notifications (web, tests).
  bool get supported;

  Future<void> init({void Function()? onOpened});

  /// Asks the OS for permission. True if notifications may be shown.
  Future<bool> requestPermission();

  /// Cancels everything and schedules [plan].
  Future<void> replaceSchedule(List<PlannedReminder> plan);

  Future<void> cancelAll();

  /// Whether this app launch came from tapping a reminder.
  Future<bool> launchedFromReminder();
}

class NoReminderService implements ReminderService {
  @override
  bool get supported => false;
  @override
  Future<void> init({void Function()? onOpened}) async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> replaceSchedule(List<PlannedReminder> plan) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Future<bool> launchedFromReminder() async => false;
}

/// flutter_local_notifications implementation (Android / iOS).
///
/// Reminders are one-shot notifications for the next few days rather than a
/// repeating rule, so a day whose puzzle is already solved can be skipped.
/// Times are planned in local wall-clock time by [ReminderPlanner] and
/// converted to an absolute instant here, so no time-zone database is needed.
class LocalReminderService implements ReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'daily_puzzle',
      '今日のパズル',
      channelDescription: '毎日のパズルのお知らせ',
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  bool get supported => true;

  @override
  Future<void> init({void Function()? onOpened}) async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Permission is requested later, only after the player opts in.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (_) => onOpened?.call(),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifications init failed: $e');
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        final granted = await android.requestNotificationsPermission();
        return granted ?? await android.areNotificationsEnabled() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, sound: true) ?? false;
      }
    } catch (e) {
      debugPrint('Notification permission failed: $e');
    }
    return false;
  }

  @override
  Future<void> replaceSchedule(List<PlannedReminder> plan) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      for (final r in plan) {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.when, tz.UTC),
          notificationDetails: _details,
          // Inexact is fine for a daily nudge and needs no special permission.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'daily',
        );
      }
    } catch (e) {
      debugPrint('Scheduling reminders failed: $e');
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  @override
  Future<bool> launchedFromReminder() async {
    if (!_ready) return false;
    try {
      final d = await _plugin.getNotificationAppLaunchDetails();
      return d?.didNotificationLaunchApp ?? false;
    } catch (_) {
      return false;
    }
  }
}
