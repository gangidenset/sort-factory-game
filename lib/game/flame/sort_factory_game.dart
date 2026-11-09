import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../ui/palette.dart';
import '../logic/game_session.dart';
import '../logic/models.dart';
import 'board_layout.dart';
import 'package_painter.dart';

/// Flame game hosting a [GameSession]. All rules live in the session; this
/// class renders it and translates touches into moves.
class SortFactoryGame extends FlameGame {
  SortFactoryGame({
    required this.session,
    required this.skin,
    required this.boxStyle,
    required this.onEvents,
    this.alwaysHint = false,
  });

  final GameSession session;
  final FactorySkin skin;
  final String boxStyle;
  final bool alwaysHint;

  /// Called with each batch of session events (sound, HUD, end of stage).
  final void Function(List<SessionEvent> events) onEvents;

  /// Seconds of hint display left (granted by rewarded ad).
  double hintTime = 0;

  bool get hintActive => alwaysHint || hintTime > 0;

  late final BoardComponent board;

  @override
  Color backgroundColor() => skin.background;

  @override
  Future<void> onLoad() async {
    board = BoardComponent();
    add(board);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (hintTime > 0) hintTime = math.max(0, hintTime - dt);
    session.update(dt);
    final events = session.drainEvents();
    if (events.isNotEmpty) {
      board.onSessionEvents(events);
      onEvents(events);
    }
  }
}

class _Flyer {
  _Flyer(this.pkg, this.from, this.to, this.outcome);
  final Package pkg;
  final Offset from;
  final Offset to;
  final MoveOutcome outcome;
  double t = 0;
  static const duration = 0.16;
}

class _Floater {
  _Floater(this.text, this.pos, this.color, {this.big = false});
  final String text;
  final Offset pos;
  final Color color;
  final bool big;
  double t = 0;
  static const duration = 0.9;
}

