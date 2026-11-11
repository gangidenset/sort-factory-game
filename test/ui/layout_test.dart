import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/game/flame/board_layout.dart';

void main() {
  // Game-area sizes (screen minus HUD / safe areas), small phone → tablet.
  const sizes = [
    Size(320, 470),
    Size(360, 580),
    Size(390, 700),
    Size(430, 800),
    Size(460, 860),
    Size(768, 940),
  ];

  for (final size in sizes) {
    for (final lanes in [3, 4, 5, 6]) {
      for (final docks in [2, 3]) {
        test(
          'layout fits ${size.width}x${size.height} lanes=$lanes docks=$docks',
          () {
            final l = BoardLayout(
              size: size,
              lanes: lanes,
              maxDepth: 9,
              docks: docks,
              shelfSlots: 7,
            );
            final screen = Offset.zero & size;
            for (final r in l.all) {
              expect(
                screen.contains(r.topLeft) &&
                    screen.contains(r.bottomRight.translate(-0.01, -0.01)),
                isTrue,
                reason: '$r out of $screen',
              );
            }
            final rects = [...l.dockRects, l.shelfRect, ...l.laneRects];
            for (var i = 0; i < rects.length; i++) {
              for (var j = i + 1; j < rects.length; j++) {
                expect(
                  rects[i].overlaps(rects[j]),
                  isFalse,
                  reason: '${rects[i]} vs ${rects[j]}',
                );
              }
            }
            // Lanes are the tap targets: wide enough for a thumb.
            for (final r in l.laneRects) {
              expect(r.width, greaterThanOrEqualTo(44));
            }
            // The deepest package still fits inside its lane.
            final last = l.packageCenter(0, 8);
            expect(
              last.dy + l.pkgSize / 2,
              lessThanOrEqualTo(l.laneRects[0].bottom + 0.01),
            );
            expect(l.pkgSize, greaterThanOrEqualTo(26));
          },
        );
      }
    }
  }
}
