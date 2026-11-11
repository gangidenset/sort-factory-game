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

/// Flame game hosting a [GameSession].
///
/// The session resolves a tap (including whole departure chains) instantly.
/// The board then *replays* the resulting events one by one on its own visual
/// copy of the state, so chains read clearly: box flies → truck departs →
/// next truck rolls in → shelf boxes hop in → next departure...
class SortFactoryGame extends FlameGame {
  SortFactoryGame({
    required this.session,
    required this.skin,
    required this.boxStyle,
    required this.onEvent,
    required this.onSettled,
  });

  final GameSession session;
  final FactorySkin skin;
  final String boxStyle;

  /// Called as each event is *played* (sound, haptics, HUD).
  final void Function(SessionEvent e) onEvent;

  /// Called when playback is idle and the session is over (show result).
  final VoidCallback onSettled;

  late final BoardComponent board;

  @override
  Color backgroundColor() => skin.background;

  @override
  Future<void> onLoad() async {
    board = BoardComponent();
    add(board);
  }

  /// Highlights [lane] as a hint until the next tap.
  void showHint(int lane) => board.hintLane = lane;

  /// Re-syncs visuals after undo / revive.
  void resync() => board.resync();
}

class _VBox {
  _VBox(this.id, this.color, {this.hidden = false});
  final int id;
  final int color;
  bool hidden;
  double reveal = 0; // flip animation
}

class _VTruck {
  _VTruck(this.id, this.color, this.capacity, this.filled);
  final int id;
  final int color;
  final int capacity;
  int filled;
  double arrive = 0; // 1 → 0 slide-in
  double bounce = 0;
}

class _Flyer {
  _Flyer(
    this.box,
    this.from,
    this.to,
    this.toSize,
    this.onLand, {
    this.fall = false,
  });
  final _VBox box;
  final Offset from;
  final Offset to;
  final double toSize;
  final VoidCallback onLand;
  final bool fall;
  double t = 0;
  static const duration = 0.2;
}

class _Departing {
  _Departing(this.truck, this.dock);
  final _VTruck truck;
  final int dock;
  double t = 0;
  static const duration = 0.55;
}

class _Floater {
  _Floater(this.text, this.pos, this.color, {this.size = 20});
  final String text;
  final Offset pos;
  final Color color;
  final double size;
  double t = 0;
  static const duration = 1.0;
}

class _Particle {
  _Particle(this.pos, this.vel, this.color, this.size);
  Offset pos;
  Offset vel;
  final Color color;
  final double size;
  double t = 0;
  double spin = 0;
  static const life = 0.9;
}

