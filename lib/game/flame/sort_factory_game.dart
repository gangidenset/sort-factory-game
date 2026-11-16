import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../ui/palette.dart';
import '../logic/deduction.dart';
import '../logic/game_session.dart';
import '../logic/models.dart';
import 'board_layout.dart';
import 'package_painter.dart';

/// What just happened on the board (for sounds / haptics).
enum BoardCue { box, cross, erase, lineDone, shipStep, shipDone }

/// Flame game showing a deduction puzzle grid. All rules live in
/// [GameSession]; this renders it and turns touches into marks.
class SortFactoryGame extends FlameGame {
  SortFactoryGame({
    required this.session,
    required this.skin,
    required this.boxStyle,
    required this.onCue,
    required this.onSolved,
    required this.onBlocked,
  });

  final GameSession session;
  final FactorySkin skin;
  final String boxStyle;

  /// Called for every feedback-worthy event; [step] counts shipped trucks
  /// during the finale (for rising pitch).
  final void Function(BoardCue cue, int step) onCue;

  /// Called once the shipping finale has finished playing.
  final VoidCallback onSolved;

  /// Called when the player tries to put a box where a rule forbids it,
  /// with the reason in plain words.
  final void Function(String reason) onBlocked;

  BoardComponent? _board;
  BoardComponent get board => _board!;

  @override
  Color backgroundColor() => skin.background;

  @override
  Future<void> onLoad() async {
    _board = BoardComponent()..hint = _pendingHint;
    add(board);
  }

  Hint? _pendingHint;

  /// Highlights a hint cell (safe to call before the board is loaded).
  void showHint(Hint? hint) {
    final b = _board;
    if (b != null) {
      b.hint = hint;
    } else {
      _pendingHint = hint;
    }
  }

  bool get boardReady => _board != null;

  /// Call after undo / reset / hint applied from outside.
  void refresh() {
    _board?.afterChange(silent: true);
  }
}

class _Particle {
  _Particle(this.pos, this.vel, this.color, this.size);
  Offset pos;
  Offset vel;
  final Color color;
  final double size;
  double t = 0;
  static const life = 1.0;
}

