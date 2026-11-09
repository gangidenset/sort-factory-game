import 'dart:math' as math;

import 'models.dart';
import 'rng.dart';
import 'scoring.dart';
import 'stage_config.dart';

/// Complete, deterministic rule engine for one play of a stage.
///
/// The Flame layer only renders this state and forwards input via [move].
/// Time advances via [update]; nothing here depends on wall-clock time.
class GameSession {
  GameSession(this.config, {SessionModifiers modifiers = SessionModifiers.none})
    : beltCapacity = config.beltCapacity + modifiers.extraBelt,
      _rng = SeededRng(config.seed) {
    final bufferSize = config.bufferSlots == 0
        ? 0
        : math.min(3, config.bufferSlots + modifiers.extraBuffer);
    buffer = List<Package?>.filled(bufferSize, null);
    for (var i = 0; i < config.docks; i++) {
      final req = _newRequirement(exclude: docks.map((d) => d.requirement));
      final next = _newRequirement(exclude: [req]);
      docks.add(
        Dock(requirement: req, next: next, capacity: config.dockCapacity),
      );
    }
    for (var i = 0; i < config.initialPackages; i++) {
      _spawn(pos: i.toDouble());
    }
  }

  final StageConfig config;
  final int beltCapacity;
  final SeededRng _rng;

  /// Packages on the belt; index 0 is the front (at the sorting point).
  final List<Package> belt = [];
  late final List<Package?> buffer;
  final List<Dock> docks = [];

  SessionStatus status = SessionStatus.ready;
  FailReason? failReason;

  int score = 0;
  int delivered = 0;
  int mistakes = 0;
  int combo = 0;
  int maxCombo = 0;
  int movesUsed = 0;
  int discarded = 0;
  int expired = 0;
  int timedDelivered = 0;
  int revivesUsed = 0;
  double elapsed = 0;
  double _spawnTimer = 0;
  int _nextId = 1;

  /// Extra seconds / moves granted by revives.
  double _bonusTime = 0;
  int _bonusMoves = 0;

  /// Events since the last [drainEvents] call (for sound / effects).
  final List<SessionEvent> _events = [];

  // ---------------------------------------------------------------------------
  // Queries

  Package? get front => belt.isEmpty ? null : belt.first;

  bool get isOver =>
      status == SessionStatus.cleared || status == SessionStatus.failed;

  double? get timeLimit =>
      config.timeLimit == null ? null : config.timeLimit! + _bonusTime;

  double? get timeLeft =>
      timeLimit == null ? null : math.max(0, timeLimit! - elapsed);

  int? get moveLimit =>
      config.moveLimit == null ? null : config.moveLimit! + _bonusMoves;

  int? get movesLeft =>
      moveLimit == null ? null : math.max(0, moveLimit! - movesUsed);

  /// True when the belt is one package from jamming.
  bool get jamWarning => belt.length >= beltCapacity - 1;

  int get stars => status == SessionStatus.cleared ? config.starsFor(score) : 0;

