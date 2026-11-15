import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/game/logic/deduction.dart';
import 'package:sort_factory/game/logic/game_session.dart';
import 'package:sort_factory/game/logic/models.dart';
import 'package:sort_factory/game/logic/stage_config.dart';

/// 4x4:   . T . .      boxes at (0,0) (2,2) (3,0)
///        . . . .      trucks at (0,1) (2,3) (2,0)
///        T . b T
///        b . . .
StageConfig small() => StageConfig(
  id: 1,
  size: 4,
  trucks: const [Truck((0, 1), 0), Truck((2, 3), 1), Truck((2, 0), 2)],
  solution: const [(0, 0), (2, 2), (3, 0)],
)..validate();

GameSession play([StageConfig? c]) => GameSession(c ?? small())..start();

void main() {
  group('config', () {
    test('clues are derived from the solution', () {
      final c = small();
      expect(c.rowClues, [1, 0, 1, 1]);
      expect(c.colClues, [2, 0, 1, 0]);
      expect(c.boxCount, 3);
    });

    test('rejects a box that is not next to its truck', () {
      expect(
        () => StageConfig(
          id: 1,
          size: 4,
          trucks: const [Truck((0, 0), 0)],
          solution: const [(2, 2)],
        ).validate(),
        throwsFormatException,
      );
    });

    test('rejects touching boxes', () {
      expect(
        () => StageConfig(
          id: 1,
          size: 4,
          trucks: const [Truck((0, 0), 0), Truck((2, 2), 0)],
          solution: const [(0, 1), (1, 2)],
        ).validate(),
        throwsFormatException,
      );
    });

    test('json parsing', () {
      final c = StageConfig.fromJson({
        'id': 7,
        'size': 4,
        'tier': 2,
        'trucks': [
          [0, 1, 3],
        ],
        'solution': [
          [0, 0],
        ],
        'tutorial': 'basic',
      });
      expect(c.trucks.single.color, 3);
      expect(c.solution.single, (0, 0));
      expect(c.tier, 2);
    });
  });

  group('marking', () {
    test('tap cycles none → box → cross → none', () {
      final s = play();
      const c = (1, 1);
      s.tap(c);
      expect(s.markAt(c), Mark.box);
      s.tap(c);
      expect(s.markAt(c), Mark.cross);
      s.tap(c);
      expect(s.markAt(c), Mark.none);
      expect(s.moves, 3);
    });

    test('trucks, outside cells and unstarted sessions cannot be marked', () {
      final idle = GameSession(small());
      expect(idle.tap((1, 1)), isFalse);
      final s = play();
      expect(s.tap((0, 1)), isFalse); // truck
      expect(s.tap((9, 9)), isFalse);
      expect(s.moves, 0);
    });

    test('undo restores the previous marks; reset clears and is undoable', () {
      final s = play();
      s.tap((0, 0));
      s.tap((1, 1));
      expect(s.undo(), isTrue);
      expect(s.markAt((1, 1)), Mark.none);
      expect(s.isBox((0, 0)), isTrue);
      s.reset();
      expect(s.boxesPlaced, 0);
      expect(s.undo(), isTrue);
      expect(s.isBox((0, 0)), isTrue);
    });

    test('line states follow the counts', () {
      final s = play();
      expect(s.rowState(0), LineState.open);
      expect(s.rowState(1), LineState.done); // clue 0
      s.setMark((0, 0), Mark.box);
      expect(s.rowState(0), LineState.done);
      s.setMark((0, 2), Mark.box);
      expect(s.rowState(0), LineState.over);
    });
  });

  group('rules feedback', () {
    test('auto crosses: far from trucks, next to a box, full lines', () {
      final s = play();
      expect(
        s.autoCrossReason((3, 3)),
        isNotNull,
      ); // (2,3) truck is adjacent → check another
      expect(s.autoCrossReason((1, 2)), isNotNull); // no truck neighbour
      expect(s.isCandidate((0, 0)), isTrue);
      s.setMark((2, 2), Mark.box);
      expect(s.autoCrossReason((3, 3)), '箱のとなり');
      expect(s.isCandidate((1, 0)), isFalse); // row 1 has clue 0
    });

    test('violations: touching boxes, no truck, too many in a line', () {
      final s = play();
      s.setMark((1, 2), Mark.box); // not next to a truck
      expect(s.violations, {(1, 2)});
      s.setMark((1, 2), Mark.none);
      s.setMark((0, 0), Mark.box);
      s.setMark((1, 1), Mark.box); // touches (0,0) diagonally, row 1 clue 0
      expect(s.violations, containsAll([(0, 0), (1, 1)]));
    });
  });

  group('clearing', () {
    test('placing exactly the solution clears the stage', () {
      final s = play();
      s.setMark((0, 0), Mark.box);
      s.setMark((2, 2), Mark.box);
      expect(s.isCleared, isFalse);
      s.setMark((3, 0), Mark.box);
      expect(s.isCleared, isTrue);
      expect(s.stars, 3);
      expect(s.score, greaterThan(0));
      expect(s.tap((1, 1)), isFalse); // locked after clear
    });

    test('an extra wrong box prevents clearing', () {
      final s = play();
      s.setMark((1, 1), Mark.box);
      for (final b in small().solution) {
        s.setMark(b, Mark.box);
      }
      expect(s.isCleared, isFalse);
      s.setMark((1, 1), Mark.none);
      expect(s.isCleared, isTrue);
    });

    test('stars drop with hints; free hints are consumed first', () {
      final s = GameSession(
        small(),
        modifiers: const SessionModifiers(extraHints: 1),
      )..start();
      expect(s.freeHints, 2);
      s.consumeHint();
      s.consumeHint();
      s.consumeHint(paid: true);
      expect(s.freeHints, 0);
      expect(s.hintsUsed, 3);
      for (final b in small().solution) {
        s.setMark(b, Mark.box);
      }
      expect(s.stars, 1);
    });
  });

  group('deduction hints', () {
    test('points out a wrong box first', () {
      final s = play();
      s.setMark((1, 1), Mark.box);
      final h = Deduction.next(s);
      expect(h.cell, (1, 1));
      expect(h.mark, Mark.none);
    });

    test('points out a wrong cross', () {
      final s = play();
      s.setMark((0, 0), Mark.cross);
      final h = Deduction.next(s);
      expect(h.cell, (0, 0));
      expect(h.mark, Mark.none);
    });

    test('every hint is correct and following hints solves the puzzle', () {
      final s = play();
      for (var i = 0; i < 50 && !s.isCleared; i++) {
        final h = Deduction.next(s);
        expect(h.reason, isNotEmpty);
        if (h.mark == Mark.box) expect(s.inSolution(h.cell), isTrue);
        if (h.mark == Mark.cross) expect(s.inSolution(h.cell), isFalse);
        s.setMark(h.cell, h.mark);
      }
      expect(s.isCleared, isTrue);
    });

    test('line pattern: two boxes in a run of three go to the ends', () {
      // Row 0 has three free cells in a row and needs two boxes.
      final c = StageConfig(
        id: 1,
        size: 4,
        trucks: const [Truck((1, 0), 0), Truck((1, 2), 0), Truck((1, 1), 0)],
        solution: const [(0, 0), (0, 2), (2, 1)],
      )..validate();
      final s = play(c);
      final h = Deduction.logical(s)!;
      expect(h.cell, (0, 0));
      expect(h.mark, Mark.box);
      expect(h.reason, contains('並べ方'));
    });
  });
}
