import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart' show Colors;

import '../../ui/palette.dart';

/// Draws boxes and trucks with plain canvas calls (no bitmap assets → crisp
/// on every screen, tiny app). Boxes and trucks have little faces for charm.
class PackagePainter {
  PackagePainter(this.boxStyle);

  final String boxStyle;
  final _fill = Paint();
  final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  static const ink = Color(0xFF1F2733);

  void drawBox(
    Canvas c,
    int color,
    Offset center,
    double size, {
    bool hidden = false,
    double alpha = 1,
    double squash = 0,
    bool happy = false,
    bool glow = false,
  }) {
    final w = size * (1 + squash * 0.15), h = size * (1 - squash * 0.15);
    final r = Rect.fromCenter(
      center: center.translate(0, squash * size * 0.07),
      width: w,
      height: h,
    );
    final round = boxStyle == 'box_round';
    final rr = RRect.fromRectXY(
      r,
      round ? w / 2 : size * 0.2,
      round ? h / 2 : size * 0.2,
    );

    if (glow) {
      _fill.color = const Color(0xFFFFE066).withValues(alpha: 0.75 * alpha);
      c.drawRRect(rr.inflate(size * 0.12), _fill);
    }
    _fill.color = Colors.black.withValues(alpha: 0.12 * alpha);
    c.drawRRect(rr.shift(Offset(0, size * 0.06)), _fill);

    final base = hidden ? const Color(0xFFB8C0CC) : packageColors[color];
    _fill.color = base.withValues(alpha: alpha);
    c.drawRRect(rr, _fill);
    // Top highlight.
    _fill.color = Colors.white.withValues(alpha: 0.22 * alpha);
    c.drawRRect(
      RRect.fromRectXY(
        Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.32),
        size * 0.2,
        size * 0.2,
      ),
      _fill,
    );

