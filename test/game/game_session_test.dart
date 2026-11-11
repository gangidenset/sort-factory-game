import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/game/logic/game_session.dart';
import 'package:sort_factory/game/logic/models.dart';
import 'package:sort_factory/game/logic/solver.dart';
import 'package:sort_factory/game/logic/stage_config.dart';

StageConfig stage({
  required List<List<int>> lanes,
  required List<int> trucks,
  int cap = 3,
  int docks = 2,
  int shelf = 3,
  Set<String> hidden = const {},
  List<LaneLock> locks = const [],
  int par = 0,
}) {
  final s = StageConfig(
    id: 1,
    lanes: lanes,
    trucks: [for (final c in trucks) TruckSpec(c, cap)],
    docks: docks,
    shelf: shelf,
    hidden: hidden,
    locks: locks,
    par: par,
  );
  s.validate();
  return s;
}

GameSession play(StageConfig c) => GameSession(c)..start();

void main() {
  group('tapping', () {
    test('front package goes to the matching truck', () {
      final s = play(
        stage(
          lanes: [
            [0, 0, 0],
            [1, 1, 1],
          ],
          trucks: [0, 1],
        ),
      );
      expect(s.tap(0), isTrue);
      expect(s.docks[0]!.filled, 1);
      expect(s.lanes[0].length, 2);
      expect(s.shelf, isEmpty);
      expect(s.moves, 1);
    });

    test('package with no truck goes to the shelf', () {
      final s = play(
        stage(
          lanes: [
            [2, 0, 0],
            [0, 1, 1],
            [1, 2, 2],
          ],
          trucks: [0, 1, 2],
          docks: 2,
        ),
      );
      s.tap(0); // color 2, no truck parked yet
      expect(s.shelf.map((p) => p.color), [2]);
      expect(s.shelfPlacements, 1);
    });

    test('full truck departs, next arrives and pulls from shelf (chain)', () {
      // Trucks: red, blue parked; green next. Shelf greens first, then fill red.
      final s = play(
        stage(
          lanes: [
            [2, 2, 2],
            [0, 0, 0],
            [1, 1, 1],
          ],
          trucks: [0, 1, 2],
          shelf: 3,
        ),
      );
      s.tap(0);
      s.tap(0);
      s.tap(0);
      expect(s.shelf.length, 3);
      s.tap(1);
      s.tap(1);
      s.drainEvents();
      s.tap(1); // red departs → green arrives → 3 greens from shelf → departs
      final events = s.drainEvents();
      final departs = events
          .where((e) => e.type == SessionEventType.depart)
          .toList();
      expect(departs.map((e) => e.chain), [1, 2]);
      expect(s.maxChain, 2);
      expect(s.shelf, isEmpty);
      expect(s.shipped, 2);
      expect(s.score, greaterThanOrEqualTo(100 + 200));
    });

    test('truck with most boxes of a color is preferred', () {
      final s = play(
        stage(
          lanes: [
            [0],
            [0, 0, 0, 0, 0],
          ],
          trucks: [0, 0],
          docks: 2,
        ),
      );
      s.tap(1);
      s.tap(1);
      expect(s.docks.map((t) => t!.filled), [2, 0]);
    });

    test('shelf overflow fails the stage', () {
      final s = play(
        stage(
          lanes: [
            [2, 2, 3, 0, 0, 0],
            [1, 1, 1],
            [2, 3, 3],
          ],
          trucks: [0, 1, 2, 3],
          shelf: 2,
        ),
      );
      s.tap(0);
      s.tap(0);
      expect(s.status, SessionStatus.playing);
      s.tap(0);
      expect(s.status, SessionStatus.failed);
      expect(s.failReason, FailReason.shelfOverflow);
    });

    test('shipping every truck clears the stage', () {
      final s = play(
        stage(
          lanes: [
            [0, 0, 0],
            [1, 1, 1],
          ],
          trucks: [0, 1],
          par: 0,
        ),
      );
      for (var i = 0; i < 3; i++) {
        s.tap(0);
        s.tap(1);
      }
      expect(s.status, SessionStatus.cleared);
      expect(s.stars, 3);
      expect(s.drainEvents().last.type, SessionEventType.cleared);
    });

    test('stars depend on shelf placements vs par', () {
      final c = stage(
        lanes: [
          [0, 0, 0],
        ],
        trucks: [0],
        par: 1,
      );
      expect(c.starsFor(0), 3);
      expect(c.starsFor(1), 3);
      expect(c.starsFor(3), 2);
      expect(c.starsFor(4), 1);
    });

    test('taps are ignored on empty lanes and before start', () {
      final c = stage(
        lanes: [
          [0, 0, 0],
          [],
        ],
        trucks: [0],
      );
      final s = GameSession(c);
      expect(s.tap(0), isFalse);
      s.start();
      expect(s.tap(1), isFalse);
      expect(s.tap(5), isFalse);
      expect(s.moves, 0);
    });
  });

  group('gimmicks', () {
    test('hidden package is revealed when it reaches the front', () {
      final s = play(
        stage(
          lanes: [
            [0, 1, 0, 0],
            [1, 1],
          ],
          trucks: [0, 1],
          hidden: {'0:1'},
        ),
      );
      expect(s.lanes[0][1].hidden, isTrue);
      s.tap(0);
      expect(s.lanes[0][0].hidden, isFalse);
      expect(
        s.drainEvents().any((e) => e.type == SessionEventType.reveal),
        isTrue,
      );
    });

    test('locked lane opens after enough departures', () {
      final s = play(
        stage(
          lanes: [
            [0, 0, 0],
            [1, 1, 1],
          ],
          trucks: [0, 1],
          locks: const [LaneLock(1, 1)],
        ),
      );
      expect(s.canTap(1), isFalse);
      expect(s.unlockIn(1), 1);
      s.tap(0);
      s.tap(0);
      s.tap(0);
      expect(s.canTap(1), isTrue);
    });

    test('stuck when only locked lanes remain', () {
      final s = play(
        stage(
          lanes: [
            [0, 0, 1],
            [1, 1, 0],
          ],
          trucks: [0, 1],
          docks: 1,
          shelf: 5,
          locks: const [LaneLock(1, 5)],
        ),
      );
      s.tap(0);
      s.tap(0);
      s.tap(0);
      expect(s.failReason, FailReason.stuck);
    });
  });

  group('undo & revive', () {
    test('undo restores the previous state and uses a free undo', () {
      final s = play(
        stage(
          lanes: [
            [2, 0, 0, 0],
            [1, 1, 1],
            [2, 2],
          ],
          trucks: [0, 1, 2],
        ),
      );
      final before = s.stateKey();
      s.tap(0);
      expect(s.shelf.length, 1);
      expect(s.undo(), isTrue);
      expect(s.stateKey(), before);
      expect(s.shelf, isEmpty);
      expect(s.freeUndos, 0);
      s.tap(0);
      expect(s.undo(), isFalse); // no free undos left
      expect(s.undo(paid: true), isTrue);
    });

    test('revive undoes the fatal move and adds a shelf slot once', () {
      final s = play(
        stage(
          lanes: [
            [2, 2, 3, 0, 0, 0],
            [1, 1, 1],
            [2, 3, 3],
          ],
          trucks: [0, 1, 2, 3],
          shelf: 2,
        ),
      );
      s.tap(0);
      s.tap(0);
      s.tap(0);
      expect(s.canRevive, isTrue);
      expect(s.revive(), isTrue);
      expect(s.status, SessionStatus.playing);
      expect(s.shelfCapacity, 3);
      expect(s.shelf.length, 2);
      s.tap(0);
      expect(s.status, SessionStatus.playing);
    });

    test('upgrades add shelf slots and free undos', () {
      final s = GameSession(
        stage(
          lanes: [
            [0, 0, 0],
          ],
          trucks: [0],
        ),
        modifiers: const SessionModifiers(extraShelf: 1, extraUndo: 2),
      );
      expect(s.shelfCapacity, 4);
      expect(s.freeUndos, 3);
    });
  });

  group('config validation', () {
    test('package count must match truck seats', () {
      expect(
        () => stage(
          lanes: [
            [0, 0],
          ],
          trucks: [0],
        ),
        throwsFormatException,
      );
    });

    test('json parsing', () {
      final c = StageConfig.fromJson({
        'id': 3,
        'lanes': [
          [0, 1],
          [1, 0],
        ],
        'trucks': [0, 1],
        'truckCapacity': 2,
        'docks': 2,
        'shelf': 4,
        'hidden': [
          [0, 1],
        ],
        'locks': [
          {'lane': 1, 'after': 1},
        ],
        'par': 2,
      });
      expect(c.packageCount, 4);
      expect(c.hidden, {'0:1'});
      expect(c.locks.single.after, 1);
      expect(c.par, 2);
    });
  });

  group('solver', () {
    test('solves a small puzzle and the solution clears it', () {
      final c = stage(
        lanes: [
          [2, 0, 1],
          [0, 2, 1],
          [1, 0, 2],
        ],
        trucks: [0, 1, 2],
        shelf: 2,
      );
      final sol = Solver().solve(play(c));
      expect(sol, isNotNull);
      final s = play(c);
      for (final m in sol!) {
        s.tap(m);
      }
      expect(s.status, SessionStatus.cleared);
    });

    test('reports unsolvable puzzles', () {
      final c = stage(
        lanes: [
          [2, 2, 2, 3, 3, 3, 0, 0, 0, 1, 1, 1],
        ],
        trucks: [0, 1, 2, 3],
        shelf: 2,
      );
      expect(Solver().solve(play(c)), isNull);
    });
  });
}
