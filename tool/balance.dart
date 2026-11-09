// Balancing harness: simulates human-like players on every stage.
//
//   dart run tool/balance.dart
//
// Each profile acts every `reaction` seconds and makes a wrong choice with
// probability `error`. Prints clear rate, average stars and play time.
import 'dart:io';

import 'package:sort_factory/game/logic/game_session.dart';
import 'package:sort_factory/game/logic/models.dart';
import 'package:sort_factory/game/logic/rng.dart';
import 'package:sort_factory/game/logic/stage_config.dart';
import 'package:sort_factory/game/logic/stage_repository.dart';

class Profile {
  const Profile(this.name, this.reaction, this.error);
  final String name;
  final double reaction;
  final double error;
}

const profiles = [
  Profile('expert', 0.6, 0.02),
  Profile('average', 0.9, 0.06),
  Profile('casual', 1.2, 0.10),
];

GameSession play(StageConfig base, Profile pr, int run) {
  final stage = StageConfig.fromJson({
    ..._toJson(base),
    'seed': base.seed + run * 7919,
  });
  final rng = SeededRng(run * 31 + 7);
  final s = GameSession(stage)..start();
  var t = 0.0;
  // Reaction time varies +-30%.
  var wait = pr.reaction;
  while (!s.isOver && s.elapsed < 600) {
    s.update(1 / 30);
    t += 1 / 30;
    if (t < wait) continue;
    t = 0;
    wait = pr.reaction * (0.7 + rng.nextDouble() * 0.6);
    final fb = s.hintForBuffer();
    if (fb != null) {
      s.move(BufferSource(fb.$1), DockTarget(fb.$2));
      continue;
    }
    if (s.front == null) continue;
    Target? hint = s.hintForFront();
    if (rng.chance(pr.error)) hint = DockTarget(rng.nextInt(s.docks.length));
    if (hint != null) s.move(const FrontSource(), hint);
  }
  return s;
}

Map<String, dynamic> _toJson(StageConfig c) => {
  'id': c.id,
  'difficulty': c.difficulty.name,
  'colors': c.colors,
  'docks': c.docks,
  'dockCapacity': c.dockCapacity,
  'targetDeliveries': c.targetDeliveries,
  'maxMistakes': c.maxMistakes,
  'spawnInterval': c.spawnInterval,
  'beltSpeed': c.beltSpeed,
  'beltCapacity': c.beltCapacity,
  'bufferSlots': c.bufferSlots,
  'initialPackages': c.initialPackages,
  'timeLimit': c.timeLimit,
  'moveLimit': c.moveLimit,
  'offRate': c.offRate,
  'timedRate': c.timedRate,
  'timedSeconds': c.timedSeconds,
  'shiftRate': c.shiftRate,
  'shiftPeriod': c.shiftPeriod,
  'useMarks': c.useMarks,
  'markDockRate': c.markDockRate,
  'markOnlyRate': c.markOnlyRate,
  'starScores': c.starScores,
  'seed': c.seed,
};

void main() {
  final catalog = StageCatalog.fromJsonString(
    File('assets/stages/stages.json').readAsStringSync(),
  );
  const runs = 30;
  stdout.writeln('stage  ${profiles.map((p) => p.name.padRight(22)).join()}');
  for (final stage in catalog.stages) {
    final cols = <String>[];
    for (final pr in profiles) {
      var clears = 0, stars = 0;
      var time = 0.0;
      for (var r = 0; r < runs; r++) {
        final s = play(stage, pr, r);
        if (s.status == SessionStatus.cleared) {
          clears++;
          stars += s.stars;
          time += s.elapsed;
        }
      }
      final avgStars = clears == 0 ? 0 : stars / clears;
      final avgTime = clears == 0 ? 0 : time / clears;
      cols.add(
        '${(clears * 100 / runs).round().toString().padLeft(3)}% '
                '★${avgStars.toStringAsFixed(1)} ${avgTime.toStringAsFixed(0)}s'
            .padRight(22),
      );
    }
    stdout.writeln(
      '${stage.id.toString().padLeft(2)} ${stage.difficulty.name[0]}  ${cols.join()}',
    );
  }
}
