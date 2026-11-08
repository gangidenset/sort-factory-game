import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/game/logic/game_session.dart';
import 'package:sort_factory/game/logic/models.dart';
import 'package:sort_factory/game/logic/scoring.dart';
import 'package:sort_factory/game/logic/stage_config.dart';

StageConfig cfg({
  int docks = 2,
  int cap = 3,
  int target = 10,
  int maxMistakes = 3,
  int buffer = 1,
  int belt = 6,
  double spawn = 2,
  double? timeLimit,
  int? moveLimit,
  double timedRate = 0,
  double shiftRate = 0,
  List<int> colors = const [0, 1],
}) => StageConfig(
  id: 1,
  docks: docks,
  dockCapacity: cap,
  targetDeliveries: target,
  maxMistakes: maxMistakes,
  bufferSlots: buffer,
  beltCapacity: belt,
  spawnInterval: spawn,
  timeLimit: timeLimit,
  moveLimit: moveLimit,
  timedRate: timedRate,
  shiftRate: shiftRate,
  colors: colors,
  starScores: const [500, 1000],
);

GameSession started(StageConfig c) => GameSession(c)..start();

/// Replaces the front package with one of the given color.
Package putFront(GameSession s, {required int color, int mark = 0}) {
  final p = Package(id: 999, colorA: color, mark: mark);
  if (s.belt.isEmpty) {
    s.belt.add(p);
  } else {
    s.belt[0] = p;
  }
  return p;
}

int matchingDock(GameSession s, Package p) =>
    s.docks.indexWhere((d) => d.requirement.matches(p));

int wrongDock(GameSession s, Package p) =>
    s.docks.indexWhere((d) => !d.requirement.matches(p));

