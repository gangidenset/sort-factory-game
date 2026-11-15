import 'dart:math' as math;
import 'dart:ui';

import '../logic/models.dart';

/// Screen geometry of the puzzle grid with clue bands on the top and left.
/// Pure, so it can be tested on many screen sizes.
class BoardLayout {
  BoardLayout({required Size size, required this.n}) {
    final pad = math.max(8.0, size.width * 0.03);
    // Clue band is 0.62 of a cell: solve for the largest cell that fits.
    final byW = (size.width - pad * 2) / (n + 0.62);
    final byH = (size.height - pad * 2) / (n + 0.62);
    cell = math.min(math.min(byW, byH), 72.0);
    band = cell * 0.62;
    final total = band + cell * n;
    final left = (size.width - total) / 2;
    final top = math.min(pad * 1.5, (size.height - total) / 2);
    grid = Rect.fromLTWH(left + band, top + band, cell * n, cell * n);
  }

  final int n;
  late final double cell;
  late final double band;
  late final Rect grid;

  Rect cellRect(Cell c) => Rect.fromLTWH(
    grid.left + c.$2 * cell,
    grid.top + c.$1 * cell,
    cell,
    cell,
  );

  Offset colClue(int c) =>
      Offset(grid.left + (c + 0.5) * cell, grid.top - band / 2);
  Offset rowClue(int r) =>
      Offset(grid.left - band / 2, grid.top + (r + 0.5) * cell);

  Rect get bounds =>
      Rect.fromLTRB(grid.left - band, grid.top - band, grid.right, grid.bottom);

  Cell? cellAt(Offset p) {
    if (!grid.contains(p)) return null;
    return (
      ((p.dy - grid.top) / cell).floor().clamp(0, n - 1),
      ((p.dx - grid.left) / cell).floor().clamp(0, n - 1),
    );
  }
}