class BoardComponent extends PositionComponent
    with HasGameReference<SortFactoryGame>, TapCallbacks {
  BoardLayout? _layout;
  late PackagePainter _painter;
  final _rng = math.Random(7);

  // Visual state (replayed from events).
  final List<List<_VBox>> _lanes = [];
  final List<_VTruck?> _docks = [];
  final List<_VBox> _shelf = [];
  int _queueShown = 0;

  final List<SessionEvent> _pending = [];
  double _wait = 0;
  int? _bufferedTap;
  bool _settledNotified = false;

  final List<_Flyer> _flyers = [];
  final Map<int, int> _inbound = {}; // truck id -> boxes in flight
  final List<_Departing> _departing = [];
  final List<_Floater> _floaters = [];
  final List<_Particle> _particles = [];
  double _shake = 0;
  double _time = 0;
  int? hintLane;

  final _paint = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  GameSession get s => game.session;

  bool get isIdle => _pending.isEmpty && _flyers.isEmpty && _wait <= 0;

  @override
  Future<void> onLoad() async {
    _painter = PackagePainter(game.boxStyle);
    // Web loads CJK fallback fonts lazily: drop cached text layouts when
    // fonts change so labels don't stay as tofu.
    PaintingBinding.instance.systemFonts.addListener(_textCache.clear);
    resync();
  }

  @override
  void onRemove() {
    PaintingBinding.instance.systemFonts.removeListener(_textCache.clear);
    super.onRemove();
  }

  /// Copies the logical state into the visual state (start, undo, revive).
  void resync() {
    s.drainEvents();
    _pending.clear();
    _flyers.clear();
    _inbound.clear();
    _wait = 0;
    _bufferedTap = null;
    _settledNotified = false;
    hintLane = null;
    _lanes
      ..clear()
      ..addAll([
        for (final l in s.lanes)
          [for (final p in l) _VBox(p.id, p.color, hidden: p.hidden)],
      ]);
    _docks
      ..clear()
      ..addAll([
        for (final t in s.docks)
          t == null ? null : _VTruck(t.id, t.color, t.capacity, t.filled),
      ]);
    _shelf
      ..clear()
      ..addAll([for (final p in s.shelf) _VBox(p.id, p.color)]);
    _queueShown = s.queue.length;
    _relayout();
  }

  @visibleForTesting
  Rect debugLaneRect(int lane) => _layout!.laneRects[lane];

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
    _relayout();
  }

  void _relayout() {
    if (size.x <= 0 || size.y <= 0) return;
    final maxDepth = s.config.lanes.fold(0, (a, l) => math.max(a, l.length));
    _layout = BoardLayout(
      size: Size(size.x, size.y),
      lanes: s.lanes.length,
      maxDepth: maxDepth,
      docks: s.docks.length,
      shelfSlots: s.config.shelf + 2, // room for upgrade / revive slots
    );
  }

  // ---------------------------------------------------------------------------
  // Input

  @override
  void onTapDown(TapDownEvent event) {
    final l = _layout;
    if (l == null) return;
    final lane = l.laneAt(Offset(event.localPosition.x, event.localPosition.y));
    if (lane == null) return;
    if (isIdle) {
      _doTap(lane);
    } else {
      _bufferedTap = lane; // feels responsive during chain playback
    }
  }

  void _doTap(int lane) {
    if (!s.canTap(lane)) {
      if (s.status == SessionStatus.playing && s.isLocked(lane)) {
        _floaters.add(
          _Floater(
            'LOCK',
            _layout!.laneRects[lane].topCenter.translate(0, 30),
            AppColors.danger,
          ),
        );
      }
      return;
    }
    hintLane = null;
    s.tap(lane);
    _pending.addAll(s.drainEvents());
    _settledNotified = false;
  }

  // ---------------------------------------------------------------------------
  // Playback

  @override
  void update(double dt) {
    _time += dt;
    final l = _layout;
    if (l == null) return;

    for (final f in List.of(_flyers)) {
      f.t += dt;
      if (f.t >= _Flyer.duration) {
        _flyers.remove(f);
        f.onLand();
      }
    }
    for (final d in _departing) {
      d.t += dt;
    }
    _departing.removeWhere((d) => d.t >= _Departing.duration);
    for (final f in _floaters) {
      f.t += dt;
    }
    _floaters.removeWhere((f) => f.t >= _Floater.duration);
    for (final p in _particles) {
      p.t += dt;
      p.vel = p.vel.translate(0, 900 * dt);
      p.pos += p.vel * dt;
      p.spin += dt * 10;
    }
    _particles.removeWhere((p) => p.t >= _Particle.life);
    for (final t in _docks) {
      if (t == null) continue;
      t.arrive = math.max(0, t.arrive - dt * 3.2);
      t.bounce = math.max(0, t.bounce - dt * 5);
    }
    for (final lane in _lanes) {
      for (final b in lane) {
        if (b.reveal > 0) b.reveal = math.max(0, b.reveal - dt * 4);
      }
    }
    _shake = math.max(0, _shake - dt);

    _wait -= dt;
    while (_wait <= 0 && _pending.isNotEmpty) {
      _play(_pending.removeAt(0));
    }
    if (isIdle) {
      final buffered = _bufferedTap;
      _bufferedTap = null;
      if (buffered != null && s.status == SessionStatus.playing) {
        _doTap(buffered);
      } else if (s.isOver && !_settledNotified && _departing.isEmpty) {
        _settledNotified = true;
        game.onSettled();
      }
    }
  }

  void _play(SessionEvent e) {
    final l = _layout!;
    game.onEvent(e);
    switch (e.type) {
      case SessionEventType.move:
        final p = e.package!;
        late _VBox box;
        late Offset from;
        switch (e.origin!) {
          case LaneOrigin(:final lane):
            box = _lanes[lane].isNotEmpty
                ? _lanes[lane].removeAt(0)
                : _VBox(p.id, p.color);
            from = l.packageCenter(lane, 0);
          case ShelfOrigin(:final slot):
            final i = slot.clamp(0, math.max(0, _shelf.length - 1)).toInt();
            box = _shelf.isNotEmpty ? _shelf.removeAt(i) : _VBox(p.id, p.color);
            from = l
                .shelfSlotRects[math.min(slot, l.shelfSlotRects.length - 1)]
                .center;
        }
        box.hidden = false;
        switch (e.destination!) {
          case ToTruck(:final dock):
            final t = _docks[dock]!;
            final seat = t.filled + (_inbound[t.id] ?? 0);
            _inbound[t.id] = (_inbound[t.id] ?? 0) + 1;
            final to = BoardTruck.seat(
              l.dockRects[dock],
              math.min(seat, t.capacity - 1),
              t.capacity,
            );
            _flyers.add(
              _Flyer(
                box,
                from,
                to,
                BoardTruck.seatBox(l.dockRects[dock], t.capacity),
                () {
                  _inbound[t.id] = (_inbound[t.id] ?? 1) - 1;
                  t.filled = math.min(t.capacity, t.filled + 1);
                  t.bounce = 1;
                },
              ),
            );
            // Let the box land before its truck drives off.
            final departsNext =
                _pending.isNotEmpty &&
                _pending.first.type == SessionEventType.depart;
            _wait = departsNext ? _Flyer.duration + 0.02 : 0.12;
          case ToShelf(:final slot):
            final to = l
                .shelfSlotRects[math.min(slot, l.shelfSlotRects.length - 1)]
                .center;
            _flyers.add(
              _Flyer(box, from, to, l.pkgSize * 0.9, () => _shelf.add(box)),
            );
            _wait = 0.1;
          case Overflow():
            final to = Offset(l.shelfRect.right + 20, l.shelfRect.center.dy);
            _flyers.add(
              _Flyer(box, from, to, l.pkgSize, () => _shake = 0.4, fall: true),
            );
            _wait = 0.25;
        }
      case SessionEventType.depart:
        final d = e.dock!;
        final gone = _docks[d];
        if (gone != null) {
          gone.filled = gone.capacity;
          _departing.add(_Departing(gone, d));
        }
        final next = e.arrived;
        _docks[d] = next == null
            ? null
            : (_VTruck(next.id, next.color, next.capacity, 0)..arrive = 1);
        if (next != null) _queueShown = math.max(0, _queueShown - 1);
        final rect = l.dockRects[d];
        _burst(rect.center, packageColors[e.departed!.color], 18 + 6 * e.chain);
        _floaters.add(
          _Floater(
            e.chain >= 2 ? '${e.chain}連鎖!' : '出荷!',
            rect.center.translate(0, -rect.height * 0.2),
            e.chain >= 2 ? AppColors.coin : AppColors.success,
            size: e.chain >= 2 ? 28 + 4.0 * e.chain : 22,
          ),
        );
        if (e.chain >= 2) _shake = 0.12 + 0.04 * e.chain;
        _wait = 0.32;
      case SessionEventType.reveal:
        final lane = e.lane!;
        if (_lanes[lane].isNotEmpty) {
          _lanes[lane].first
            ..hidden = false
            ..reveal = 1;
        }
      case SessionEventType.cleared:
        for (var i = 0; i < 4; i++) {
          _burst(
            Offset(size.x * (0.2 + 0.2 * i), size.y * 0.35),
            packageColors[i % packageColors.length],
            24,
          );
        }
      case SessionEventType.shelfCompacted ||
          SessionEventType.undone ||
          SessionEventType.failed:
        break;
    }
  }

  void _burst(Offset at, Color color, int n) {
    for (var i = 0; i < n; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final v = 180 + _rng.nextDouble() * 320;
      final palette = [color, Colors.white, AppColors.coin];
      _particles.add(
        _Particle(
          at,
          Offset(math.cos(a) * v, math.sin(a) * v - 260),
          palette[i % palette.length],
          4 + _rng.nextDouble() * 5,
        ),
      );
    }
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
      c.translate(
        math.sin(_time * 70) * _shake * 14,
        math.cos(_time * 55) * _shake * 6,
      );
    }
    _renderQueue(c, l);
    _renderDocks(c, l);
    _renderShelf(c, l);
    _renderLanes(c, l);
    for (final f in _flyers) {
      final k = Curves.easeInOut.transform((f.t / _Flyer.duration).clamp(0, 1));
      var pos = Offset.lerp(f.from, f.to, k)!;
      pos = pos.translate(0, -math.sin(k * math.pi) * 40); // arc
      if (f.fall) pos = pos.translate(0, k * k * 60);
      final size = l.pkgSize + (f.toSize - l.pkgSize) * k;
      _painter.drawBox(c, f.box.color, pos, size, happy: true);
    }
    for (final p in _particles) {
      final a = 1 - p.t / _Particle.life;
      _paint.color = p.color.withValues(alpha: a);
      c.save();
      c.translate(p.pos.dx, p.pos.dy);
      c.rotate(p.spin);
      c.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.6,
        ),
        _paint,
      );
      c.restore();
    }
    for (final f in _floaters) {
      final k = f.t / _Floater.duration;
      final pop = k < 0.15
          ? 0.6 + k / 0.15 * 0.6
          : 1.2 - math.min(0.2, (k - 0.15));
      _text(
        c,
        f.text,
        f.pos.translate(0, -40 * k),
        f.size * pop,
        f.color.withValues(alpha: (1 - k * k).clamp(0, 1)),
        bold: true,
        outline: true,
      );
    }
    c.restore();
  }

  void _renderQueue(Canvas c, BoardLayout l) {
    final r = l.queueRect;
    _text(
      c,
      'NEXT',
      Offset(r.left + 20, r.center.dy),
      11,
      game.skin.onBackground.withValues(alpha: 0.6),
      bold: true,
    );
    final q = s.queue;
    final shownStart = q.length - _queueShown;
    var x = r.left + 50;
    for (
      var i = math.max(0, shownStart);
      i < q.length && x < r.right - 30;
      i++
    ) {
      _painter.drawMiniTruck(
        c,
        Offset(x + 12, r.center.dy),
        16,
        q[i].color,
        alpha: i == shownStart ? 1 : 0.75,
      );
      x += 34;
    }
    final remaining = _queueShown + _docks.whereType<_VTruck>().length;
    _text(
      c,
      '残り$remaining台',
      Offset(r.right - 30, r.center.dy),
      11,
      game.skin.onBackground.withValues(alpha: 0.6),
      bold: true,
    );
  }

  void _renderDocks(Canvas c, BoardLayout l) {
    for (var i = 0; i < l.dockRects.length; i++) {
      final r = l.dockRects[i];
      _paint.color = game.skin.onBackground.withValues(alpha: 0.06);
      c.drawRRect(RRect.fromRectXY(r.inflate(2), 14, 14), _paint);
      final t = _docks[i];
      if (t != null) {
        final dx = -t.arrive * t.arrive * (r.left + r.width);
        c.save();
        c.translate(dx, 0);
        _painter.drawTruck(
          c,
          r,
          t.color,
          t.capacity,
          t.filled,
          bounce: t.bounce,
          wheelSpin: t.arrive * 12,
        );
        c.restore();
      }
    }
    for (final d in _departing) {
      final r = l.dockRects[d.dock];
      final k = d.t / _Departing.duration;
      final dx = k * k * (size.x - r.left + 40);
      c.save();
      c.translate(dx, -math.sin(k * math.pi) * 6);
      _painter.drawTruck(
        c,
        r,
        d.truck.color,
        d.truck.capacity,
        d.truck.capacity,
        wheelSpin: d.t * 30,
      );
      c.restore();
    }
  }

  void _renderShelf(Canvas c, BoardLayout l) {
    final cap = s.shelfCapacity;
    final danger = _shelf.length >= cap - 1;
    final r = l.shelfRect;
    final visibleSlots = math.min(cap, l.shelfSlotRects.length);
    final last = l.shelfSlotRects[visibleSlots - 1];
    final board = Rect.fromLTRB(r.left, r.top, last.right + 8, r.bottom);
    final pulse = danger ? 0.5 + 0.5 * math.sin(_time * 8) : 0.0;
    _paint.color = (danger ? AppColors.danger : const Color(0xFF8A6A4A))
        .withValues(alpha: 0.12 + 0.1 * pulse);
    c.drawRRect(RRect.fromRectXY(board, 12, 12), _paint);
    _text(
      c,
      '棚',
      Offset(board.left - 0, board.top - 8),
      11,
      game.skin.onBackground.withValues(alpha: 0.6),
      bold: true,
    );
    for (var i = 0; i < visibleSlots; i++) {
      final sr = l.shelfSlotRects[i];
      _stroke
        ..color = (danger ? AppColors.danger : game.skin.onBackground)
            .withValues(alpha: 0.25)
        ..strokeWidth = 2;
      c.drawRRect(RRect.fromRectXY(sr, 8, 8), _stroke);
      if (i < _shelf.length) {
        _painter.drawBox(c, _shelf[i].color, sr.center, sr.width * 0.86);
      }
    }
  }

  void _renderLanes(Canvas c, BoardLayout l) {
    for (var i = 0; i < _lanes.length; i++) {
      final r = l.laneRects[i];
      final locked = s.isLocked(i);
      _paint.color = game.skin.belt.withValues(alpha: locked ? 0.35 : 0.9);
      c.drawRRect(RRect.fromRectXY(r, 14, 14), _paint);
      // Conveyor stripes.
      c.save();
      c.clipRRect(RRect.fromRectXY(r, 14, 14));
      _paint.color = Colors.white.withValues(alpha: 0.05);
      for (var y = r.top; y < r.bottom; y += 22) {
        c.drawRect(Rect.fromLTWH(r.left, y, r.width, 8), _paint);
      }
      c.restore();

      final lane = _lanes[i];
      final maxVisible = ((r.height - l.pkgSize * 0.2) / l.pkgStep).floor();
      for (var k = math.min(lane.length, maxVisible) - 1; k >= 0; k--) {
        final b = lane[k];
        final ctr = l.packageCenter(i, k);
        final isFront = k == 0;
        final alpha = locked ? 0.45 : (isFront ? 1.0 : 0.92);
        final willLoad =
            isFront && !locked && s.dockFor(b.color) != null && isIdle;
        final sizeK = isFront ? 1.0 : 0.94;
        if (b.reveal > 0) {
          final sx = (b.reveal - 0.5).abs() * 2;
          c.save();
          c.translate(ctr.dx, ctr.dy);
          c.scale(math.max(0.05, sx), 1);
          _painter.drawBox(
            c,
            b.color,
            Offset.zero,
            l.pkgSize,
            hidden: b.reveal > 0.5,
          );
          c.restore();
        } else {
          _painter.drawBox(
            c,
            b.color,
            ctr,
            l.pkgSize * sizeK,
            hidden: b.hidden,
            alpha: alpha,
            glow: willLoad,
            squash: willLoad ? 0.25 * (0.5 + 0.5 * math.sin(_time * 5 + i)) : 0,
          );
        }
      }
      if (lane.length > maxVisible) {
        _text(
          c,
          '+${lane.length - maxVisible}',
          Offset(r.center.dx, r.bottom - 10),
          12,
          Colors.white,
          bold: true,
        );
      }
      if (locked) {
        _lock(c, r.center, l.pkgSize * 0.7);
        _text(
          c,
          '${s.unlockIn(i)}',
          r.center.translate(0, l.pkgSize * 0.6),
          18,
          Colors.white,
          bold: true,
          outline: true,
        );
      }
      if (hintLane == i) {
        final pulse = 0.5 + 0.5 * math.sin(_time * 8);
        _stroke
          ..color = AppColors.coin.withValues(alpha: 0.6 + 0.4 * pulse)
          ..strokeWidth = 4;
        c.drawRRect(
          RRect.fromRectXY(r.inflate(3 + pulse * 3), 16, 16),
          _stroke,
        );
      }
    }
  }

  void _lock(Canvas c, Offset center, double size) {
    _paint.color = const Color(0xFFF2C94C);
    final body = Rect.fromCenter(
      center: center.translate(0, size * 0.15),
      width: size * 0.8,
      height: size * 0.6,
    );
    c.drawRRect(RRect.fromRectXY(body, 6, 6), _paint);
    _stroke
      ..color = const Color(0xFFF2C94C)
      ..strokeWidth = size * 0.12;
    c.drawArc(
      Rect.fromCenter(
        center: center.translate(0, -size * 0.12),
        width: size * 0.5,
        height: size * 0.6,
      ),
      math.pi,
      math.pi,
      false,
      _stroke,
    );
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
    final key =
        '$text|${size.toStringAsFixed(1)}|${color.toARGB32()}|$bold|$outline';
    var tp = _textCache[key];
    if (tp == null) {
      if (_textCache.length > 400) _textCache.clear();
      tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: size,
            color: color,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
            shadows: outline
                ? [
                    Shadow(
                      color: Colors.black.withValues(alpha: color.a * 0.45),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
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
