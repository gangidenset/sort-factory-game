import 'dart:math' as math;
import 'dart:ui';

/// Computes screen rectangles for the board. Pure, so it can be tested on
/// many screen sizes to make sure nothing overlaps or leaves the screen.
class BoardLayout {
  BoardLayout({
    required Size size,
    required int docks,
    required int beltCapacity,
    required int bufferSlots,
  }) {
    final w = size.width, h = size.height;
    final pad = math.max(8.0, w * 0.03);

    // Docks along the bottom.
    final dockH = math.min(h * 0.24, math.max(96.0, w * 0.36));
    final dockW = (w - pad * (docks + 1)) / docks;
    final dockTop = h - pad - dockH;
    dockRects = [
      for (var i = 0; i < docks; i++)
        Rect.fromLTWH(pad + i * (dockW + pad), dockTop, dockW, dockH),
    ];

    // Belt: vertical, centered, ending just above the docks.
    final beltBottom = dockTop - pad * 1.5;
    final available = beltBottom - pad;
    pkgSize = math.min(w * 0.17, available / (beltCapacity * 1.15 + 0.6));
    spacing = pkgSize * 1.15;
    final beltW = pkgSize * 1.45;
    final beltH = spacing * beltCapacity + pkgSize * 0.5;
    beltRect = Rect.fromLTWH((w - beltW) / 2, beltBottom - beltH, beltW, beltH);
    frontCenter = Offset(w / 2, beltBottom - pkgSize * 0.65);

    // Side zones next to the front of the belt.
    final sideW = beltRect.left - pad * 2;
    // Keep touch targets >= 48 logical px even on very small screens.
    final slot = math.min(sideW, math.max(48.0, pkgSize * 1.35));
    bufferRects = [
      for (var i = 0; i < bufferSlots; i++)
        Rect.fromLTWH(
          beltRect.left - pad - slot,
          beltBottom - slot - i * (slot + pad * 0.8),
          slot,
          slot,
        ),
    ];
    chuteRect = Rect.fromLTWH(
      beltRect.right + pad,
      beltBottom - slot,
      slot,
      slot,
    );
  }

  late final List<Rect> dockRects;
  late final List<Rect> bufferRects;
  late final Rect chuteRect;
  late final Rect beltRect;
  late final Offset frontCenter;
  late final double pkgSize;
  late final double spacing;

  Offset beltPosition(double pos) =>
      Offset(frontCenter.dx, frontCenter.dy - pos * spacing);

  Rect get frontRect => Rect.fromCenter(
    center: frontCenter,
    width: pkgSize * 1.5,
    height: pkgSize * 1.5,
  );

  /// All interactive rects, for overlap tests.
  List<Rect> get interactive => [
    ...dockRects,
    ...bufferRects,
    chuteRect,
    frontRect,
  ];
}
