import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/game/flame/board_layout.dart';

void main() {
  // Game area sizes (screen minus HUD/safe areas) from small to tall phones
  // and tablets.
  const sizes = [
    Size(320, 460), // iPhone SE 1st gen class
    Size(360, 560),
    Size(375, 580),
    Size(390, 700),
    Size(412, 760),
    Size(430, 800),
    Size(768, 900), // tablet portrait
  ];

  for (final size in sizes) {
    for (final docks in [2, 3, 4]) {
      for (final buffer in [0, 1, 3]) {
        test(
          'layout fits ${size.width}x${size.height} docks=$docks buf=$buffer',
          () {
            final l = BoardLayout(
              size: size,
              docks: docks,
              beltCapacity: 8,
              bufferSlots: buffer,
            );
            final screen = Offset.zero & size;
            for (final r in [...l.interactive, l.beltRect]) {
              expect(
                screen.contains(r.topLeft) &&
                    screen.contains(r.bottomRight.translate(-0.01, -0.01)),
                isTrue,
                reason: 'rect $r out of $screen',
              );
            }
            final rects = [...l.dockRects, ...l.bufferRects, l.chuteRect];
            for (var i = 0; i < rects.length; i++) {
              for (var j = i + 1; j < rects.length; j++) {
                expect(
                  rects[i].overlaps(rects[j]),
                  isFalse,
                  reason: '${rects[i]} overlaps ${rects[j]}',
                );
              }
              expect(rects[i].overlaps(l.beltRect), isFalse);
            }
            // Touch targets at least 44pt.
            for (final r in rects) {
              expect(
                r.shortestSide,
                greaterThanOrEqualTo(44),
                reason: '$r too small',
              );
            }
          },
        );
      }
    }
  }
}
