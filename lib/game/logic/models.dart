/// Pure puzzle models. No Flutter / Flame dependency so they are unit-testable.
library;

const int kColorCount = 6;

/// A grid cell (row, column).
typedef Cell = (int r, int c);

const orthogonal = <Cell>[(-1, 0), (1, 0), (0, -1), (0, 1)];
const around8 = <Cell>[
  (-1, -1),
  (-1, 0),
  (-1, 1),
  (0, -1),
  (0, 1),
  (1, -1),
  (1, 0),
  (1, 1),
];

/// What the player has put on a cell.
enum Mark {
  none,

  /// "A box goes here."
  box,

  /// "Definitely no box here" (player's note).
  cross,
}

class Truck {
  const Truck(this.cell, this.color);
  final Cell cell;
  final int color;
}

enum SessionStatus { ready, playing, cleared }

/// State of a row / column clue.
enum LineState { open, done, over }
