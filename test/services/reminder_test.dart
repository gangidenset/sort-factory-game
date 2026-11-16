import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/data/progress_controller.dart';
import 'package:sort_factory/data/save_data.dart';
import 'package:sort_factory/data/save_repository.dart';
import 'package:sort_factory/economy/economy.dart';
import 'package:sort_factory/services/analytics/analytics.dart';
import 'package:sort_factory/services/notifications/reminder_manager.dart';
import 'package:sort_factory/services/notifications/reminder_planner.dart';
import 'package:sort_factory/services/notifications/reminder_service.dart';

/// Records what would be scheduled on a device.
class FakeReminderService implements ReminderService {
  FakeReminderService({this.grant = true});
  bool grant;
  List<PlannedReminder> scheduled = [];
  int permissionRequests = 0;
  bool cancelled = false;

  @override
  bool get supported => true;
  @override
  Future<void> init({void Function()? onOpened}) async {}
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grant;
  }

  @override
  Future<void> replaceSchedule(List<PlannedReminder> plan) async {
    scheduled = List.of(plan);
    cancelled = false;
  }

  @override
  Future<void> cancelAll() async {
    scheduled = [];
    cancelled = true;
  }

  @override
  Future<bool> launchedFromReminder() async => false;
}

StageResult solved() => const StageResult(
  stageId: 20261116,
  cleared: true,
  score: 500,
  stars: 3,
  deliveries: 7,
  seconds: 60,
);

void main() {
  group('ReminderPlanner', () {
    // Monday 2026-11-16, 10:00.
    final morning = DateTime(2026, 11, 16, 10);

    test('one reminder per day for a week, at the chosen local time', () {
      final plan = ReminderPlanner.plan(
        now: morning,
        hour: 19,
        minute: 30,
        todaySolved: false,
        streak: 0,
      );
      expect(plan.length, 7);
      expect(plan.first.when, DateTime(2026, 11, 16, 19, 30));
      expect(plan.last.when, DateTime(2026, 11, 22, 19, 30));
      expect(plan.map((r) => r.id).toSet().length, 7);
      expect(plan.first.body, contains('月曜日'));
      expect(plan.last.body, contains('むずかしい'));
    });

    test('no reminder today once today is solved', () {
      final plan = ReminderPlanner.plan(
        now: morning,
        hour: 19,
        minute: 30,
        todaySolved: true,
        streak: 4,
      );
      expect(plan.length, 6);
      expect(plan.first.when.day, 17);
      expect(plan.first.title, contains('4日連続中'));
      expect(plan[1].title, isNot(contains('連続')));
    });

    test('no reminder today if the time has already passed', () {
      final plan = ReminderPlanner.plan(
        now: DateTime(2026, 11, 16, 21),
        hour: 19,
        minute: 30,
        todaySolved: false,
        streak: 2,
      );
      expect(plan.first.when, DateTime(2026, 11, 17, 19, 30));
    });

    test('streak at risk today is mentioned', () {
      final plan = ReminderPlanner.plan(
        now: morning,
        hour: 19,
        minute: 30,
        todaySolved: false,
        streak: 3,
      );
      expect(plan.first.title, contains('3日連続中'));
    });

    test('month and year boundaries roll over', () {
      final plan = ReminderPlanner.plan(
        now: DateTime(2026, 12, 30, 8),
        hour: 8,
        minute: 0,
        todaySolved: false,
        streak: 0,
      );
      expect(plan.first.when, DateTime(2026, 12, 31, 8));
      expect(plan[1].when, DateTime(2027, 1, 1, 8));
    });
  });

  group('ReminderManager', () {
    late ProgressController progress;
    late FakeReminderService service;
    late ReminderManager manager;
    var now = DateTime(2026, 11, 16, 10);

    setUp(() async {
      now = DateTime(2026, 11, 16, 10);
      progress = await ProgressController.load(
        SaveRepository(MemoryStore()),
        clock: () => now,
      );
      service = FakeReminderService();
      manager = ReminderManager(
        service: service,
        progress: progress,
        analytics: DebugAnalytics(),
        clock: () => now,
      );
    });

    test('off by default: nothing scheduled, offer pending', () async {
      await manager.start();
      expect(service.scheduled, isEmpty);
      expect(manager.shouldOffer, isTrue);
    });

    test('opt-in asks permission once and schedules the week', () async {
      expect(await manager.enable(), isTrue);
      expect(service.permissionRequests, 1);
      expect(service.scheduled.length, 7);
      expect(manager.shouldOffer, isFalse);
    });

    test('denied permission keeps reminders off and never re-offers', () async {
      service.grant = false;
      expect(await manager.enable(), isFalse);
      expect(manager.enabled, isFalse);
      expect(manager.shouldOffer, isFalse);
      expect(service.scheduled, isEmpty);
    });

    test('declining also stops the offer', () async {
      await manager.decline();
      expect(manager.shouldOffer, isFalse);
      expect(manager.enabled, isFalse);
    });

    test('solving today drops today from the schedule', () async {
      await manager.enable();
      expect(service.scheduled.first.when.day, 16);
      await progress.recordDaily(
        day: Economy.dayKey(now),
        result: solved(),
        hints: 0,
      );
      await manager.refresh();
      expect(service.scheduled.first.when.day, 17);
      expect(service.scheduled.first.title, contains('1日連続中'));
    });

    test('changing the time re-plans; turning off cancels', () async {
      await manager.enable();
      await manager.setTime(7, 5);
      expect(manager.timeLabel, '7:05');
      expect(service.scheduled.first.when, DateTime(2026, 11, 17, 7, 5));
      await manager.disable();
      expect(service.cancelled, isTrue);
      expect(service.scheduled, isEmpty);
    });

    test('unsupported platform does nothing', () async {
      final m = ReminderManager(
        service: NoReminderService(),
        progress: progress,
        analytics: DebugAnalytics(),
      );
      expect(m.supported, isFalse);
      expect(m.shouldOffer, isFalse);
      await m.refresh();
    });
  });

  test('reminder settings persist', () async {
    final store = MemoryStore();
    final p = await ProgressController.load(SaveRepository(store));
    await p.updateSettings((s) {
      s.reminderEnabled = true;
      s.reminderHour = 8;
      s.reminderMinute = 15;
      s.reminderAsked = true;
    });
    final r = await ProgressController.load(SaveRepository(store));
    expect(r.data.settings.reminderEnabled, isTrue);
    expect(r.data.settings.reminderHour, 8);
    expect(r.data.settings.reminderMinute, 15);
    expect(r.data.settings.reminderAsked, isTrue);
    final old = Settings.fromJson({'sound': true});
    expect(old.reminderEnabled, isFalse);
    expect(old.reminderHour, 19);
  });
}
