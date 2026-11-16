import '../../game/logic/daily.dart';

/// One scheduled local notification.
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
  });

  final int id;

  /// Local wall-clock time.
  final DateTime when;
  final String title;
  final String body;

  @override
  String toString() => 'Reminder($id, $when, $body)';
}

/// Decides when daily-puzzle reminders fire and what they say. Pure, so the
/// rules are unit-tested; the platform service only delivers the plan.
///
/// Rules:
/// * one reminder per day at the chosen time, for the next [days] days
///   (re-planned on every app start and after each daily clear, so it keeps
///   rolling forward while the player is active and stops after a week of
///   inactivity instead of nagging forever);
/// * no reminder today if today's puzzle is already solved or the time has
///   passed;
/// * the next reminder mentions the running streak.
class ReminderPlanner {
  const ReminderPlanner._();

  static const days = 7;
  static const baseId = 1000;

  static List<PlannedReminder> plan({
    required DateTime now,
    required int hour,
    required int minute,
    required bool todaySolved,
    required int streak,
  }) {
    final out = <PlannedReminder>[];
    for (var k = 0; k < days; k++) {
      // DateTime normalizes day overflow and applies local DST rules.
      final when = DateTime(now.year, now.month, now.day + k, hour, minute);
      if (k == 0 && (todaySolved || !when.isAfter(now))) continue;
      final first = out.isEmpty;
      // Streak the player keeps alive by solving on that day.
      final alive = k == 0 ? streak : (todaySolved ? streak : 0);
      out.add(
        PlannedReminder(
          id: baseId + k,
          when: when,
          title: first && alive > 0 ? '🔥 $alive日連続中！' : '今日のパズルが届きました',
          body: first && alive > 0
              ? '今日のパズルを解いて記録をのばそう（${_level(when)}）'
              : '${DailyCatalog.weekdayNames[when.weekday - 1]}曜日は「${_level(when)}」。1問だけ解いてみませんか？',
        ),
      );
    }
    return out;
  }

  static String _level(DateTime d) => DailyCatalog.levelOf(d);
}
