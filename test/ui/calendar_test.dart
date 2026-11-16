import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/app/services.dart';
import 'package:sort_factory/app/theme.dart';
import 'package:sort_factory/data/progress_controller.dart';
import 'package:sort_factory/data/save_repository.dart';
import 'package:sort_factory/game/logic/daily.dart';
import 'package:sort_factory/game/logic/game_session.dart';
import 'package:sort_factory/game/logic/stage_repository.dart';
import 'package:sort_factory/screens/calendar_screen.dart';
import 'package:sort_factory/services/ads/ad_manager.dart';
import 'package:sort_factory/services/ads/ad_service.dart';
import 'package:sort_factory/services/analytics/analytics.dart';
import 'package:sort_factory/services/audio/audio_service.dart';
import 'package:sort_factory/services/iap/purchase_service.dart';
import 'package:sort_factory/services/notifications/reminder_manager.dart';
import 'package:sort_factory/services/notifications/reminder_service.dart';

// Monday 2026-11-16, noon.
final fixedNow = DateTime(2026, 11, 16, 12);

StageResult solved({int seconds = 90}) => StageResult(
  stageId: 0,
  cleared: true,
  score: 500,
  stars: 3,
  deliveries: 7,
  seconds: seconds.toDouble(),
);

Future<AppServices> makeServices({DateTime Function()? clock}) async {
  final analytics = DebugAnalytics();
  final progress = await ProgressController.load(
    SaveRepository(MemoryStore()),
    clock: clock ?? () => fixedNow,
  );
  return AppServices(
    progress: progress,
    stages: StageCatalog.fromJsonString(
      File('assets/stages/stages.json').readAsStringSync(),
    ),
    daily: DailyCatalog.fromJsonString(
      File('assets/stages/daily.json').readAsStringSync(),
    ),
    ads: AdManager(
      service: NoAdService(),
      progress: progress,
      analytics: analytics,
    ),
    purchases: UnavailablePurchaseService(),
    analytics: analytics,
    audio: AudioService(soundEnabled: () => false, hapticsEnabled: () => false),
    reminders: ReminderManager(
      service: NoReminderService(),
      progress: progress,
      analytics: analytics,
    ),
  );
}

void main() {
  group('past puzzles rules', () {
    late ProgressController p;
    setUp(() async => p = (await makeServices()).progress);

    test('window covers the last 28 days, not today or the future', () {
      expect(p.isPastInWindow(20261115), isTrue);
      expect(p.isPastInWindow(20261019), isTrue); // 28 days back
      expect(p.isPastInWindow(20261018), isFalse);
      expect(p.isPastInWindow(20261116), isFalse);
      expect(p.isPastInWindow(20261117), isFalse);
    });

    test('missed day is locked until opened with coins', () async {
      expect(p.canPlayDaily(20261116), isTrue); // today
      expect(p.canPlayDaily(20261110), isFalse);
      expect(
        await p.unlockPastDaily(20261110, payWithCoins: true),
        isFalse,
      ); // 0 coins
      await p.addCoins(150);
      expect(await p.unlockPastDaily(20261110, payWithCoins: true), isTrue);
      expect(p.data.coins, 50);
      expect(p.canPlayDaily(20261110), isTrue);
      expect(
        await p.unlockPastDaily(20261110, payWithCoins: true),
        isFalse,
      ); // already open
      expect(p.data.coins, 50);
    });

    test(
      'ad unlock costs no coins; out-of-window days cannot be opened',
      () async {
        expect(await p.unlockPastDaily(20261101, payWithCoins: false), isTrue);
        expect(p.data.coins, 0);
        expect(await p.unlockPastDaily(20260901, payWithCoins: false), isFalse);
        expect(await p.unlockPastDaily(20261120, payWithCoins: false), isFalse);
      },
    );

    test(
      'late solves pay the small reward and never extend the streak',
      () async {
        final (yesterday, streak1) = await p.recordDaily(
          day: 20261115,
          result: solved(),
          hints: 0,
        );
        expect(yesterday.coins, ProgressController.pastReward);
        expect(streak1, 0);
        expect(p.dailyRecord(20261115)!.late, isTrue);
        final (today, streak2) = await p.recordDaily(
          day: 20261116,
          result: solved(),
          hints: 0,
        );
        expect(today.coins, ProgressController.dailyCoins(1));
        expect(streak2, 1, reason: 'late yesterday does not chain into today');
        expect(p.recentDaily(2), [false, true]);
      },
    );

    test('late flag and unlocks persist', () async {
      final store = MemoryStore();
      final a = await ProgressController.load(
        SaveRepository(store),
        clock: () => fixedNow,
      );
      await a.unlockPastDaily(20261112, payWithCoins: false);
      await a.recordDaily(day: 20261111, result: solved(), hints: 1);
      final b = await ProgressController.load(
        SaveRepository(store),
        clock: () => fixedNow,
      );
      expect(b.canPlayDaily(20261112), isTrue);
      expect(b.dailyRecord(20261111)!.late, isTrue);
    });
  });

  testWidgets('calendar: open a missed day with coins and play it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final svc = await tester.runAsync(makeServices);
    await svc!.progress.addCoins(120);
    await tester.pumpWidget(
      ServicesScope(
        services: svc,
        child: MaterialApp(
          theme: buildTheme(),
          home: CalendarScreen(clock: () => fixedNow),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2026年11月'), findsOneWidget);

    // Future days are not playable.
    await tester.tap(find.text('20'));
    await tester.pump();
    expect(find.textContaining('まだ届いていません'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));

    // A missed day asks to be opened.
    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();
    expect(find.text('11/10(火)のパズル'), findsOneWidget);
    await tester.tap(find.text('100コインで開ける'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(svc.progress.data.coins, 20);
    final game =
        (tester.widget(
              find.byWidgetPredicate((w) => w is GameWidget),
            ) as GameWidget).game!
            as dynamic;
    expect((game.session as GameSession).config.id, 20261110);

    // Previous month is reachable (window spans into October).
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('前の月'));
    await tester.pumpAndSettle();
    expect(find.text('2026年10月'), findsOneWidget);
  });
}
