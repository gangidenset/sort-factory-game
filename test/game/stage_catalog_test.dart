import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/game/logic/deduction.dart';
import 'package:sort_factory/game/logic/game_session.dart';
import 'package:sort_factory/game/logic/models.dart';
import 'package:sort_factory/game/logic/stage_config.dart';
import 'package:sort_factory/game/logic/stage_repository.dart';

StageCatalog loadCatalog() => StageCatalog.fromJsonString(
  File('assets/stages/stages.json').readAsStringSync(),
);

/// Counts solutions (up to 2) by exhaustive search, independently of the
/// Python generator: box cells must be next to a truck, never touch, match
/// all clues, and admit a one-to-one pairing with the trucks.
int countSolutions(StageConfig st) {
  final n = st.size;
  final trucks = [for (final t in st.trucks) t.cell];
  final truckSet = trucks.toSet();
  final cells = <Cell>[
    for (var r = 0; r < n; r++)
      for (var c = 0; c < n; c++)
        if (!truckSet.contains((r, c)) &&
            orthogonal.any((d) => truckSet.contains((r + d.$1, c + d.$2))))
          (r, c),
  ];
  final rows = List.filled(n, 0), cols = List.filled(n, 0);
  final boxes = <Cell>{};
  var found = 0;

  bool matching() {
    final list = boxes.toList();
    if (list.length != trucks.length) return false;
    final owner = <int, int>{};
    bool assign(int b, Set<int> seen) {
      for (var t = 0; t < trucks.length; t++) {
        final d =
            (trucks[t].$1 - list[b].$1).abs() +
            (trucks[t].$2 - list[b].$2).abs();
        if (d != 1 || !seen.add(t)) continue;
        if (!owner.containsKey(t) || assign(owner[t]!, seen)) {
          owner[t] = b;
          return true;
        }
      }
      return false;
    }

    for (var b = 0; b < list.length; b++) {
      if (!assign(b, {})) return false;
    }
    return true;
  }

  void rec(int i) {
    if (found >= 2) return;
    if (i == cells.length) {
      for (var k = 0; k < n; k++) {
        if (rows[k] != st.rowClues[k] || cols[k] != st.colClues[k]) return;
      }
      if (matching()) found++;
      return;
    }
    final (r, c) = cells[i];
    if (rows[r] < st.rowClues[r] &&
        cols[c] < st.colClues[c] &&
        !around8.any((d) => boxes.contains((r + d.$1, c + d.$2)))) {
      boxes.add((r, c));
      rows[r]++;
      cols[c]++;
      rec(i + 1);
      boxes.remove((r, c));
      rows[r]--;
      cols[c]--;
    }
    rec(i + 1);
  }

  rec(0);
  return found;
}

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
    const st = '{"id":1,"size":4,"trucks":[[0,1,0]],"solution":[[0,0]]}';
    expect(
      () => StageCatalog.fromJsonString('{"stages":[$st,$st]}'),
      throwsFormatException,
    );
  });

  test('every stage has exactly one solution', () {
    for (final st in loadCatalog().stages) {
      expect(countSolutions(st), 1, reason: 'stage ${st.id}');
    }
  });

  test('tier 1-2 stages are solved by the hint rules alone (no reveal)', () {
    for (final st in loadCatalog().stages.where((s) => s.tier <= 2)) {
      final s = GameSession(st)..start();
      for (var i = 0; i < 400 && !s.isCleared; i++) {
        final h = Deduction.logical(s);
        expect(h, isNotNull, reason: 'stage ${st.id} got stuck');
        expect(
          s.inSolution(h!.cell),
          h.mark == Mark.box,
          reason: 'stage ${st.id} wrong hint',
        );
        s.setMark(h.cell, h.mark);
      }
      expect(s.isCleared, isTrue, reason: 'stage ${st.id}');
    }
  });

  test('following hints solves every stage and hints are never wrong', () {
    for (final st in loadCatalog().stages) {
      final s = GameSession(st)..start();
      for (var i = 0; i < 400 && !s.isCleared; i++) {
        final h = Deduction.next(s);
        expect(
          s.inSolution(h.cell),
          h.mark == Mark.box,
          reason: 'stage ${st.id}',
        );
        s.setMark(h.cell, h.mark);
      }
      expect(s.isCleared, isTrue, reason: 'stage ${st.id}');
    }
  });
}
