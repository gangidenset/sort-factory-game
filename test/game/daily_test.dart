import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/game/logic/daily.dart';
import 'package:sort_factory/game/logic/deduction.dart';
import 'package:sort_factory/game/logic/game_session.dart';
import 'package:sort_factory/game/logic/models.dart';

import 'stage_catalog_test.dart' show countSolutions;

DailyCatalog load() => DailyCatalog.fromJsonString(
  File('assets/stages/daily.json').readAsStringSync(),
);

void main() {
  test('pool covers about a year (7 weekdays x 53)', () {
    expect(load().totalPuzzles, 7 * 53);
  });

  test('same date → same puzzle; consecutive days differ', () {
    final c = load();
    final a = c.forDate(DateTime(2026, 11, 16, 8));
    final b = c.forDate(DateTime(2026, 11, 16, 23, 59));
    expect(a.solution, b.solution);
    expect(a.id, 20261116);
    final seen = <String>{};
    for (var i = 0; i < 371; i++) {
      final p = c.forDate(DateTime(2026, 11, 16 + i));
      seen.add(p.solution.toString() + p.trucks.map((t) => t.cell).toString());
    }
    expect(seen.length, 371, reason: 'no repeats within a year');
  });

  test('difficulty rises through the week', () {
    final c = load();
    final mon = c.forDate(DateTime(2026, 11, 16)); // Monday
    final sun = c.forDate(DateTime(2026, 11, 22)); // Sunday
    expect(mon.size, 6);
    expect(mon.tier, 1);
    expect(sun.size, 8);
    expect(sun.tier, 3);
    expect(DailyCatalog.label(DateTime(2026, 11, 16)), '11/16(月)');
    expect(DailyCatalog.levelOf(DateTime(2026, 11, 22)), 'むずかしい');
  });

  test('dates before the epoch still map to a puzzle', () {
    expect(load().forDate(DateTime(2025, 6, 1)).trucks, isNotEmpty);
  });

  test('every daily puzzle is valid, unique and solvable with hints', () {
    var i = 0;
    for (final st in load().all()) {
      i++;
      // Uniqueness is proven by the generator for all; re-check a sample
      // independently here to keep CI fast.
      if (i % 7 == 0) expect(countSolutions(st), 1, reason: 'daily #$i');
      final s = GameSession(st)..start();
      for (var k = 0; k < 400 && !s.isCleared; k++) {
        final h = Deduction.next(s);
        expect(s.inSolution(h.cell), h.mark == Mark.box, reason: 'daily #$i');
        s.setMark(h.cell, h.mark);
      }
      expect(s.isCleared, isTrue, reason: 'daily #$i');
    }
  });
}