class BoardComponent extends PositionComponent
    with HasGameReference<SortFactoryGame>, TapCallbacks, DragCallbacks {
  BoardLayout? _layout;
  late PackagePainter _painter;

  Source _selected = const FrontSource();

  // Drag state
  Source? _dragSource;
  Offset? _dragPos;

  final List<_Flyer> _flyers = [];
  final List<_Floater> _floaters = [];
  final Map<int, double> _dockFlash =
      {}; // dock -> remaining (positive=ok, negative=bad)
  final Map<int, double> _dockSwap = {};
  double _shake = 0;
  double _time = 0;

  final _paint = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  GameSession get s => game.session;

  /// Dock rectangle in game coordinates (used by widget tests).
  @visibleForTesting
  Rect debugDockRect(int dock) => _layout!.dockRects[dock];

  @override
  Future<void> onLoad() async {
    _painter = PackagePainter(game.boxStyle);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
    _layout = BoardLayout(
      size: Size(size.x, size.y),
      docks: s.docks.length,
      beltCapacity: s.beltCapacity,
      bufferSlots: s.buffer.length,
    );
  }

  @override
  void update(double dt) {
    _time += dt;
    for (final f in _flyers) {
      f.t += dt;
    }
    _flyers.removeWhere((f) => f.t >= _Flyer.duration);
    for (final f in _floaters) {
      f.t += dt;
    }
    _floaters.removeWhere((f) => f.t >= _Floater.duration);
    for (final m in [_dockFlash, _dockSwap]) {
      for (final k in m.keys.toList()) {
        final v = m[k]!;
        final nv = v > 0 ? math.max(0.0, v - dt) : math.min(0.0, v + dt);
        if (nv == 0) {
          m.remove(k);
        } else {
          m[k] = nv;
        }
      }
    }
    _shake = math.max(0, _shake - dt);
    // Selected buffer slot emptied (e.g. timed package expired).
    if (_selected case BufferSource(:final slot)
        when slot >= s.buffer.length || s.buffer[slot] == null) {
      _selected = const FrontSource();
    }
  }

  void onSessionEvents(List<SessionEvent> events) {
    final l = _layout;
    if (l == null) return;
    for (final e in events) {
      switch (e.type) {
        case SessionEventType.truckDeparted:
          _dockSwap[e.dock!] = 0.35;
        case SessionEventType.expired:
          _shake = 0.25;
          _floaters.add(_Floater('時間切れ!', l.frontCenter, AppColors.danger));
        case SessionEventType.comboMilestone:
          _floaters.add(
            _Floater(
              '${e.combo} COMBO!',
              l.frontCenter.translate(0, -l.pkgSize * 2),
              AppColors.coin,
              big: true,
            ),
          );
        default:
          break;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Input

  Offset _local(Vector2 v) => Offset(v.x, v.y);

  Source? _sourceAt(Offset p) {
    final l = _layout!;
    if (l.frontRect.inflate(l.pkgSize * 0.2).contains(p) && s.front != null) {
      return const FrontSource();
    }
    for (var i = 0; i < l.bufferRects.length; i++) {
      if (l.bufferRects[i].inflate(6).contains(p) && s.buffer[i] != null) {
        return BufferSource(i);
      }
    }
    return null;
  }

  Target? _targetAt(Offset p, {bool generous = false}) {
    final l = _layout!;
    final grow = generous ? l.pkgSize * 0.35 : 4.0;
    for (var i = 0; i < l.dockRects.length; i++) {
      // Docks extend upward a bit so drags that end just above still count.
      final r = l.dockRects[i];
      final hit = Rect.fromLTRB(
        r.left,
        r.top - grow * 2,
        r.right,
        r.bottom + grow,
      );
      if (hit.contains(p)) return DockTarget(i);
    }
    for (var i = 0; i < l.bufferRects.length; i++) {
      if (l.bufferRects[i].inflate(grow).contains(p)) return BufferTarget(i);
    }
    if (l.chuteRect.inflate(grow).contains(p)) return const ChuteTarget();
    return null;
  }

  Offset _sourceCenter(Source src) => switch (src) {
    FrontSource() => _layout!.frontCenter,
    BufferSource(:final slot) => _layout!.bufferRects[slot].center,
  };

  Offset _targetCenter(Target t) => switch (t) {
    DockTarget(:final dock) => _layout!.dockRects[dock].center,
    BufferTarget(:final slot) => _layout!.bufferRects[slot].center,
    ChuteTarget() => _layout!.chuteRect.center,
  };

  void _perform(Source src, Target tgt, {Offset? from}) {
    final start = from ?? _sourceCenter(src);
    final r = s.move(src, tgt);
    _selected = const FrontSource();
    if (r.outcome == MoveOutcome.invalid) return;
    _flyers.add(_Flyer(r.package!, start, _targetCenter(tgt), r.outcome));
    final l = _layout!;
    switch (r.outcome) {
      case MoveOutcome.correct:
        final dock = (tgt as DockTarget).dock;
        _dockFlash[dock] = 0.3;
        _floaters.add(
          _Floater(
            '+${r.scoreDelta}',
            l.dockRects[dock].topCenter,
            AppColors.success,
          ),
        );
      case MoveOutcome.wrong:
        final dock = (tgt as DockTarget).dock;
        _dockFlash[dock] = -0.4;
        _shake = 0.25;
        _floaters.add(
          _Floater('ミス!', l.dockRects[dock].topCenter, AppColors.danger),
        );
      default:
        break;
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (s.status != SessionStatus.playing || _layout == null) return;
    final p = _local(event.localPosition);

    final tgt = _targetAt(p);
    // Tapping an occupied buffer slot selects it (or deselects).
    if (tgt is BufferTarget && s.buffer[tgt.slot] != null) {
      final src = BufferSource(tgt.slot);
      _selected = _selected == src ? const FrontSource() : src;
      return;
    }
    if (tgt != null) {
      _perform(_selected, tgt);
      return;
    }
    if (_sourceAt(p) is FrontSource) _selected = const FrontSource();
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (s.status != SessionStatus.playing || _layout == null) return;
    final p = _local(event.localPosition);
    _dragSource = _sourceAt(p);
    _dragPos = _dragSource == null ? null : p;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (_dragPos == null) return;
    _dragPos = _dragPos! + _local(event.localDelta);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    final src = _dragSource, pos = _dragPos;
    _dragSource = null;
    _dragPos = null;
    if (src == null || pos == null || s.status != SessionStatus.playing) return;
    final tgt = _targetAt(pos, generous: true);
    if (tgt != null) _perform(src, tgt, from: pos);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _dragSource = null;
    _dragPos = null;
  }

  // ---------------------------------------------------------------------------
  // Rendering

  @override
  void render(Canvas canvas) {
    final c = canvas;
    final l = _layout;
    if (l == null) return;
    c.save();
    if (_shake > 0) {
      final k = _shake * 24;
      c.translate(math.sin(_time * 80) * k * 0.3, 0);
    }
    final hint = game.hintActive ? _hint() : null;
    _renderBelt(c, l);
    _renderBuffer(c, l, hint);
    _renderChute(c, l, hint);
    _renderDocks(c, l, hint);
    _renderBeltPackages(c, l);
    for (final f in _flyers) {
      final k = Curves.easeIn.transform((f.t / _Flyer.duration).clamp(0, 1));
      final pos = Offset.lerp(f.from, f.to, k)!;
      _painter.drawPackage(
        c,
        f.pkg,
        pos,
        l.pkgSize * (1 - 0.4 * k),
        alpha: 1 - 0.5 * k,
      );
    }
    if (_dragPos != null && _dragSource != null) {
      final p = _packageAt(_dragSource!);
      if (p != null) {
        final over = _targetAt(_dragPos!, generous: true);
        if (over != null) _outline(c, _targetRect(l, over), Colors.white, 4);
        _painter.drawPackage(c, p, _dragPos!, l.pkgSize * 1.1);
      }
    }
    for (final f in _floaters) {
      final k = f.t / _Floater.duration;
      _text(
        c,
        f.text,
        f.pos.translate(0, -30 * k - 10),
        f.big ? 26 : 18,
        f.color.withValues(alpha: 1 - k),
        bold: true,
        outline: true,
      );
    }
    c.restore();
  }

  Package? _packageAt(Source src) => switch (src) {
    FrontSource() => s.front,
    BufferSource(:final slot) => s.buffer[slot],
  };

  Rect _targetRect(BoardLayout l, Target t) => switch (t) {
    DockTarget(:final dock) => l.dockRects[dock],
    BufferTarget(:final slot) => l.bufferRects[slot],
    ChuteTarget() => l.chuteRect,
  };

  (Source, Target)? _hint() {
    final b = s.hintForBuffer();
    if (b != null) return (BufferSource(b.$1), DockTarget(b.$2));
    final t = s.hintForFront();
    return t == null ? null : (const FrontSource(), t);
  }

  void _renderBelt(Canvas c, BoardLayout l) {
    final skin = game.skin;
    final belt = RRect.fromRectXY(l.beltRect, 14, 14);
    _paint.color = skin.belt;
    c.drawRRect(belt, _paint);
    // Moving rollers.
    c.save();
    c.clipRRect(belt);
    _paint.color = Colors.white.withValues(alpha: 0.08);
    final step = l.spacing / 2;
    final offset = (_time * s.config.beltSpeed * l.spacing) % step;
    for (
      var y = l.beltRect.top - step + offset;
      y < l.beltRect.bottom;
      y += step
    ) {
      c.drawRect(
        Rect.fromLTWH(l.beltRect.left, y, l.beltRect.width, step * 0.35),
        _paint,
      );
    }
    c.restore();
    // Jam warning.
    if (s.jamWarning) {
      final pulse = 0.5 + 0.5 * math.sin(_time * 10);
      _outline(
        c,
        l.beltRect,
        AppColors.danger.withValues(alpha: 0.4 + 0.6 * pulse),
        4,
      );
      _text(
        c,
        '詰まり注意!',
        l.beltRect.topCenter.translate(0, -12),
        14,
        AppColors.danger,
        bold: true,
      );
    }
    // Sorting point marker.
    _stroke
      ..color = skin.accent
      ..strokeWidth = 3;
    c.drawRRect(
      RRect.fromRectXY(
        Rect.fromCenter(
          center: l.frontCenter,
          width: l.pkgSize * 1.3,
          height: l.pkgSize * 1.3,
        ),
        12,
        12,
      ),
      _stroke,
    );
  }

  void _renderBeltPackages(Canvas c, BoardLayout l) {
    c.save();
    c.clipRect(l.beltRect.inflate(l.pkgSize * 0.3));
    for (var i = s.belt.length - 1; i >= 0; i--) {
      final p = s.belt[i];
      if (_dragPos != null && _dragSource is FrontSource && i == 0) continue;
      final selectedFront = i == 0 && _selected is FrontSource;
      _painter.drawPackage(
        c,
        p,
        l.beltPosition(p.pos),
        l.pkgSize,
        highlight: selectedFront && p.pos < 0.05,
      );
    }
    c.restore();
  }

  void _renderBuffer(Canvas c, BoardLayout l, (Source, Target)? hint) {
    for (var i = 0; i < l.bufferRects.length; i++) {
      final r = l.bufferRects[i];
      _paint.color = game.skin.onBackground.withValues(alpha: 0.08);
      c.drawRRect(RRect.fromRectXY(r, 12, 12), _paint);
      _dashed(c, r, game.skin.onBackground.withValues(alpha: 0.35));
      final p = s.buffer[i];
      final dragging = _dragSource == BufferSource(i) && _dragPos != null;
      if (p != null && !dragging) {
        _painter.drawPackage(
          c,
          p,
          r.center,
          l.pkgSize,
          highlight: _selected == BufferSource(i),
        );
      } else if (p == null) {
        _text(
          c,
          '保管',
          r.center,
          12,
          game.skin.onBackground.withValues(alpha: 0.5),
        );
      }
      if (hint != null &&
          (hint.$2 == BufferTarget(i) || hint.$1 == BufferSource(i))) {
        _pulseOutline(c, r);
      }
    }
  }

  void _renderChute(Canvas c, BoardLayout l, (Source, Target)? hint) {
    final r = l.chuteRect;
    _paint.color = const Color(0xFF8A94A6).withValues(alpha: 0.25);
    c.drawRRect(RRect.fromRectXY(r, 12, 12), _paint);
    _dashed(c, r, const Color(0xFF8A94A6));
    _returnArrow(
      c,
      r.center.translate(0, -8),
      r.width * 0.32,
      game.skin.onBackground.withValues(alpha: 0.7),
    );
    _text(
      c,
      '返品',
      r.center.translate(0, 14),
      11,
      game.skin.onBackground.withValues(alpha: 0.7),
    );
    if (hint?.$2 is ChuteTarget) _pulseOutline(c, r);
  }

  /// U-turn arrow icon (drawn, so it needs no font glyph).
  void _returnArrow(Canvas c, Offset center, double size, Color color) {
    _stroke
      ..color = color
      ..strokeWidth = size * 0.16
      ..strokeCap = StrokeCap.round;
    final r = size * 0.38;
    final path = Path()
      ..moveTo(center.dx + r, center.dy + r)
      ..lineTo(center.dx + r, center.dy)
      ..arcToPoint(
        Offset(center.dx - r, center.dy),
        radius: Radius.circular(r),
        clockwise: false,
      )
      ..lineTo(center.dx - r, center.dy + r * 0.6);
    c.drawPath(path, _stroke);
    final head = Path()
      ..moveTo(center.dx - r * 1.6, center.dy + r * 0.1)
      ..lineTo(center.dx - r, center.dy + r * 0.9)
      ..lineTo(center.dx - r * 0.4, center.dy + r * 0.1);
    c.drawPath(head, _stroke);
  }

  void _renderDocks(Canvas c, BoardLayout l, (Source, Target)? hint) {
    for (var i = 0; i < s.docks.length; i++) {
      final d = s.docks[i];
      var r = l.dockRects[i];
      final swap = _dockSwap[i];
      if (swap != null) r = r.translate(0, (swap / 0.35) * r.height * 0.25);

      final rr = RRect.fromRectXY(r, 16, 16);
      _paint.color = Colors.white;
      c.drawRRect(
        rr.shift(const Offset(0, 3)),
        _paint..color = const Color(0x22000000),
      );
      _paint.color = Colors.white;
      c.drawRRect(rr, _paint);

      final reqColor = d.requirement.color == null
          ? const Color(0xFF8A94A6)
          : packageColors[d.requirement.color!];
      // Colored header band.
      c.save();
      c.clipRRect(rr);
      _paint.color = reqColor.withValues(alpha: 0.18);
      c.drawRect(
        Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.62),
        _paint,
      );
      c.restore();
      _stroke
        ..color = reqColor
        ..strokeWidth = 3;
      c.drawRRect(rr, _stroke);

      final badge = math.min(r.width * 0.42, r.height * 0.36);
      _painter.drawRequirement(
        c,
        d.requirement,
        Offset(r.center.dx, r.top + r.height * 0.31),
        badge,
      );

      // Capacity cells.
      final cellsW = r.width * 0.8;
      final gap = 3.0;
      final cw = (cellsW - gap * (d.capacity - 1)) / d.capacity;
      final ch = math.min(cw, r.height * 0.14);
      final cy = r.top + r.height * 0.7;
      for (var k = 0; k < d.capacity; k++) {
        final cell = Rect.fromLTWH(
          r.left + r.width * 0.1 + k * (cw + gap),
          cy,
          cw,
          ch,
        );
        _paint.color = k < d.filled ? reqColor : const Color(0xFFE3E7ED);
        c.drawRRect(RRect.fromRectXY(cell, 4, 4), _paint);
      }

      // Next truck preview.
      final nextSize = math.min(r.width * 0.2, 22.0);
      final nextCenter = Offset(
        r.right - nextSize * 0.8,
        r.bottom - nextSize * 0.75,
      );
      _text(
        c,
        'NEXT',
        nextCenter.translate(-nextSize * 1.25, 0),
        9,
        const Color(0xFF8A94A6),
        bold: true,
      );
      _painter.drawRequirement(c, d.next, nextCenter, nextSize);

      final flash = _dockFlash[i];
      if (flash != null) {
        final ok = flash > 0;
        _paint.color = (ok ? AppColors.success : AppColors.danger).withValues(
          alpha: (flash.abs() / 0.4) * 0.45,
        );
        c.drawRRect(rr, _paint);
      }
      if (hint?.$2 == DockTarget(i)) _pulseOutline(c, r);
    }
  }

  void _pulseOutline(Canvas c, Rect r) {
    final pulse = 0.5 + 0.5 * math.sin(_time * 8);
    _outline(
      c,
      r.inflate(3 + pulse * 3),
      AppColors.coin.withValues(alpha: 0.6 + 0.4 * pulse),
      4,
    );
  }

  void _outline(Canvas c, Rect r, Color color, double width) {
    _stroke
      ..color = color
      ..strokeWidth = width;
    c.drawRRect(RRect.fromRectXY(r, 14, 14), _stroke);
  }

  void _dashed(Canvas c, Rect r, Color color) {
    _stroke
      ..color = color
      ..strokeWidth = 2;
    const dash = 6.0;
    void line(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += dash * 2) {
        c.drawLine(a + dir * d, a + dir * math.min(len, d + dash), _stroke);
      }
    }

    final i = r.deflate(4);
    line(i.topLeft, i.topRight);
    line(i.topRight, i.bottomRight);
    line(i.bottomRight, i.bottomLeft);
    line(i.bottomLeft, i.topLeft);
  }

  final Map<String, TextPainter> _textCache = {};

  void _text(
    Canvas c,
    String text,
    Offset center,
    double size,
    Color color, {
    bool bold = false,
    bool outline = false,
  }) {
    final key = '$text|$size|${color.toARGB32()}|$bold|$outline';
    var tp = _textCache[key];
    if (tp == null) {
      if (_textCache.length > 300) _textCache.clear();
      tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: size,
            color: color,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            shadows: outline
                ? [
                    Shadow(
                      color: Colors.black.withValues(alpha: color.a * 0.5),
                      blurRadius: 3,
                    ),
                  ]
                : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _textCache[key] = tp;
    }
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }
}
