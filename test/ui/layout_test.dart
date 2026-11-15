import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/game/flame/board_layout.dart';

void main() {
  // Game-area sizes (screen minus HUD, rule panel and safe areas).
  const sizes = [
    Size(320, 360),
    Size(360, 460),
    Size(390, 600),
    Size(430, 700),
    Size(460, 760),
    Size(768, 820),
  ];

  for (final size in sizes) {
    for (final n in [4, 5, 6, 7, 8]) {
      test('grid fits ${size.width}x${size.height} n=$n', () {
        final l = BoardLayout(size: size, n: n);
        final screen = Offset.zero & size;
        expect(
          screen.contains(l.bounds.topLeft),
          isTrue,
          reason: '${l.bounds}',
        );
        expect(
          screen.contains(l.bounds.bottomRight.translate(-0.01, -0.01)),
          isTrue,
          reason: '${l.bounds}',
        );
        // Cells stay tappable even at 8x8 on the smallest phone.
        expect(l.cell, greaterThanOrEqualTo(32));
        expect(l.cellAt(l.cellRect((n - 1, n - 1)).center), (n - 1, n - 1));
        expect(l.cellAt(l.cellRect((0, 0)).center), (0, 0));
        expect(l.cellAt(l.colClue(0)), isNull);
      });
    }
  }
}