  List<SessionEvent> drainEvents() {
    final out = List<SessionEvent>.of(_events);
    _events.clear();
    return out;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle

  void start() {
    if (status == SessionStatus.ready) status = SessionStatus.playing;
  }

  /// Advances the simulation by [dt] seconds.
  void update(double dt) {
    if (status != SessionStatus.playing || dt <= 0) return;
    // Large frame gaps (app resumed etc.) are split so spawns stay consistent.
    var remaining = math.min(dt, 1.0);
    while (remaining > 0 && status == SessionStatus.playing) {
      final step = math.min(remaining, 1 / 30);
      _step(step);
      remaining -= step;
    }
  }

  void _step(double dt) {
    elapsed += dt;

    for (var i = 0; i < belt.length; i++) {
      final p = belt[i];
      p.age += dt;
      p.pos = math.max(i.toDouble(), p.pos - config.beltSpeed * dt);
    }
    for (final p in buffer) {
      p?.age += dt;
    }

    _expireTimed();
    if (isOver) return;

    // An empty belt calls the next package sooner so skilled players are not
    // left waiting (reduces dead time without making the stage harder).
    _spawnTimer += belt.isEmpty ? dt * emptyBeltSpawnBoost : dt;
    if (_spawnTimer >= config.spawnInterval) {
      _spawnTimer -= config.spawnInterval;
      if (belt.length >= beltCapacity) {
        _fail(FailReason.jam);
        return;
      }
      _spawn(pos: beltCapacity.toDouble());
    }

    if (timeLimit != null && elapsed >= timeLimit!) {
      _fail(FailReason.timeUp);
    }
  }

  void _expireTimed() {
    void expire(Package p) {
      expired++;
      _registerMistake();
      _events.add(SessionEvent(SessionEventType.expired, package: p));
    }

    for (final p in belt.where((p) => p.isExpired).toList()) {
      belt.remove(p);
      expire(p);
      if (isOver) return;
    }
    for (var i = 0; i < buffer.length; i++) {
      final p = buffer[i];
      if (p != null && p.isExpired) {
        buffer[i] = null;
        expire(p);
        if (isOver) return;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Input

  /// Whether [src] currently holds a package that may be moved to [tgt].
  bool canMove(Source src, Target tgt) {
    if (status != SessionStatus.playing) return false;
    final p = _peek(src);
    if (p == null) return false;
    return switch (tgt) {
      DockTarget(:final dock) => dock >= 0 && dock < docks.length,
      BufferTarget(:final slot) =>
        slot >= 0 &&
            slot < buffer.length &&
            buffer[slot] == null &&
            src is FrontSource,
      ChuteTarget() => true,
    };
  }

  /// Moves a package. Invalid moves leave the state untouched.
  MoveResult move(Source src, Target tgt) {
    if (!canMove(src, tgt)) return MoveResult.invalid;
    final p = _take(src);
    movesUsed++;

    final MoveResult result;
    switch (tgt) {
      case DockTarget(:final dock):
        result = _deliver(p, docks[dock]);
      case BufferTarget(:final slot):
        buffer[slot] = p;
        result = MoveResult(MoveOutcome.stored, combo: combo, package: p);
        _events.add(SessionEvent(SessionEventType.stored, package: p));
      case ChuteTarget():
        discarded++;
        combo = 0;
        result = MoveResult(MoveOutcome.discarded, package: p);
        _events.add(SessionEvent(SessionEventType.discarded, package: p));
    }

    if (status == SessionStatus.playing) {
      if (delivered >= config.targetDeliveries) {
        status = SessionStatus.cleared;
        _events.add(const SessionEvent(SessionEventType.cleared));
      } else if (movesLeft == 0) {
        _fail(FailReason.outOfMoves);
      }
    }
    return result;
  }

  MoveResult _deliver(Package p, Dock dock) {
    if (!dock.requirement.matches(p)) {
      _registerMistake();
      _events.add(SessionEvent(SessionEventType.wrong, package: p));
      return MoveResult(MoveOutcome.wrong, package: p);
    }
    combo++;
    maxCombo = math.max(maxCombo, combo);
    delivered++;
    if (p.kind == PackageKind.timed) timedDelivered++;
    var gained = Scoring.correct(p, combo);
    dock.filled++;
    var departed = false;
    if (dock.isFull) {
      departed = true;
      gained += Scoring.truckBonus;
      dock.departures++;
      dock.filled = 0;
      dock.requirement = dock.next;
      dock.next = _newRequirement(
        exclude: [
          for (final d in docks) d.requirement,
          for (final d in docks)
            if (d != dock) d.next,
        ],
      );
    }
    score += gained;
    _events.add(
      SessionEvent(SessionEventType.correct, package: p, combo: combo),
    );
    if (departed) {
      _events.add(
        SessionEvent(SessionEventType.truckDeparted, dock: docks.indexOf(dock)),
      );
    }
    if (combo > 0 && combo % 5 == 0) {
      _events.add(SessionEvent(SessionEventType.comboMilestone, combo: combo));
    }
    return MoveResult(
      MoveOutcome.correct,
      scoreDelta: gained,
      truckDeparted: departed,
      combo: combo,
      package: p,
    );
  }

  Package? _peek(Source src) => switch (src) {
    FrontSource() => front,
    BufferSource(:final slot) =>
      slot >= 0 && slot < buffer.length ? buffer[slot] : null,
  };

  Package _take(Source src) {
    switch (src) {
      case FrontSource():
        return belt.removeAt(0);
      case BufferSource(:final slot):
        final p = buffer[slot]!;
        buffer[slot] = null;
        return p;
    }
  }

  void _registerMistake() {
    mistakes++;
    combo = 0;
    if (mistakes >= config.maxMistakes) _fail(FailReason.mistakes);
  }

  void _fail(FailReason reason) {
    if (isOver) return;
    status = SessionStatus.failed;
    failReason = reason;
    _events.add(SessionEvent(SessionEventType.failed, failReason: reason));
  }

  // ---------------------------------------------------------------------------
  // Revive (rewarded ad)

  static const int maxRevives = 1;

  /// Spawn-timer multiplier while the belt is empty.
  static const double emptyBeltSpawnBoost = 1.5;

  bool get canRevive =>
      status == SessionStatus.failed && revivesUsed < maxRevives;

  /// Restores a failed session so play can continue. Returns false if not
  /// allowed.
  bool revive() {
    if (!canRevive) return false;
    switch (failReason!) {
      case FailReason.mistakes:
        mistakes = math.max(0, config.maxMistakes - 2);
      case FailReason.jam:
        final removeCount = math.min(3, belt.length);
        belt.removeRange(belt.length - removeCount, belt.length);
        _spawnTimer = 0;
      case FailReason.timeUp:
        _bonusTime += 15;
      case FailReason.outOfMoves:
        _bonusMoves += 5;
    }
    revivesUsed++;
    failReason = null;
    status = SessionStatus.playing;
    return true;
  }

  // ---------------------------------------------------------------------------
  // Generation

  Requirement _newRequirement({Iterable<Requirement> exclude = const []}) {
    final excluded = exclude.toSet();
    for (var attempt = 0; attempt < 8; attempt++) {
      final req = _randomRequirement();
      // Avoid two open trucks wanting exactly the same thing.
      if (!excluded.contains(req)) return req;
    }
    return _randomRequirement();
  }

  Requirement _randomRequirement() {
    if (config.useMarks) {
      final mark = 1 + _rng.nextInt(kMarkCount - 1);
      if (_rng.chance(config.markOnlyRate)) return Requirement(mark: mark);
      if (_rng.chance(config.markDockRate)) {
        return Requirement(color: _rng.pick(config.colors), mark: mark);
      }
    }
    return Requirement(color: _rng.pick(config.colors));
  }

  void _spawn({required double pos}) {
    // Most packages fit an open truck; "off" packages fit an upcoming truck so
    // that planning with the buffer pays off.
    final Requirement target;
    if (_rng.chance(config.offRate)) {
      target = _rng.pick(docks).next;
    } else {
      target = _rng.pick(docks).requirement;
    }
    final int color = target.color ?? _rng.pick<int>(config.colors);
    final mark = config.useMarks
        ? (target.mark ?? 1 + _rng.nextInt(kMarkCount - 1))
        : kMarkNone;

    var kind = PackageKind.normal;
    final roll = _rng.nextDouble();
    if (roll < config.timedRate) {
      kind = PackageKind.timed;
    } else if (roll < config.timedRate + config.shiftRate) {
      kind = PackageKind.shifting;
    }

    int? colorB;
    if (kind == PackageKind.shifting) {
      final others = config.colors.where((c) => c != color).toList();
      if (others.isEmpty) {
        kind = PackageKind.normal;
      } else {
        colorB = _rng.pick(others);
      }
    }

    final p = Package(
      id: _nextId++,
      colorA: color,
      colorB: colorB,
      mark: mark,
      kind: kind,
      timeLimit: kind == PackageKind.timed ? config.timedSeconds : null,
      shiftPeriod: config.shiftPeriod,
      pos: pos,
    );
    belt.add(p);
    _events.add(SessionEvent(SessionEventType.spawned, package: p));
  }

  // ---------------------------------------------------------------------------
  // Hint

  /// Suggests the best target for the front package (used by the hint
  /// feature and tutorials).
  Target? hintForFront() {
    final p = front;
    if (p == null) return null;
    for (var i = 0; i < docks.length; i++) {
      if (docks[i].requirement.matches(p)) return DockTarget(i);
    }
    final empty = buffer.indexOf(null);
    if (empty >= 0 && docks.any((d) => d.next.matches(p))) {
      return BufferTarget(empty);
    }
    if (empty >= 0 && p.kind == PackageKind.shifting) {
      return BufferTarget(empty);
    }
    return const ChuteTarget();
  }

  /// A buffered package that can be delivered right now, if any.
  (int slot, int dock)? hintForBuffer() {
    for (var s = 0; s < buffer.length; s++) {
      final p = buffer[s];
      if (p == null) continue;
      for (var d = 0; d < docks.length; d++) {
        if (docks[d].requirement.matches(p)) return (s, d);
      }
    }
    return null;
  }
}

enum SessionEventType {
  spawned,
  correct,
  wrong,
  stored,
  discarded,
  expired,
  truckDeparted,
  comboMilestone,
  cleared,
  failed,
}

class SessionEvent {
  const SessionEvent(
    this.type, {
    this.package,
    this.dock,
    this.combo = 0,
    this.failReason,
  });

  final SessionEventType type;
  final Package? package;
  final int? dock;
  final int combo;
  final FailReason? failReason;
}
