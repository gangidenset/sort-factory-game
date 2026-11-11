import 'dart:math' as math;
import 'dart:ui';

/// Screen rectangles for the puzzle board. Pure, so it can be tested on many
/// screen sizes to ensure nothing overlaps or leaves the screen.
///
/// ```
///  NEXT ▭▭▭▭           (truck queue)
///  [truck][truck][truck] (docks)
///  [□][□][□][□][□]      (shelf)
///  |■| |■| |■| |■|       (lanes; front package on top)
///  |■| |■| |■| |■|
/// ```
class BoardLayout {
  BoardLayout({
    required Size size,
    required int lanes,
    required int maxDepth,
    required int docks,
    required int shelfSlots,
  }) {
    final w = size.width, h = size.height;
    pad = math.max(8.0, w * 0.025);

    queueRect = Rect.fromLTWH(pad, pad * 0.5, w - pad * 2, 26);

    final dockTop = queueRect.bottom + pad * 0.5;
    final dockW = (w - pad * (docks + 1)) / docks;
    final dockH = math.min(math.min(h * 0.17, 112.0), dockW * 0.75);
    dockRects = [
      for (var i = 0; i < docks; i++)
        Rect.fromLTWH(pad + i * (dockW + pad), dockTop, dockW, dockH),
    ];

    final slots = math.max(shelfSlots, 1);
    final slot = math.min(math.min((w - pad * 2) / slots - 6, 54.0), h * 0.08);
    final shelfW = slots * (slot + 6) - 6;
    final shelfTop = dockTop + dockH + pad * 1.4;
    shelfRect = Rect.fromLTWH(
      (w - shelfW) / 2 - 8,
      shelfTop,
      shelfW + 16,
      slot + 16,
    );
    shelfSlotRects = [
      for (var i = 0; i < slots; i++)
        Rect.fromLTWH(
          shelfRect.left + 8 + i * (slot + 6),
          shelfTop + 8,
          slot,
          slot,
        ),
    ];

    final laneTop = shelfRect.bottom + pad * 1.4;
    final laneW = (w - pad * (lanes + 1)) / lanes;
    final laneH = h - laneTop - pad;
    laneRects = [
      for (var i = 0; i < lanes; i++)
        Rect.fromLTWH(pad + i * (laneW + pad), laneTop, laneW, laneH),
    ];
    final depth = math.max(maxDepth, 1);
    pkgSize = math.min(
      math.min(laneW * 0.8, 62.0),
      (laneH - pad) / (depth * 1.08 + 0.1),
    );
    pkgStep = pkgSize * 1.08;
  }

  late final double pad;
  late final Rect queueRect;
  late final List<Rect> dockRects;
  late final Rect shelfRect;
  late final List<Rect> shelfSlotRects;
  late final List<Rect> laneRects;
  late final double pkgSize;
  late final double pkgStep;

  /// Center of the package at [index] (0 = front) in [lane].
  Offset packageCenter(int lane, int index) {
    final r = laneRects[lane];
    return Offset(r.center.dx, r.top + pkgSize * 0.62 + index * pkgStep);
  }

  int? laneAt(Offset p) {
    for (var i = 0; i < laneRects.length; i++) {
      if (laneRects[i].inflate(pad / 2).contains(p)) return i;
    }
    return null;
  }

  List<Rect> get all => [...dockRects, shelfRect, ...laneRects];
}
