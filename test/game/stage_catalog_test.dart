import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/game/logic/game_session.dart';
import 'package:sort_factory/game/logic/models.dart';
import 'package:sort_factory/game/logic/solver.dart';
import 'package:sort_factory/game/logic/stage_config.dart';
import 'package:sort_factory/game/logic/stage_repository.dart';

StageCatalog loadCatalog() => StageCatalog.fromJsonString(
  File('assets/stages/stages.json').readAsStringSync(),
);

void main() {
  test('stage file has 30 valid stages with unique ids', () {
    final c = loadCatalog();
    expect(c.length, 30);
    expect(c.stages.map((s) => s.id), List.generate(30, (i) => i + 1));
    for (final d in Difficulty.values) {
      expect(c.stages.where((s) => s.difficulty == d).length, 10);
    }
    expect(c.nextOf(1)!.id, 2);
    expect(c.nextOf(30), isNull);
  });

  test('duplicate ids are rejected', () {
    expect(
      () => StageCatalog.fromJsonString(
        '{"stages":[{"id":1,"lanes":[[0,0,0]],"trucks":[0]},'
        '{"id":1,"lanes":[[0,0,0]],"trucks":[0]}]}',
      ),
      throwsFormatException,
    );
  });

  test('every stage is solvable and its solution clears it', () {
    for (final stage in loadCatalog().stages) {
      final sol = Solver(maxNodes: 2000000).solve(GameSession(stage)..start());
      expect(sol, isNotNull, reason: 'stage ${stage.id} not solvable');
      final s = GameSession(stage)..start();
      for (final m in sol!) {
        expect(s.tap(m), isTrue);
      }
      expect(s.status, SessionStatus.cleared, reason: 'stage ${stage.id}');
    }
  });

  test('tapping blindly from left to right fails most hard stages', () {
    var fails = 0;
    for (final stage in loadCatalog().stages.where(
      (s) => s.difficulty == Difficulty.hard,
    )) {
      final s = GameSession(stage)..start();
      while (s.status == SessionStatus.playing) {
        final lane = List.generate(
          s.lanes.length,
          (i) => i,
        ).firstWhere(s.canTap);
        s.tap(lane);
      }
      if (s.status == SessionStatus.failed) fails++;
    }
    expect(fails, greaterThanOrEqualTo(8));
  });
}
