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

  /// Color of a box that has not been loaded onto a truck yet (color = -1).
  static const cardboard = Color(0xFFD9A066);

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

    final base = hidden
        ? const Color(0xFFB8C0CC)
        : (color < 0 ? cardboard : packageColors[color]);
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

  /// Compact truck that fits one grid cell (facing right).
  void drawCellTruck(
    Canvas c,
    Rect cell,
    int color, {
    double alpha = 1,
    bool loaded = false,
    double wheelSpin = 0,
  }) {
    final col = packageColors[color];
    final w = cell.width, h = cell.height;
    final cargo = Rect.fromLTWH(
      cell.left + w * 0.08,
      cell.top + h * 0.24,
      w * 0.56,
      h * 0.44,
    );
    final cab = Rect.fromLTWH(
      cargo.right + w * 0.02,
      cargo.top + h * 0.1,
      w * 0.26,
      h * 0.34,
    );
    _fill.color = Colors.black.withValues(alpha: 0.12 * alpha);
    c.drawRRect(
      RRect.fromRectXY(
        Rect.fromLTRB(
          cargo.left,
          cargo.bottom + h * 0.02,
          cab.right,
          cargo.bottom + h * 0.14,
        ),
        4,
        4,
      ),
      _fill,
    );
    _fill.color = Color.lerp(col, Colors.black, 0.2)!.withValues(alpha: alpha);
    c.drawRRect(
      RRect.fromRectAndCorners(
        cab,
        topRight: Radius.circular(w * 0.1),
        topLeft: const Radius.circular(2),
        bottomLeft: const Radius.circular(2),
        bottomRight: const Radius.circular(3),
      ),
      _fill,
    );
    _fill.color = const Color(0xFFDDF3FF).withValues(alpha: alpha);
    c.drawRRect(
      RRect.fromRectXY(
        Rect.fromLTWH(
          cab.left + cab.width * 0.25,
          cab.top + cab.height * 0.15,
          cab.width * 0.6,
          cab.height * 0.4,
        ),
        2,
        2,
      ),
      _fill,
    );
    _fill.color = (loaded ? col : Colors.white).withValues(alpha: alpha);
    final rr = RRect.fromRectXY(cargo, w * 0.07, w * 0.07);
    c.drawRRect(rr, _fill);
    _stroke
      ..color = col.withValues(alpha: alpha)
      ..strokeWidth = math.max(2.5, w * 0.06);
    c.drawRRect(rr, _stroke);
    if (loaded) _face(c, cargo.center, cargo.height * 1.5, alpha, happy: true);
    final wy = cargo.bottom + h * 0.07;
    for (final x in [
      cargo.left + cargo.width * 0.25,
      cargo.right - cargo.width * 0.15,
      cab.center.dx,
    ]) {
      _fill.color = ink.withValues(alpha: alpha);
      c.drawCircle(Offset(x, wy), h * 0.085, _fill);
      _fill.color = const Color(0xFFBFC7D2).withValues(alpha: alpha);
      c.drawCircle(
        Offset(
          x + math.cos(wheelSpin) * h * 0.02,
          wy + math.sin(wheelSpin) * h * 0.02,
        ),
        h * 0.035,
        _fill,
      );
    }
  }
}
