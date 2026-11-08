import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart' show Colors;

import '../../ui/palette.dart';
import '../logic/models.dart';

/// Draws packages, marks and requirement badges with plain canvas calls
/// (no bitmap assets → crisp on every screen density, tiny app size).
class PackagePainter {
  PackagePainter(this.boxStyle);

  final String boxStyle;

  final _fill = Paint();
  final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  void drawPackage(
    Canvas c,
    Package p,
    Offset center,
    double size, {
    double alpha = 1,
    bool highlight = false,
  }) {
    final color = packageColors[p.color];
    final r = Rect.fromCenter(center: center, width: size, height: size);
    final rr = boxStyle == 'box_round'
        ? RRect.fromRectXY(r, size / 2, size / 2)
        : RRect.fromRectXY(r, size * 0.16, size * 0.16);

    // Shadow
    _fill.color = const Color(0x33000000).withValues(alpha: 0.2 * alpha);
    c.drawRRect(rr.shift(Offset(0, size * 0.06)), _fill);

    _fill.color = color.withValues(alpha: alpha);
    c.drawRRect(rr, _fill);

    _decorate(c, r, color, size, alpha);

    if (p.kind == PackageKind.shifting && p.colorB != null) {
      // Show the "other" color as a corner flag + a cycle arrow.
      final other = p.color == p.colorA ? p.colorB! : p.colorA;
      final phase = (p.age % p.shiftPeriod) / p.shiftPeriod;
      _fill.color = packageColors[other].withValues(alpha: alpha);
      final tri = Path()
        ..moveTo(r.right - size * 0.42, r.top)
        ..lineTo(r.right - size * 0.16, r.top)
        ..arcToPoint(
          Offset(r.right, r.top + size * 0.16),
          radius: Radius.circular(size * 0.16),
        )
        ..lineTo(r.right, r.top + size * 0.42)
        ..close();
      c.drawPath(tri, _fill);
      // Progress ring that shows when the color will flip.
      _stroke
        ..color = Colors.white.withValues(alpha: 0.9 * alpha)
        ..strokeWidth = size * 0.06;
      c.drawArc(
        Rect.fromCircle(center: center, radius: size * 0.42),
        -math.pi / 2,
        2 * math.pi * phase,
        false,
        _stroke,
      );
    }

    if (p.mark != kMarkNone) {
      drawMark(c, p.mark, center, size * 0.42, alpha: alpha);
    }

    if (p.kind == PackageKind.timed && p.timeLimit != null) {
      final frac = (p.remaining! / p.timeLimit!).clamp(0.0, 1.0);
      final urgent = p.remaining! < 3;
      _stroke
        ..color = (urgent ? const Color(0xFFFFFFFF) : const Color(0xFF1F2733))
            .withValues(alpha: alpha)
        ..strokeWidth = size * 0.08;
      final ringR = Rect.fromCircle(
        center: Offset(r.left + size * 0.2, r.top + size * 0.2),
        radius: size * 0.14,
      );
      _fill.color = (urgent ? AppColors.danger : Colors.white).withValues(
        alpha: alpha,
      );
      c.drawCircle(ringR.center, size * 0.18, _fill);
      c.drawArc(ringR, -math.pi / 2, 2 * math.pi * frac, false, _stroke);
    }

    if (highlight) {
      _stroke
        ..color = Colors.white
        ..strokeWidth = size * 0.07;
      c.drawRRect(rr.inflate(size * 0.06), _stroke);
    }
  }

  void _decorate(Canvas c, Rect r, Color color, double size, double alpha) {
    final dark = Color.lerp(
      color,
      Colors.black,
      0.25,
    )!.withValues(alpha: alpha);
    final light = Color.lerp(
      color,
      Colors.white,
      0.35,
    )!.withValues(alpha: alpha);
    switch (boxStyle) {
      case 'box_gift':
        _fill.color = Colors.white.withValues(alpha: 0.85 * alpha);
        c.drawRect(
          Rect.fromCenter(center: r.center, width: size * 0.14, height: size),
          _fill,
        );
        c.drawRect(
          Rect.fromCenter(center: r.center, width: size, height: size * 0.14),
          _fill,
        );
      case 'box_crate':
        _stroke
          ..color = dark
          ..strokeWidth = size * 0.05;
        for (final f in [0.33, 0.66]) {
          c.drawLine(
            Offset(r.left + size * 0.08, r.top + size * f),
            Offset(r.right - size * 0.08, r.top + size * f),
            _stroke,
          );
        }
      case 'box_gold':
        _stroke
          ..color = const Color(0xFFFFD54F).withValues(alpha: alpha)
          ..strokeWidth = size * 0.08;
        c.drawRRect(
          RRect.fromRectXY(r.deflate(size * 0.06), size * 0.12, size * 0.12),
          _stroke,
        );
      case 'box_round':
        _fill.color = light;
        c.drawCircle(
          r.center.translate(-size * 0.15, -size * 0.15),
          size * 0.1,
          _fill,
        );
      default:
        // Cardboard tape strip.
        _fill.color = light;
        c.drawRect(
          Rect.fromLTWH(
            r.center.dx - size * 0.09,
            r.top,
            size * 0.18,
            size * 0.36,
          ),
          _fill,
        );
    }
  }

  /// Mark glyph: white with a dark outline so it reads on every color.
  void drawMark(
    Canvas c,
    int mark,
    Offset center,
    double size, {
    double alpha = 1,
  }) {
    final path = markPath(mark, center, size);
    _stroke
      ..color = const Color(0xFF1F2733).withValues(alpha: alpha)
      ..strokeWidth = size * 0.16
      ..strokeJoin = StrokeJoin.round;
    c.drawPath(path, _stroke);
    _fill.color = Colors.white.withValues(alpha: alpha);
    c.drawPath(path, _fill);
  }

  static Path markPath(int mark, Offset c, double size) {
    final r = size / 2;
    switch (mark) {
      case 1: // star
        final p = Path();
        for (var i = 0; i < 10; i++) {
          final rad = i.isEven ? r : r * 0.45;
          final a = -math.pi / 2 + i * math.pi / 5;
          final pt = Offset(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
          i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
        }
        return p..close();
      case 2: // circle
        return Path()..addOval(Rect.fromCircle(center: c, radius: r * 0.8));
      case 3: // triangle
        return Path()
          ..moveTo(c.dx, c.dy - r)
          ..lineTo(c.dx + r * 0.95, c.dy + r * 0.75)
          ..lineTo(c.dx - r * 0.95, c.dy + r * 0.75)
          ..close();
      default:
        return Path();
    }
  }

  /// Badge showing what a truck wants: color swatch and/or mark.
  void drawRequirement(Canvas c, Requirement req, Offset center, double size) {
    final r = Rect.fromCenter(center: center, width: size, height: size);
    if (req.color != null) {
      _fill.color = packageColors[req.color!];
      c.drawRRect(RRect.fromRectXY(r, size * 0.22, size * 0.22), _fill);
    } else {
      // Any color: neutral box with a rainbow rim.
      _fill.color = const Color(0xFFE0E4EA);
      final rr = RRect.fromRectXY(r, size * 0.22, size * 0.22);
      c.drawRRect(rr, _fill);
      final seg = 2 * math.pi / packageColors.length;
      for (var i = 0; i < packageColors.length; i++) {
        _stroke
          ..color = packageColors[i]
          ..strokeWidth = size * 0.1;
        c.drawArc(r.deflate(size * 0.06), i * seg, seg, false, _stroke);
      }
    }
    if (req.mark != null) drawMark(c, req.mark!, center, size * 0.55);
  }
}