void main() {
  group('delivery & scoring', () {
    test('correct delivery scores and builds combo', () {
      final s = started(cfg());
      final req = s.docks[0].requirement;
      putFront(s, color: req.color!);
      final r = s.move(const FrontSource(), const DockTarget(0));
      expect(r.outcome, MoveOutcome.correct);
      expect(s.delivered, 1);
      expect(s.combo, 1);
      expect(s.score, Scoring.baseCorrect);
      expect(s.docks[0].filled, 1);
    });

    test('combo increases points per delivery', () {
      final s = started(cfg(cap: 10));
      final c = s.docks[0].requirement.color!;
      putFront(s, color: c);
      s.move(const FrontSource(), const DockTarget(0));
      putFront(s, color: c);
      final r = s.move(const FrontSource(), const DockTarget(0));
      expect(r.scoreDelta, Scoring.baseCorrect + Scoring.comboStep);
      expect(s.maxCombo, 2);
    });

    test('combo bonus is capped', () {
      const p = Package;
      expect(p, isNotNull);
      final pkg = Package(id: 1, colorA: 0);
      expect(Scoring.correct(pkg, 100), Scoring.correct(pkg, 21));
    });

    test('wrong delivery counts as mistake and resets combo', () {
      final s = started(cfg());
      final c = s.docks[0].requirement.color!;
      putFront(s, color: c);
      s.move(const FrontSource(), const DockTarget(0));
      final p = putFront(s, color: c);
      final wd = wrongDock(s, p);
      final r = s.move(const FrontSource(), DockTarget(wd));
      expect(r.outcome, MoveOutcome.wrong);
      expect(s.mistakes, 1);
      expect(s.combo, 0);
      expect(s.delivered, 1);
    });

    test('reaching max mistakes fails the stage', () {
      final s = started(cfg(maxMistakes: 2));
      for (var i = 0; i < 2; i++) {
        final p = putFront(s, color: s.docks[0].requirement.color!);
        s.move(const FrontSource(), DockTarget(wrongDock(s, p)));
      }
      expect(s.status, SessionStatus.failed);
      expect(s.failReason, FailReason.mistakes);
    });

    test('truck departs when full and next requirement moves in', () {
      final s = started(cfg(cap: 2));
      final next = s.docks[0].next;
      final c = s.docks[0].requirement.color!;
      putFront(s, color: c);
      s.move(const FrontSource(), const DockTarget(0));
      putFront(s, color: c);
      final r = s.move(const FrontSource(), const DockTarget(0));
      expect(r.truckDeparted, isTrue);
      expect(s.docks[0].filled, 0);
      expect(s.docks[0].departures, 1);
      expect(s.docks[0].requirement, next);
      expect(
        r.scoreDelta,
        Scoring.baseCorrect + Scoring.comboStep + Scoring.truckBonus,
      );
    });

    test('mark requirement must match mark too', () {
      const req = Requirement(color: 1, mark: 2);
      expect(req.matches(Package(id: 1, colorA: 1, mark: 2)), isTrue);
      expect(req.matches(Package(id: 1, colorA: 1, mark: 1)), isFalse);
      expect(req.matches(Package(id: 1, colorA: 0, mark: 2)), isFalse);
      const markOnly = Requirement(mark: 3);
      expect(markOnly.matches(Package(id: 1, colorA: 4, mark: 3)), isTrue);
    });

    test('reaching target clears the stage', () {
      final s = started(cfg(target: 2, cap: 5));
      for (var i = 0; i < 2; i++) {
        putFront(s, color: s.docks[0].requirement.color!);
        s.move(const FrontSource(), const DockTarget(0));
      }
      expect(s.status, SessionStatus.cleared);
      expect(s.stars, greaterThanOrEqualTo(1));
    });

    test('stars follow thresholds', () {
      final c = cfg();
      expect(c.starsFor(0), 1);
      expect(c.starsFor(500), 2);
      expect(c.starsFor(1000), 3);
    });
  });

  group('buffer & chute', () {
    test('store front into buffer then deliver from buffer', () {
      final s = started(cfg());
      final p = putFront(s, color: s.docks[1].requirement.color!);
      expect(
        s.move(const FrontSource(), const BufferTarget(0)).outcome,
        MoveOutcome.stored,
      );
      expect(s.buffer[0], same(p));
      final r = s.move(const BufferSource(0), DockTarget(matchingDock(s, p)));
      expect(r.outcome, MoveOutcome.correct);
      expect(s.buffer[0], isNull);
    });

    test('cannot store into an occupied slot or move buffer to buffer', () {
      final s = started(cfg());
      putFront(s, color: 0);
      s.move(const FrontSource(), const BufferTarget(0));
      putFront(s, color: 1);
      final before = s.movesUsed;
      expect(
        s.move(const FrontSource(), const BufferTarget(0)).outcome,
        MoveOutcome.invalid,
      );
      expect(
        s.move(const BufferSource(0), const BufferTarget(0)).outcome,
        MoveOutcome.invalid,
      );
      expect(s.movesUsed, before);
    });

    test('empty source and out-of-range targets are invalid', () {
      final s = started(cfg(buffer: 0));
      expect(
        s.move(const BufferSource(0), const DockTarget(0)).outcome,
        MoveOutcome.invalid,
      );
      putFront(s, color: 0);
      expect(
        s.move(const FrontSource(), const DockTarget(9)).outcome,
        MoveOutcome.invalid,
      );
      expect(
        s.move(const FrontSource(), const BufferTarget(0)).outcome,
        MoveOutcome.invalid,
      );
    });

    test('chute discards without a mistake but breaks combo', () {
      final s = started(cfg(cap: 9));
      putFront(s, color: s.docks[0].requirement.color!);
      s.move(const FrontSource(), const DockTarget(0));
      putFront(s, color: 0);
      final r = s.move(const FrontSource(), const ChuteTarget());
      expect(r.outcome, MoveOutcome.discarded);
      expect(s.mistakes, 0);
      expect(s.combo, 0);
      expect(s.discarded, 1);
    });

    test('moves are rejected when not playing', () {
      final s = GameSession(cfg());
      putFront(s, color: 0);
      expect(
        s.move(const FrontSource(), const ChuteTarget()).outcome,
        MoveOutcome.invalid,
      );
    });
  });

  group('time & belt', () {
    test('belt jams when full', () {
      final s = started(cfg(belt: 3, spawn: 0.5));
      for (var i = 0; i < 40 && !s.isOver; i++) {
        s.update(0.25);
      }
      expect(s.failReason, FailReason.jam);
    });

    test('packages slide toward the front and never overlap', () {
      final s = started(cfg(spawn: 0.3));
      for (var i = 0; i < 10; i++) {
        s.update(0.1);
      }
      for (var i = 0; i < s.belt.length; i++) {
        expect(s.belt[i].pos, greaterThanOrEqualTo(i.toDouble()));
      }
    });

    test('time limit fails the stage', () {
      final s = started(cfg(timeLimit: 3, spawn: 100));
      for (var i = 0; i < 5; i++) {
        s.update(0.5);
      }
      expect(s.status, SessionStatus.playing);
      s.update(0.6);
      expect(s.failReason, FailReason.timeUp);
    });

    test('huge frame gaps are capped to 1 second', () {
      final s = started(cfg(spawn: 100));
      s.update(30);
      expect(s.elapsed, closeTo(1, 1e-6));
    });

    test('move limit fails when moves run out', () {
      final s = started(cfg(moveLimit: 10, target: 10));
      for (var i = 0; i < 10 && !s.isOver; i++) {
        putFront(s, color: 0);
        s.move(const FrontSource(), const ChuteTarget());
      }
      expect(s.failReason, FailReason.outOfMoves);
    });

    test('timed package expires into a mistake', () {
      final s = started(cfg(spawn: 100));
      s.belt
        ..clear()
        ..add(Package(id: 5, colorA: 0, kind: PackageKind.timed, timeLimit: 2));
      s.update(1);
      expect(s.mistakes, 0);
      s.update(1.1);
      expect(s.mistakes, 1);
      expect(s.expired, 1);
      expect(s.belt, isEmpty);
    });

    test('shifting package alternates colors', () {
      final p = Package(
        id: 1,
        colorA: 0,
        colorB: 3,
        kind: PackageKind.shifting,
        shiftPeriod: 2,
      );
      expect(p.color, 0);
      p.age = 2.1;
      expect(p.color, 3);
      p.age = 4.1;
      expect(p.color, 0);
    });

    test('update is ignored when paused/over', () {
      final s = GameSession(cfg());
      s.update(5);
      expect(s.elapsed, 0);
    });
  });

  group('revive', () {
    test('revive after mistakes restores play once', () {
      final s = started(cfg(maxMistakes: 3));
      for (var i = 0; i < 3; i++) {
        final p = putFront(s, color: s.docks[0].requirement.color!);
        s.move(const FrontSource(), DockTarget(wrongDock(s, p)));
      }
      expect(s.canRevive, isTrue);
      expect(s.revive(), isTrue);
      expect(s.status, SessionStatus.playing);
      expect(s.mistakes, 1);
      for (var i = 0; i < 2; i++) {
        final p = putFront(s, color: s.docks[0].requirement.color!);
        s.move(const FrontSource(), DockTarget(wrongDock(s, p)));
      }
      expect(s.status, SessionStatus.failed);
      expect(s.canRevive, isFalse);
      expect(s.revive(), isFalse);
    });

    test('revive after jam frees belt space', () {
      final s = started(cfg(belt: 4, spawn: 0.5));
      while (!s.isOver) {
        s.update(0.25);
      }
      final len = s.belt.length;
      s.revive();
      expect(s.belt.length, len - 3);
    });

    test('revive after time up adds time', () {
      final s = started(cfg(timeLimit: 2, spawn: 100));
      s.update(1);
      s.update(1);
      s.update(0.1);
      expect(s.failReason, FailReason.timeUp);
      s.revive();
      expect(s.timeLeft, greaterThan(10));
    });
  });

  group('generation', () {
    test('same seed gives same package sequence', () {
      List<int> seq() {
        final s = started(cfg(spawn: 0.5, belt: 30, colors: [0, 1, 2]));
        for (var i = 0; i < 20; i++) {
          s.update(0.5);
        }
        return s.belt.map((p) => p.color * 10 + p.mark).toList();
      }

      expect(seq(), seq());
    });

    test('open docks start with different requirements', () {
      final s = GameSession(cfg(docks: 3, colors: [0, 1, 2, 3]));
      final reqs = s.docks.map((d) => d.requirement).toSet();
      expect(reqs.length, 3);
    });

    test('upgrades extend belt and buffer', () {
      final s = GameSession(
        cfg(buffer: 1, belt: 6),
        modifiers: const SessionModifiers(extraBelt: 1, extraBuffer: 1),
      );
      expect(s.beltCapacity, 7);
      expect(s.buffer.length, 2);
      final noBuf = GameSession(
        cfg(buffer: 0),
        modifiers: const SessionModifiers(extraBuffer: 2),
      );
      expect(noBuf.buffer.length, 0);
    });
  });

  group('hint', () {
    test('hint points to matching dock', () {
      final s = started(cfg());
      final p = putFront(s, color: s.docks[1].requirement.color!);
      expect(s.hintForFront(), DockTarget(matchingDock(s, p)));
    });
  });
}
