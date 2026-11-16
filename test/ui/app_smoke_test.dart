import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/app/app.dart';
import 'package:sort_factory/app/services.dart';
import 'package:sort_factory/data/progress_controller.dart';
import 'package:sort_factory/data/save_repository.dart';
import 'package:sort_factory/game/logic/game_session.dart';
import 'package:sort_factory/game/logic/models.dart';
import 'package:sort_factory/game/logic/daily.dart';
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

  Future<dynamic> openStage1(WidgetTester tester, AppServices svc) async {
    await tester.pumpWidget(SortFactoryApp(services: svc));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    if (find.text('スタート').evaluate().isNotEmpty) {
      await tester.tap(find.text('スタート'));
      await tester.pump();
    }
    return (tester.widget(
          find.byWidgetPredicate((w) => w is GameWidget),
        ) as GameWidget).game!
        as dynamic;
  }

  Future<void> tapCell(WidgetTester tester, dynamic game, Cell c) async {
    final origin = tester.getTopLeft(
      find.byWidgetPredicate((w) => w is GameWidget),
    );
    await tester.tapAt(origin + (game.board.debugCellRect(c) as Rect).center);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('solve stage 1 with real taps, watch the finale, get rewarded', (
    tester,
  ) async {
    await setPhone(tester, const Size(390, 844));
    final svc = await tester.runAsync(makeServices);
    final game = await openStage1(tester, svc!);
    // Stage 1 is guided: the panel tells the player what to tap.
    expect(find.textContaining('光っているマスをタップ'), findsOneWidget);
    final session = game.session as GameSession;
    for (final box in session.config.solution) {
      await tapCell(tester, game, box);
    }
    expect(session.isCleared, isTrue);
    expect(find.text('ALL SHIPPED!'), findsNothing); // finale still playing
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('ALL SHIPPED!'), findsOneWidget);
    expect(find.text('ヒントなしで解けました！'), findsOneWidget);
    expect(svc.progress.isUnlocked(2), isTrue);
    expect(svc.progress.data.coins, greaterThan(0));
  });

  testWidgets('tap cycles marks, undo reverts, hint explains', (tester) async {
    await setPhone(tester, const Size(390, 844));
    final svc = await tester.runAsync(makeServices);
    final game = await openStage1(tester, svc!);
    final session = game.session as GameSession;
    final cell = session.config.solution.first;
    await tapCell(tester, game, cell);
    expect(session.markAt(cell), Mark.box);
    await tapCell(tester, game, cell);
    expect(session.markAt(cell), Mark.cross);
    await tester.tap(find.text('戻す'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(session.markAt(cell), Mark.box);
    await tester.tap(find.text('戻す'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(session.boxesPlaced, 0);

    await tester.tap(find.text('ヒント'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byIcon(Icons.lightbulb_rounded),
      findsNWidgets(2),
    ); // button + explanation
    expect(session.hintsUsed, 0); // practice stage: hints are free
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

  testWidgets('tapping a forbidden cell explains why and places nothing', (
    tester,
  ) async {
    await setPhone(tester, const Size(390, 844));
    final svc = await tester.runAsync(makeServices);
    final game = await openStage1(tester, svc!);
    final session = game.session as GameSession;
    final n = session.size;
    final cell =
        [
          for (var r = 0; r < n; r++)
            for (var c = 0; c < n; c++) (r, c),
        ].firstWhere(
          (c) => !session.isTruck(c) && session.placeBlockReason(c) != null,
        );
    await tapCell(tester, game, cell);
    expect(session.markAt(cell), Mark.none);
    expect(find.textContaining('ここには置けません'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('ここには置けません'), findsNothing);
    // Guidance comes back after the refusal message.
    expect(find.textContaining('光っているマス'), findsOneWidget);
  });

  testWidgets('daily puzzle: open from title, solve, share, streak shown', (
    tester,
  ) async {
    await setPhone(tester, const Size(390, 844));
    final svc = await tester.runAsync(makeServices);
    await tester.pumpWidget(SortFactoryApp(services: svc!));
    await tester.pumpAndSettle();
    expect(find.text('今日のパズル'), findsOneWidget);
    await tester.tap(find.text('挑戦'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final game =
        (tester.widget(
              find.byWidgetPredicate((w) => w is GameWidget),
            ) as GameWidget).game!
            as dynamic;
    final session = game.session as GameSession;
    expect(session.config.id, DailyCatalog.dayKey(DateTime.now()));
    for (final box in session.config.solution) {
      await tapCell(tester, game, box);
    }
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('今日のパズル クリア！'), findsOneWidget);
    expect(find.text('1日連続'), findsOneWidget);
    expect(svc.progress.todaysPuzzleSolved, isTrue);
    // Daily play never touches the stage list.
    expect(svc.progress.isUnlocked(2), isFalse);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await tester.ensureVisible(find.text('結果をコピーして共有'));
    await tester.tap(find.text('結果をコピーして共有'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(copied, contains('SORT FACTORY 今日のパズル'));
    expect(copied, contains('ノーヒント'));
  });
}
