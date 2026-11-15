import 'game_session.dart';
import 'models.dart';

/// A hint: what to do on which cell, and the reasoning in plain words so the
/// player learns the technique instead of just being told the answer.
class Hint {
  const Hint(this.cell, this.mark, this.reason, {this.related = const []});

  final Cell cell;

  /// Mark to apply ([Mark.none] = remove a wrong mark).
  final Mark mark;
  final String reason;

  /// Cells to highlight as the evidence (the row, the truck...).
  final List<Cell> related;
}

/// Human-style deduction, mirroring the rule tiers of `tool/gen_stages.py`.
class Deduction {
  const Deduction._();

  /// Next logical step for [s]. Mistakes are pointed out first; if no simple
  /// rule applies, falls back to revealing one correct box.
  static Hint next(GameSession s) {
    final wrong = s.wrongBoxes;
    if (wrong.isNotEmpty) {
      return Hint(wrong.first, Mark.none, 'この箱はまちがい。タップして消そう。');
    }
    final wrongX = s.wrongCrosses;
    if (wrongX.isNotEmpty) {
      return Hint(wrongX.first, Mark.none, 'この×はまちがい。タップして消そう。');
    }
    return _counting(s) ?? _lonelyTruck(s) ?? _linePattern(s) ?? _reveal(s);
  }

  /// Only the pure deduction rules (no mistake check, no reveal). Used by
  /// tests to prove easy stages are solvable with simple rules.
  static Hint? logical(GameSession s) =>
      _counting(s) ?? _lonelyTruck(s) ?? _linePattern(s);

  static List<Cell> _line(GameSession s, bool row, int i) => [
    for (var k = 0; k < s.size; k++) row ? (i, k) : (k, i),
  ];

  static int _need(GameSession s, bool row, int i) => row
      ? s.config.rowClues[i] - s.rowCount(i)
      : s.config.colClues[i] - s.colCount(i);

  static String _lineName(bool row, int i) => row ? 'この行（横）' : 'この列（たて）';

  /// Tier 1: a line whose remaining free cells must all be boxes.
  static Hint? _counting(GameSession s) {
    for (final row in [true, false]) {
      for (var i = 0; i < s.size; i++) {
        final need = _need(s, row, i);
        if (need <= 0) continue;
        final line = _line(s, row, i);
        final cands = line.where(s.isCandidate).toList();
        if (cands.length == need) {
          return Hint(
            cands.first,
            Mark.box,
            '${_lineName(row, i)}は箱があと$need個。置けるマスも$need個しか残っていない → ここは箱！',
            related: line,
          );
        }
      }
    }
    return null;
  }

  /// Tier 1: a truck without a box and with a single free neighbour.
  static Hint? _lonelyTruck(GameSession s) {
    for (final t in s.config.trucks) {
      final adj = [
        for (final d in orthogonal) (t.cell.$1 + d.$1, t.cell.$2 + d.$2),
      ];
      if (adj.any(s.isBox)) continue;
      final free = adj.where(s.isCandidate).toList();
      if (free.length == 1) {
        return Hint(
          free.first,
          Mark.box,
          'このトラックの箱を置けるマスは、もうここしか残っていない → ここは箱！',
          related: [t.cell],
        );
      }
    }
    return null;
  }

  /// Tier 2: cells used by every (or no) way to fill a line.
  static Hint? _linePattern(GameSession s) {
    for (final row in [true, false]) {
      for (var i = 0; i < s.size; i++) {
        final need = _need(s, row, i);
        if (need <= 0) continue;
        final line = _line(s, row, i);
        final cands = line.where(s.isCandidate).toList();
        final options = <List<Cell>>[];
        void pick(int from, List<Cell> acc) {
          if (acc.length == need) {
            options.add(List.of(acc));
            return;
          }
          for (var k = from; k < cands.length; k++) {
            final c = cands[k];
            if (acc.isNotEmpty) {
              final p = acc.last;
              // Boxes may not be neighbours within the line.
              if ((p.$1 - c.$1).abs() + (p.$2 - c.$2).abs() <= 1) continue;
            }
            acc.add(c);
            pick(k + 1, acc);
            acc.removeLast();
          }
        }

        pick(0, []);
        if (options.isEmpty) continue;
        for (final c in cands) {
          final uses = options.where((o) => o.contains(c)).length;
          if (uses == options.length) {
            return Hint(
              c,
              Mark.box,
              '${_lineName(row, i)}に箱を$need個、くっつけずに置く方法を全部考えると、'
              'どの置き方でもここに箱が入る → ここは箱！',
              related: line,
            );
          }
          if (uses == 0) {
            return Hint(
              c,
              Mark.cross,
              'ここに箱を置くと、${_lineName(row, i)}の残りの箱が入りきらない → ここは×',
              related: line,
            );
          }
        }
      }
    }
    return null;
  }

  static Hint _reveal(GameSession s) {
    final cell = s.config.solution.firstWhere((b) => !s.isBox(b));
    return Hint(cell, Mark.box, 'ここは箱です。（「もしここが×なら？」と先を読むと、どこかの数字が合わなくなります）');
  }
}