class BoardComponent extends PositionComponent
    with HasGameReference<SortFactoryGame>, TapCallbacks, DragCallbacks {
  BoardLayout? _layout;
  late PackagePainter _painter;
  final _rng = math.Random(3);

  Hint? hint;
  double _time = 0;

  // Small pop animations keyed by cell / line.
  final Map<Cell, double> _pop = {};
  final Map<Cell, double> _blocked = {};
  final Map<int, double> _rowPulse = {};
  final Map<int, double> _colPulse = {};
  late List<LineState> _rowStates;
  late List<LineState> _colStates;
  final List<_Particle> _particles = [];

  // Drag painting.
  Mark? _paint;
  Cell? _lastCell;
  Offset? _dragPos;
  double _lastApplyTime = -1;
  Cell? _lastApplyCell;

  // Finale.
  double? _finale; // seconds since solved
  int _shipped = 0;
  bool _done = false;
  static const _stagger = 0.16;
  static const _fly = 0.28;
  static const _drive = 0.6;

  final _fill = Paint();
  final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  GameSession get s => game.session;
  bool get inFinale => _finale != null;

  @visibleForTesting
  Rect debugCellRect(Cell c) => _layout!.cellRect(c);

  @override
  Future<void> onLoad() async {
    _painter = PackagePainter(game.boxStyle);
    PaintingBinding.instance.systemFonts.addListener(_textCache.clear);
    _snapshotLines();
  }

  @override
  void onRemove() {
    PaintingBinding.instance.systemFonts.removeListener(_textCache.clear);
    super.onRemove();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
    if (size.x > 0 && size.y > 0) {
      _layout = BoardLayout(size: Size(size.x, size.y), n: s.size);
    }
  }

  void _snapshotLines() {
    _rowStates = [for (var r = 0; r < s.size; r++) s.rowState(r)];
    _colStates = [for (var c = 0; c < s.size; c++) s.colState(c)];
  }

  /// Detects newly completed lines and the solved state after any change.
  void afterChange({bool silent = false}) {
    var lineDone = false;
    for (var i = 0; i < s.size; i++) {
      final r = s.rowState(i), c = s.colState(i);
      if (r == LineState.done &&
          _rowStates[i] != LineState.done &&
          s.config.rowClues[i] > 0) {
        _rowPulse[i] = 1;
        lineDone = true;
      }
      if (c == LineState.done &&
          _colStates[i] != LineState.done &&
          s.config.colClues[i] > 0) {
        _colPulse[i] = 1;
        lineDone = true;
      }
    }
    _snapshotLines();
    if (lineDone && !silent && !s.isCleared) game.onCue(BoardCue.lineDone, 0);
    if (s.isCleared && _finale == null) {
      _finale = 0;
      hint = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Input

  /// Applies [m] to [c]. A box on a forbidden cell is refused; with
  /// [explain] the player is told which rule says no.
  void _apply(Cell c, Mark m, {bool explain = true}) {
    if (inFinale) return;
    if (m == Mark.box) {
      final reason = s.placeBlockReason(c);
      if (reason != null) {
        if (explain) {
          _blocked[c] = 1;
          game.onBlocked(reason);
        }
        return;
      }
    }
    if (!s.setMark(c, m)) return;
    _pop[c] = 1;
    if (hint?.cell == c) hint = null;
    game.onCue(switch (m) {
      Mark.box => BoardCue.box,
      Mark.cross => BoardCue.cross,
      Mark.none => BoardCue.erase,
    }, 0);
    afterChange();
  }

  /// Taps and drag-starts can both fire for one touch: apply only once.
  bool _dedupe(Cell c) {
    if (_lastApplyCell == c && _time - _lastApplyTime < 0.25) return true;
    _lastApplyCell = c;
    _lastApplyTime = _time;
    return false;
  }

  @override
  void onTapUp(TapUpEvent event) {
    final c = _layout?.cellAt(
      Offset(event.localPosition.x, event.localPosition.y),
    );
    if (c == null || s.isTruck(c) || _dedupe(c)) return;
    _apply(c, s.nextMark(c));
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _dragPos = Offset(event.localPosition.x, event.localPosition.y);
    final c = _layout?.cellAt(_dragPos!);
    _paint = null;
    _lastCell = c;
    if (c == null || s.isTruck(c)) return;
    _paint = s.nextMark(c);
    if (!_dedupe(c)) _apply(c, _paint!);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    final pos = _dragPos;
    final paint = _paint;
    if (pos == null || paint == null) return;
    _dragPos = pos + Offset(event.localDelta.x, event.localDelta.y);
    final c = _layout?.cellAt(_dragPos!);
    if (c == null || c == _lastCell || s.isTruck(c)) return;
    _lastCell = c;
    // Paint only over empty cells (or erase only marked ones): a stroke
    // never overwrites a different mark by accident.
    final cur = s.markAt(c);
    if (paint == Mark.none ? cur != Mark.none : cur == Mark.none) {
      _apply(c, paint, explain: false);
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _paint = null;
    _dragPos = null;
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _paint = null;
    _dragPos = null;
  }

  // ---------------------------------------------------------------------------
  // Update

  @override
  void update(double dt) {
    _time += dt;
    for (final m in [_pop, _rowPulse, _colPulse, _blocked]) {
      for (final k in m.keys.toList()) {
        final v = m[k]! - dt * 4;
        if (v <= 0) {
          m.remove(k);
        } else {
          (m as Map)[k] = v;
        }
      }
    }
    for (final p in _particles) {
      p.t += dt;
      p.vel = p.vel.translate(0, 900 * dt);
      p.pos += p.vel * dt;
    }
    _particles.removeWhere((p) => p.t >= _Particle.life);

    final f = _finale;
    if (f != null && !_done) {
      _finale = f + dt;
      final total = s.config.trucks.length;
      // A truck "ships" when its box has landed.
      while (_shipped < total &&
          _finale! >= 0.35 + _shipped * _stagger + _fly) {
        final l = _layout;
        if (l != null) {
          final t = s.config.trucks[_shipped];
          _burst(l.cellRect(t.cell).center, packageColors[t.color], 14);
        }
        _shipped++;
        game.onCue(BoardCue.shipStep, _shipped);
      }
      if (_finale! >= 0.35 + total * _stagger + _fly + _drive + 0.25) {
        _done = true;
        final l = _layout;
        if (l != null) {
          for (var i = 0; i < 5; i++) {
            _burst(
              Offset(
                l.grid.left + l.grid.width * (0.1 + 0.2 * i),
                l.grid.center.dy,
              ),
              packageColors[i % packageColors.length],
              22,
            );
          }
        }
        game.onCue(BoardCue.shipDone, total);
        game.onSolved();
      }
    }
  }

  void _burst(Offset at, Color color, int n) {
    for (var i = 0; i < n; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final v = 120 + _rng.nextDouble() * 300;
      _particles.add(
        _Particle(
          at,
          Offset(math.cos(a) * v, math.sin(a) * v - 240),
          [color, Colors.white, AppColors.coin][i % 3],
          3 + _rng.nextDouble() * 5,
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
    final fg = game.skin.onBackground;
    final n = s.size;

    // Floor.
    _fill.color = Colors.white.withValues(alpha: game.skin.isDark ? 0.1 : 0.9);
    c.drawRRect(RRect.fromRectXY(l.grid.inflate(4), 14, 14), _fill);

    final related = hint?.related.toSet() ?? const <Cell>{};
    final bad = inFinale ? const <Cell>{} : s.violations;
    final pairs = inFinale ? const <Cell, Cell>{} : s.pairing;

    for (var r = 0; r < n; r++) {
      for (var col = 0; col < n; col++) {
        final cell = (r, col);
        final rect = l.cellRect(cell);
        final inner = rect.deflate(1.5);
        _fill.color =
            ((r + col).isEven
                    ? const Color(0xFFE9EEF5)
                    : const Color(0xFFF4F7FB))
                .withValues(alpha: game.skin.isDark ? 0.16 : 1);
        c.drawRRect(RRect.fromRectXY(inner, 6, 6), _fill);
        if (related.contains(cell)) {
          _fill.color = AppColors.coin.withValues(alpha: 0.22);
          c.drawRRect(RRect.fromRectXY(inner, 6, 6), _fill);
        }
        final blocked = _blocked[cell] ?? 0;
        if (blocked > 0) {
          _fill.color = AppColors.danger.withValues(alpha: 0.35 * blocked);
          c.drawRRect(RRect.fromRectXY(inner, 6, 6), _fill);
        }
        if (s.isTruck(cell) || inFinale) continue;

        final mark = s.markAt(cell);
        final pop = _pop[cell] ?? 0;
        switch (mark) {
          case Mark.box:
            final scale = 1 + 0.25 * math.sin(pop * math.pi);
            final truck = pairs[cell];
            _painter.drawBox(
              c,
              truck == null ? -1 : s.truckAt(truck)!.color,
              rect.center,
              l.cell * 0.72 * scale,
              happy: !bad.contains(cell),
            );
            if (bad.contains(cell)) {
              _stroke
                ..color = AppColors.danger
                ..strokeWidth = 3;
              c.drawRRect(RRect.fromRectXY(inner.deflate(1), 6, 6), _stroke);
            }
          case Mark.cross:
            _cross(
              c,
              rect.center,
              l.cell * 0.2 * (1 + 0.4 * pop),
              fg.withValues(alpha: 0.55),
              3,
            );
          case Mark.none:
            if (s.autoCrossReason(cell) != null) {
              _cross(
                c,
                rect.center,
                l.cell * 0.1,
                fg.withValues(alpha: 0.18),
                2,
              );
            }
        }
      }
    }

    if (!inFinale) _renderLinks(c, l, pairs);
    _renderTrucks(c, l);
    _renderClues(c, l, fg);

    final h = hint;
    if (h != null && !inFinale) {
      final pulse = 0.5 + 0.5 * math.sin(_time * 7);
      _stroke
        ..color = AppColors.coin.withValues(alpha: 0.65 + 0.35 * pulse)
        ..strokeWidth = 4;
      c.drawRRect(
        RRect.fromRectXY(l.cellRect(h.cell).deflate(1 - pulse * 2), 8, 8),
        _stroke,
      );
    }

    for (final p in _particles) {
      _fill.color = p.color.withValues(
        alpha: (1 - p.t / _Particle.life).clamp(0, 1),
      );
      c.drawRect(
        Rect.fromCenter(center: p.pos, width: p.size, height: p.size * 0.6),
        _fill,
      );
    }
  }

  /// Colored bar joining each box to the truck it belongs to, so the
  /// "one box per truck" rule is visible at a glance.
  void _renderLinks(Canvas c, BoardLayout l, Map<Cell, Cell> pairs) {
    pairs.forEach((box, truck) {
      final color = packageColors[s.truckAt(truck)!.color];
      final a = l.cellRect(box).center, b = l.cellRect(truck).center;
      _stroke
        ..color = color.withValues(alpha: 0.55)
        ..strokeWidth = l.cell * 0.16;
      c.drawLine(Offset.lerp(a, b, 0.3)!, Offset.lerp(a, b, 0.62)!, _stroke);
    });
  }

  void _renderTrucks(Canvas c, BoardLayout l) {
    final f = _finale;
    final loaded = f == null ? s.pairing.values.toSet() : const <Cell>{};
    for (var i = 0; i < s.config.trucks.length; i++) {
      final t = s.config.trucks[i];
      final rect = l.cellRect(t.cell);
      if (f == null) {
        _painter.drawCellTruck(c, rect, t.color);
        if (loaded.contains(t.cell)) _check(c, rect);
        continue;
      }
      // Finale: box i hops into truck i, then the truck drives off.
      final start = 0.35 + i * _stagger;
      final fly = ((f - start) / _fly).clamp(0.0, 1.0);
      final drive = ((f - start - _fly) / _drive).clamp(0.0, 1.0);
      final boxRect = l.cellRect(s.config.solution[i]);
      if (drive < 1) {
        final dx = drive * drive * (size.x - rect.left + 20);
        _painter.drawCellTruck(
          c,
          rect.translate(dx, 0),
          t.color,
          loaded: fly >= 1,
          wheelSpin: drive * 30,
          alpha: 1 - drive * drive,
        );
      }
      if (fly < 1) {
        final k = Curves.easeInOut.transform(fly);
        final pos = Offset.lerp(
          boxRect.center,
          rect.center,
          k,
        )!.translate(0, -math.sin(k * math.pi) * l.cell * 0.5);
        _painter.drawBox(
          c,
          fly > 0 ? t.color : -1,
          pos,
          l.cell * 0.72 * (1 - 0.3 * k),
          happy: true,
        );
      }
    }
  }

  void _renderClues(Canvas c, BoardLayout l, Color fg) {
    void clue(Offset center, int want, LineState state, double pulse) {
      final r = l.band * 0.36 * (1 + 0.35 * math.sin(pulse * math.pi));
      final done = state == LineState.done;
      final over = state == LineState.over;
      if (done || over) {
        _fill.color = done ? AppColors.success : AppColors.danger;
        c.drawCircle(center, r, _fill);
      }
      _text(
        c,
        '$want',
        center,
        l.band * 0.58,
        done || over
            ? Colors.white
            : fg.withValues(alpha: want == 0 ? 0.35 : 1),
        bold: true,
      );
    }

    for (var i = 0; i < s.size; i++) {
      clue(
        l.colClue(i),
        s.config.colClues[i],
        inFinale ? LineState.done : s.colState(i),
        _colPulse[i] ?? 0,
      );
      clue(
        l.rowClue(i),
        s.config.rowClues[i],
        inFinale ? LineState.done : s.rowState(i),
        _rowPulse[i] ?? 0,
      );
    }
  }

  /// Small green check on a truck that already has its box.
  void _check(Canvas c, Rect cell) {
    final r = cell.width * 0.15;
    final ctr = Offset(cell.right - r * 1.1, cell.top + r * 1.1);
    _fill.color = AppColors.success;
    c.drawCircle(ctr, r, _fill);
    _stroke
      ..color = Colors.white
      ..strokeWidth = r * 0.35;
    c.drawPath(
      Path()
        ..moveTo(ctr.dx - r * 0.5, ctr.dy)
        ..lineTo(ctr.dx - r * 0.1, ctr.dy + r * 0.4)
        ..lineTo(ctr.dx + r * 0.55, ctr.dy - r * 0.4),
      _stroke,
    );
  }

  void _cross(Canvas c, Offset center, double r, Color color, double width) {
    _stroke
      ..color = color
      ..strokeWidth = width;
    c.drawLine(center.translate(-r, -r), center.translate(r, r), _stroke);
    c.drawLine(center.translate(r, -r), center.translate(-r, r), _stroke);
  }

  final Map<String, TextPainter> _textCache = {};

  void _text(
    Canvas c,
    String text,
    Offset center,
    double size,
    Color color, {
    bool bold = false,
  }) {
    final key = '$text|${size.toStringAsFixed(1)}|${color.toARGB32()}|$bold';
    var tp = _textCache[key];
    if (tp == null) {
      if (_textCache.length > 300) _textCache.clear();
      tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: size,
            color: color,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _textCache[key] = tp;
    }
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }
}