    if (hidden) {
      _questionMark(c, r.center, size * 0.5, alpha);
      return;
    }
    _decorate(c, r, base, size, alpha);
    _face(c, r.center.translate(0, size * 0.06), size, alpha, happy: happy);
  }

  void _decorate(Canvas c, Rect r, Color color, double size, double alpha) {
    switch (boxStyle) {
      case 'box_gift':
        _fill.color = Colors.white.withValues(alpha: 0.7 * alpha);
        c.drawRect(
          Rect.fromCenter(
            center: r.topCenter.translate(0, size * 0.12),
            width: size * 0.12,
            height: size * 0.24,
          ),
          _fill,
        );
      case 'box_crate':
        _stroke
          ..color = Color.lerp(
            color,
            Colors.black,
            0.25,
          )!.withValues(alpha: alpha)
          ..strokeWidth = size * 0.04;
        c.drawRRect(
          RRect.fromRectXY(r.deflate(size * 0.07), size * 0.12, size * 0.12),
          _stroke,
        );
      case 'box_gold':
        _stroke
          ..color = const Color(0xFFFFD54F).withValues(alpha: alpha)
          ..strokeWidth = size * 0.08;
        c.drawRRect(
          RRect.fromRectXY(r.deflate(size * 0.05), size * 0.16, size * 0.16),
          _stroke,
        );
      default:
        // Tape strip.
        _fill.color = Colors.white.withValues(alpha: 0.28 * alpha);
        c.drawRect(
          Rect.fromLTWH(
            r.center.dx - size * 0.08,
            r.top,
            size * 0.16,
            size * 0.22,
          ),
          _fill,
        );
    }
  }

  void _face(
    Canvas c,
    Offset center,
    double size,
    double alpha, {
    bool happy = false,
  }) {
    _fill.color = ink.withValues(alpha: 0.85 * alpha);
    final eyeY = center.dy - size * 0.06;
    final dx = size * 0.15;
    if (happy) {
      _stroke
        ..color = ink.withValues(alpha: 0.85 * alpha)
        ..strokeWidth = size * 0.06;
      for (final x in [center.dx - dx, center.dx + dx]) {
        c.drawArc(
          Rect.fromCircle(
            center: Offset(x, eyeY + size * 0.03),
            radius: size * 0.06,
          ),
          math.pi,
          math.pi,
          false,
          _stroke,
        );
      }
    } else {
      c.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx - dx, eyeY),
          width: size * 0.08,
          height: size * 0.11,
        ),
        _fill,
      );
      c.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx + dx, eyeY),
          width: size * 0.08,
          height: size * 0.11,
        ),
        _fill,
      );
    }
    _stroke
      ..color = ink.withValues(alpha: 0.85 * alpha)
      ..strokeWidth = size * 0.05;
    c.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + size * 0.06),
        width: size * 0.16,
        height: size * 0.12,
      ),
      0.2,
      math.pi - 0.4,
      false,
      _stroke,
    );
    // Cheeks.
    _fill.color = const Color(0xFFFF8FA3).withValues(alpha: 0.45 * alpha);
    c.drawCircle(
      Offset(center.dx - size * 0.27, center.dy + size * 0.03),
      size * 0.06,
      _fill,
    );
    c.drawCircle(
      Offset(center.dx + size * 0.27, center.dy + size * 0.03),
      size * 0.06,
      _fill,
    );
  }

  void _questionMark(Canvas c, Offset center, double size, double alpha) {
    _stroke
      ..color = Colors.white.withValues(alpha: alpha)
      ..strokeWidth = size * 0.16;
    final r = size * 0.28;
    final p = Path()
      ..addArc(
        Rect.fromCircle(center: center.translate(0, -r * 0.6), radius: r),
        math.pi * 1.1,
        math.pi * 1.4,
      )
      ..lineTo(center.dx, center.dy + r * 0.5);
    c.drawPath(p, _stroke);
    _fill.color = Colors.white.withValues(alpha: alpha);
    c.drawCircle(center.translate(0, r * 1.25), size * 0.09, _fill);
  }

  /// Truck facing right: cargo box (with seat cells) + cab with a face.
  void drawTruck(
    Canvas c,
    Rect dock,
    int color,
    int capacity,
    int filled, {
    double alpha = 1,
    double bounce = 0,
    double wheelSpin = 0,
  }) {
    final dy = -bounce * dock.height * 0.08;
    final cargo = _shift(BoardTruck.cargo(dock), dy);
    final cab = _shift(BoardTruck.cab(dock), dy);
    final col = packageColors[color];

    // Shadow.
    _fill.color = Colors.black.withValues(alpha: 0.12 * alpha);
    c.drawRRect(
      RRect.fromRectXY(
        Rect.fromLTRB(
          cargo.left,
          cargo.bottom,
          cab.right,
          cargo.bottom + dock.height * 0.12,
        ),
        8,
        8,
      ),
      _fill,
    );

    // Cab.
    _fill.color = Color.lerp(col, Colors.black, 0.18)!.withValues(alpha: alpha);
    c.drawRRect(
      RRect.fromRectAndCorners(
        cab,
        topRight: Radius.circular(cab.width * 0.45),
        topLeft: const Radius.circular(4),
        bottomRight: const Radius.circular(6),
        bottomLeft: const Radius.circular(4),
      ),
      _fill,
    );
    _fill.color = const Color(0xFFDDF3FF).withValues(alpha: alpha);
    final win = Rect.fromLTWH(
      cab.left + cab.width * 0.2,
      cab.top + cab.height * 0.14,
      cab.width * 0.62,
      cab.height * 0.32,
    );
    c.drawRRect(RRect.fromRectXY(win, 4, 4), _fill);
    _fill.color = PackagePainter.ink.withValues(alpha: alpha);
    c.drawCircle(
      Offset(
        win.center.dx - win.width * 0.18,
        win.center.dy + win.height * 0.05,
      ),
      win.height * 0.13,
      _fill,
    );
    c.drawCircle(
      Offset(
        win.center.dx + win.width * 0.18,
        win.center.dy + win.height * 0.05,
      ),
      win.height * 0.13,
      _fill,
    );

    // Cargo box.
    _fill.color = Colors.white.withValues(alpha: alpha);
    final cargoRR = RRect.fromRectXY(cargo, 8, 8);
    c.drawRRect(cargoRR, _fill);
    _stroke
      ..color = col.withValues(alpha: alpha)
      ..strokeWidth = math.max(3, dock.height * 0.05);
    c.drawRRect(cargoRR, _stroke);
    _fill.color = col.withValues(alpha: 0.16 * alpha);
    c.drawRRect(cargoRR.deflate(2), _fill);

    // Seats.
    final cell = cargo.width / capacity;
    final box = math.min(cell * 0.8, cargo.height * 0.72);
    for (var i = 0; i < capacity; i++) {
      final ctr = Offset(cargo.left + cell * (i + 0.5), cargo.center.dy);
      if (i < filled) {
        drawBox(c, color, ctr, box, alpha: alpha, happy: true);
      } else {
        _stroke
          ..color = col.withValues(alpha: 0.45 * alpha)
          ..strokeWidth = 2;
        c.drawRRect(
          RRect.fromRectXY(
            Rect.fromCenter(center: ctr, width: box, height: box),
            box * 0.2,
            box * 0.2,
          ),
          _stroke,
        );
      }
    }

    // Wheels.
    final wy = cargo.bottom + dock.height * 0.06;
    for (final x in [
      cargo.left + cargo.width * 0.22,
      cargo.right - cargo.width * 0.12,
      cab.center.dx,
    ]) {
      _fill.color = PackagePainter.ink.withValues(alpha: alpha);
      c.drawCircle(Offset(x, wy), dock.height * 0.1, _fill);
      _fill.color = const Color(0xFFBFC7D2).withValues(alpha: alpha);
      c.drawCircle(Offset(x, wy), dock.height * 0.045, _fill);
      _stroke
        ..color = PackagePainter.ink.withValues(alpha: alpha)
        ..strokeWidth = 2;
      c.drawLine(
        Offset(x, wy),
        Offset(
          x + math.cos(wheelSpin) * dock.height * 0.045,
          wy + math.sin(wheelSpin) * dock.height * 0.045,
        ),
        _stroke,
      );
    }
  }

  static Rect _shift(Rect r, double dy) => r.translate(0, dy);

  /// Tiny truck icon for the queue strip.
  void drawMiniTruck(
    Canvas c,
    Offset center,
    double h,
    int color, {
    double alpha = 1,
  }) {
    final col = packageColors[color];
    final cargo = Rect.fromCenter(
      center: center.translate(-h * 0.25, 0),
      width: h * 1.3,
      height: h * 0.8,
    );
    final cab = Rect.fromLTWH(
      cargo.right + 1,
      cargo.top + h * 0.2,
      h * 0.5,
      h * 0.6,
    );
    _fill.color = col.withValues(alpha: alpha);
    c.drawRRect(RRect.fromRectXY(cargo, 3, 3), _fill);
    _fill.color = Color.lerp(col, Colors.black, 0.2)!.withValues(alpha: alpha);
    c.drawRRect(RRect.fromRectXY(cab, 3, 3), _fill);
  }
}

/// Geometry shared by the painter and layout for trucks inside a dock rect.
class BoardTruck {
  static Rect cargo(Rect dock) => Rect.fromLTWH(
    dock.left + dock.width * 0.04,
    dock.top + dock.height * 0.12,
    dock.width * 0.7,
    dock.height * 0.62,
  );

  static Rect cab(Rect dock) {
    final cg = cargo(dock);
    return Rect.fromLTWH(
      cg.right + dock.width * 0.02,
      cg.top + cg.height * 0.18,
      dock.width * 0.2,
      cg.height * 0.82,
    );
  }

  static Offset seat(Rect dock, int seat, int capacity) {
    final cg = cargo(dock);
    final cell = cg.width / capacity;
    return Offset(cg.left + cell * (seat + 0.5), cg.center.dy);
  }

  static double seatBox(Rect dock, int capacity) {
    final cg = cargo(dock);
    return math.min(cg.width / capacity * 0.8, cg.height * 0.72);
  }
}
