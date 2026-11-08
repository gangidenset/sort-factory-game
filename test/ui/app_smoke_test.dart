import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/app/app.dart';
import 'package:sort_factory/app/services.dart';
import 'package:sort_factory/data/progress_controller.dart';
import 'package:sort_factory/data/save_repository.dart';
import 'package:sort_factory/game/logic/models.dart';
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

  testWidgets('play stage 1 through taps until clear', (tester) async {
    await setPhone(tester, const Size(390, 844));
    final svc = await tester.runAsync(makeServices);
    await tester.pumpWidget(SortFactoryApp(services: svc!));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Tutorial card first.
    expect(find.text('仕分けの基本'), findsOneWidget);
    await tester.tap(find.text('スタート'));
    await tester.pump();

    final game =
        (tester.widget(
              find.byWidgetPredicate((w) => w is GameWidget),
            ) as GameWidget).game!
            as dynamic;
    // Play by tapping the hinted dock, like a player following the highlight.
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final session = game.session;
      if (session.isOver) break;
      final front = session.front;
      if (front == null || front.pos > 0.1) continue;
      final hint = session.hintForFront();
      if (hint is DockTarget) {
        final rect = game.board.debugDockRect(hint.dock) as Rect;
        final gameBox = tester.getTopLeft(
          find.byWidgetPredicate((w) => w is GameWidget),
        );
        await tester.tapAt(gameBox + rect.center);
      }
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.session.status, SessionStatus.cleared);
    expect(find.text('STAGE CLEAR!'), findsOneWidget);
    // Progress was saved and stage 2 unlocked.
    await tester.pump(const Duration(milliseconds: 100));
    expect(svc.progress.isUnlocked(2), isTrue);
    expect(svc.progress.data.coins, greaterThan(0));
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
    final t = game.session.elapsed as double;
    await tester.pump(const Duration(seconds: 1));
    expect(game.session.elapsed, t);
    await tester.tap(find.text('つづける'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(game.session.elapsed as double, greaterThan(t));
  });
}
