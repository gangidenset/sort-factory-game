import '../../data/progress_controller.dart';
import '../analytics/analytics.dart';
import 'reminder_planner.dart';
import 'reminder_service.dart';

/// Glue between settings, daily-puzzle progress and the notification service.
class ReminderManager {
  ReminderManager({
    required this.service,
    required this.progress,
    required this.analytics,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ReminderService service;
  final ProgressController progress;
  final Analytics analytics;
  final DateTime Function() _clock;

  bool get supported => service.supported;
  bool get enabled => progress.data.settings.reminderEnabled;
  int get hour => progress.data.settings.reminderHour;
  int get minute => progress.data.settings.reminderMinute;

  String get timeLabel => '$hour:${minute.toString().padLeft(2, '0')}';

  /// Offer reminders once, right after the first daily clear.
  bool get shouldOffer =>
      supported && !enabled && !progress.data.settings.reminderAsked;

  Future<void> start() async {
    await service.init(
      onOpened: () => analytics.log('reminder_open', {'cold': false}),
    );
    if (await service.launchedFromReminder()) {
      analytics.log('reminder_open', {'cold': true});
    }
    await refresh();
  }

  /// Re-plans the coming week (call on start, after a daily clear and after
  /// any settings change).
  Future<void> refresh() async {
    if (!supported) return;
    if (!enabled) {
      await service.cancelAll();
      return;
    }
    await service.replaceSchedule(
      ReminderPlanner.plan(
        now: _clock(),
        hour: hour,
        minute: minute,
        todaySolved: progress.todaysPuzzleSolved,
        streak: progress.dailyStreak,
      ),
    );
  }

  /// Turns reminders on (asking the OS first). Returns whether it worked.
  Future<bool> enable() async {
    final granted = await service.requestPermission();
    await progress.updateSettings((s) {
      s.reminderAsked = true;
      s.reminderEnabled = granted;
    });
    analytics.log('reminder_opt_in', {'granted': granted});
    await refresh();
    return granted;
  }

  Future<void> decline() async {
    await progress.updateSettings((s) => s.reminderAsked = true);
    analytics.log('reminder_declined');
  }

  Future<void> disable() async {
    await progress.updateSettings((s) {
      s.reminderAsked = true;
      s.reminderEnabled = false;
    });
    analytics.log('reminder_opt_out');
    await refresh();
  }

  Future<void> setTime(int hour, int minute) async {
    await progress.updateSettings((s) {
      s.reminderHour = hour.clamp(0, 23);
      s.reminderMinute = minute.clamp(0, 59);
    });
    analytics.log('reminder_time', {'hour': hour, 'minute': minute});
    await refresh();
  }
}
