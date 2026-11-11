import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/app/app.dart';
import 'package:sort_factory/app/services.dart';
import 'package:sort_factory/data/progress_controller.dart';
import 'package:sort_factory/data/save_repository.dart';
import 'package:sort_factory/game/logic/game_session.dart';
import 'package:sort_factory/game/logic/models.dart';
import 'package:sort_factory/game/logic/solver.dart';
import 'package:sort_factory/game/logic/stage_repository.dart';
import 'package:sort_factory/services/ads/ad_manager.dart';
import 'package:sort_factory/services/ads/ad_service.dart';
import 'package:sort_factory/services/analytics/analytics.dart';
import 'package:sort_factory/services/audio/audio_service.dart';
import 'package:sort_factory/services/iap/purchase_service.dart';

Future<AppServices> makeServices() async {
  final analytics = DebugAnalytics();
  final progress = await ProgressController.load(SaveRepository(MemoryStore()));
  return AppServices(
    progress: progress,
    stages: StageCatalog.fromJsonString(
      File('assets/stages/stages.json').readAsStringSync(),
    ),
    ads: AdManager(
      service: NoAdService(),
      progress: progress,
      analytics: analytics,
    ),
    purchases: UnavailablePurchaseService(),
    analytics: analytics,
    audio: AudioService(soundEnabled: () => false, hapticsEnabled: () => false),
  );
}

void main() {
  Future<void> setPhone(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  for (final size in const [Size(320, 568), Size(390, 844), Size(430, 932)]) {
    testWidgets('all menu screens render without overflow at $size', (
      tester,
    ) async {
      await setPhone(tester, size);
      final svc = await tester.runAsync(makeServices);
      await tester.pumpWidget(SortFactoryApp(services: svc!));
      await tester.pumpAndSettle();
      expect(find.textContaining('FACTORY'), findsWidgets);

      for (final label in ['ステージ', '工場', 'ショップ']) {
        await tester.tap(find.text(label).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      expect(find.text('効果音'), findsOneWidget);
    });
  }

  testWidgets('play stage 1 through real taps until clear', (tester) async {
    await setPhone(tester, const Size(390, 844));
    final svc = await tester.runAsync(makeServices);
    await tester.pumpWidget(SortFactoryApp(services: svc!));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('出荷のきほん'), findsOneWidget);
    await tester.tap(find.text('スタート'));
    await tester.pump();

    final game =
        (tester.widget(
              find.byWidgetPredicate((w) => w is GameWidget),
            ) as GameWidget).game!
            as dynamic;
    final solution = Solver().solve(game.session as GameSession)!;
    final origin = tester.getTopLeft(
      find.byWidgetPredicate((w) => w is GameWidget),
    );
    for (final lane in solution) {
      // Wait for chain playback to finish, like a player would.
      for (var i = 0; i < 40 && !(game.board.isIdle as bool); i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final rect = game.board.debugLaneRect(lane) as Rect;
      await tester.tapAt(origin + rect.center);
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.session.status, SessionStatus.cleared);
    expect(find.text('ALL SHIPPED!'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(svc.progress.isUnlocked(2), isTrue);
    expect(svc.progress.data.coins, greaterThan(0));
  });

  testWidgets('undo button reverts a move', (tester) async {
    await setPhone(tester, const Size(390, 844));
    final svc = await tester.runAsync(makeServices);
    await svc!.progress.markTutorialSeen('basic');
    await tester.pumpWidget(SortFactoryApp(services: svc));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final game =
        (tester.widget(
              find.byWidgetPredicate((w) => w is GameWidget),
            ) as GameWidget).game!
            as dynamic;
    final origin = tester.getTopLeft(
      find.byWidgetPredicate((w) => w is GameWidget),
    );
    final before = game.session.stateKey() as String;
    await tester.tapAt(origin + (game.board.debugLaneRect(0) as Rect).center);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.session.moves, 1);
    await tester.tap(find.text('戻す'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.session.stateKey(), before);
  });

  testWidgets('pause overlay pauses the session', (tester) async {
    await setPhone(tester, const Size(390, 844));
    final svc = await tester.runAsync(makeServices);
    await svc!.progress.markTutorialSeen('basic');
    await tester.pumpWidget(SortFactoryApp(services: svc));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.pause_circle_filled));
    await tester.pump();
    expect(find.text('ポーズ'), findsOneWidget);
    final game =
        (tester.widget(
              find.byWidgetPredicate((w) => w is GameWidget),
            ) as GameWidget).game!
            as dynamic;
    expect(game.paused, isTrue);
    await tester.tap(find.text('つづける'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(game.paused, isFalse);
    expect(find.text('ポーズ'), findsNothing);
  });
}
