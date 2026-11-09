import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/game/logic/game_session.dart';
import 'package:sort_factory/game/logic/models.dart';
import 'package:sort_factory/game/logic/stage_config.dart';
import 'package:sort_factory/game/logic/stage_repository.dart';

StageCatalog loadCatalog() => StageCatalog.fromJsonString(
  File('assets/stages/stages.json').readAsStringSync(),
);

/// Simple bot: acts every [reaction] seconds following the in-game hints.
GameSession playWithBot(StageConfig stage, {double reaction = 0.45}) {
  final s = GameSession(stage)..start();
  var t = 0.0;
  while (!s.isOver && s.elapsed < 600) {
    s.update(1 / 30);
    t += 1 / 30;
    if (t < reaction) continue;
    t = 0;
    final fromBuffer = s.hintForBuffer();
    if (fromBuffer != null) {
      s.move(BufferSource(fromBuffer.$1), DockTarget(fromBuffer.$2));
      continue;
    }
    final hint = s.hintForFront();
    if (hint != null) s.move(const FrontSource(), hint);
  }
  return s;
}

void main() {
  test('stage file has 30 valid stages with unique ids', () {
    final c = loadCatalog();
    expect(c.length, 30);
    expect(c.stages.map((s) => s.id), List.generate(30, (i) => i + 1));
    expect(c.stages.where((s) => s.difficulty == Difficulty.easy).length, 10);
    expect(c.stages.where((s) => s.difficulty == Difficulty.normal).length, 10);
    expect(c.stages.where((s) => s.difficulty == Difficulty.hard).length, 10);
  });

  test('nextOf walks the catalog', () {
    final c = loadCatalog();
    expect(c.nextOf(1)!.id, 2);
    expect(c.nextOf(30), isNull);
  });

  test('invalid stage data is rejected', () {
    expect(
      () => StageConfig.fromJson({'id': 1, 'docks': 9}),
      throwsFormatException,
    );
    expect(
      () => StageCatalog.fromJsonString('{"stages":[{"id":1},{"id":1}]}'),
      throwsFormatException,
    );
  });

  test('every stage is clearable by a hint-following bot', () {
    final c = loadCatalog();
    final report = StringBuffer();
    for (final stage in c.stages) {
      final s = playWithBot(stage);
      report.writeln(
        'stage ${stage.id}: ${s.status.name} ${s.failReason?.name ?? ''} '
        'score=${s.score} stars=${s.stars} t=${s.elapsed.toStringAsFixed(0)}s '
        'moves=${s.movesUsed}/${s.moveLimit ?? '-'} miss=${s.mistakes} '
        'disc=${s.discarded}',
      );
      expect(
        s.status,
        SessionStatus.cleared,
        reason: 'stage ${stage.id} not clearable\n$report',
      );
    }
    // ignore: avoid_print
    print(report);
  });

  test('a slow, careless player does not clear the hard stages', () {
    // Sanity check that HARD is actually hard: sort front blindly to dock 0.
    final c = loadCatalog();
    var failures = 0;
    for (final stage in c.stages.where(
      (s) => s.difficulty == Difficulty.hard,
    )) {
      final s = GameSession(stage)..start();
      var t = 0.0;
      while (!s.isOver && s.elapsed < 600) {
        s.update(1 / 30);
        t += 1 / 30;
        if (t >= 1.2) {
          t = 0;
          s.move(const FrontSource(), const DockTarget(0));
        }
      }
      if (s.status == SessionStatus.failed) failures++;
    }
    expect(failures, 10);
  });
}
