import 'dart:math' as math;

import 'models.dart';
import 'stage_config.dart';

/// Turn-based rule engine for one play of a stage.
///
/// Tap a lane → its front package flies to a parked truck of the same color,
/// or to the shelf. Full trucks depart, the next truck arrives and pulls
/// matching packages off the shelf, which can fill it again → chain.
class GameSession {
  GameSession(this.config, {SessionModifiers modifiers = SessionModifiers.none})
    : shelfCapacity = config.shelf + modifiers.extraShelf,
      freeUndos = 1 + modifiers.extraUndo {
    var id = 1;
    for (var l = 0; l < config.lanes.length; l++) {
      lanes.add([
        for (var i = 0; i < config.lanes[l].length; i++)
          Package(
            id: id++,
            color: config.lanes[l][i],
            hidden: config.hidden.contains('$l:$i') && i > 0,
          ),
      ]);
    }
    for (var i = 0; i < config.docks; i++) {
      docks.add(_nextTruck());
    }
  }

  final StageConfig config;
  int shelfCapacity;

  /// Undos available without watching an ad.
  int freeUndos;

  final List<List<Package>> lanes = [];
  final List<Truck?> docks = [];
  final List<Package> shelf = [];

  int _queueIndex = 0;
  int _truckIds = 1;

  SessionStatus status = SessionStatus.ready;
  FailReason? failReason;

  int score = 0;
  int moves = 0;
  int shipped = 0; // trucks departed
  int delivered = 0; // packages loaded
  int shelfPlacements = 0;
  int maxChain = 0;
  int undosUsed = 0;
  int revivesUsed = 0;

  final List<_Snapshot> _history = [];
  final List<SessionEvent> _events = [];

  // ---------------------------------------------------------------------------
  // Queries

  bool get isOver =>
      status == SessionStatus.cleared || status == SessionStatus.failed;

  int get totalTrucks => config.trucks.length;

  /// Upcoming trucks (not yet parked), in arrival order.
  List<TruckSpec> get queue => config.trucks.sublist(_queueIndex);

  int get stars =>
      status == SessionStatus.cleared ? config.starsFor(shelfPlacements) : 0;

  bool isLocked(int lane) =>
      config.locks.any((l) => l.lane == lane && shipped < l.after);

  /// Trucks still needed before [lane] opens (0 if open).
  int unlockIn(int lane) {
    var need = 0;
    for (final l in config.locks) {
      if (l.lane == lane) need = math.max(need, l.after - shipped);
    }
    return need;
  }

  bool canTap(int lane) =>
      status == SessionStatus.playing &&
      lane >= 0 &&
      lane < lanes.length &&
      lanes[lane].isNotEmpty &&
      !isLocked(lane);

  bool get canUndo => _history.isNotEmpty && status == SessionStatus.playing;

  bool get shelfDanger => shelf.length >= shelfCapacity - 1;

  /// Dock index a package of [color] would go to right now, or null.
  int? dockFor(int color) {
    int? best;
    for (var i = 0; i < docks.length; i++) {
      final t = docks[i];
      if (t == null || t.color != color || t.isFull) continue;
      if (best == null || t.filled > docks[best]!.filled) best = i;
    }
    return best;
  }

  List<SessionEvent> drainEvents() {
    final out = List<SessionEvent>.of(_events);
    _events.clear();
    return out;
  }

  // ---------------------------------------------------------------------------
  // Actions

  void start() {
    if (status == SessionStatus.ready) status = SessionStatus.playing;
  }

  /// Taps [lane]. Returns false (state unchanged) if not allowed.
  bool tap(int lane) {
    if (!canTap(lane)) return false;
    _history.add(_Snapshot.of(this));
    moves++;
    final p = lanes[lane].removeAt(0);
    p.hidden = false;
    if (lanes[lane].isNotEmpty && lanes[lane].first.hidden) {
      lanes[lane].first.hidden = false;
      _events.add(SessionEvent.reveal(lane));
    }

    final dock = dockFor(p.color);
    if (dock != null) {
      _load(p, dock, from: LaneOrigin(lane));
      _resolveDepartures();
    } else if (shelf.length < shelfCapacity) {
      shelf.add(p);
      shelfPlacements++;
      _events.add(
        SessionEvent.move(p, LaneOrigin(lane), ToShelf(shelf.length - 1)),
      );
    } else {
      _events.add(SessionEvent.move(p, LaneOrigin(lane), const Overflow()));
      _fail(FailReason.shelfOverflow);
      return true;
    }
    _checkEnd();
    return true;
  }

  void _load(Package p, int dock, {required Origin from}) {
    docks[dock]!.filled++;
    delivered++;
    score += 10;
    _events.add(SessionEvent.move(p, from, ToTruck(dock)));
  }

  /// Departs full trucks, brings new ones and pulls from the shelf until
  /// nothing changes. Each departure in one tap raises the chain level.
  void _resolveDepartures() {
    var chain = 0;
    while (true) {
      final full = docks.indexWhere((t) => t != null && t.isFull);
      if (full < 0) break;
      chain++;
      shipped++;
      maxChain = math.max(maxChain, chain);
      score += 100 * chain;
      final gone = docks[full]!;
      docks[full] = _nextTruck();
      _events.add(SessionEvent.depart(full, gone, docks[full], chain));
      // Arriving trucks take matching packages from the shelf.
      var i = 0;
      while (i < shelf.length) {
        final d = dockFor(shelf[i].color);
        if (d == null) {
          i++;
          continue;
        }
        final p = shelf.removeAt(i);
        _load(p, d, from: ShelfOrigin(i));
        _events.add(SessionEvent.shelfCompacted());
      }
    }
  }

  Truck? _nextTruck() {
    if (_queueIndex >= config.trucks.length) return null;
    final s = config.trucks[_queueIndex++];
    return Truck(id: _truckIds++, color: s.color, capacity: s.capacity);
  }

  void _checkEnd() {
    if (status != SessionStatus.playing) return;
    if (docks.every((t) => t == null) && _queueIndex >= config.trucks.length) {
      status = SessionStatus.cleared;
      score += 200 + 50 * (shelfCapacity - shelf.length);
      _events.add(const SessionEvent(SessionEventType.cleared));
      return;
    }
    final anyTap = List.generate(lanes.length, (i) => i).any(canTap);
    if (!anyTap) _fail(FailReason.stuck);
  }

  void _fail(FailReason r) {
    status = SessionStatus.failed;
    failReason = r;
    _events.add(SessionEvent(SessionEventType.failed, failReason: r));
  }

  /// Reverts the last tap. Free undos are consumed first; [paid] marks an
  /// ad-granted undo.
  bool undo({bool paid = false}) {
    if (!canUndo) return false;
    if (!paid) {
      if (freeUndos <= 0) return false;
      freeUndos--;
    }
    _history.removeLast().restore(this);
    undosUsed++;
    _events.add(const SessionEvent(SessionEventType.undone));
    return true;
  }

  // ---------------------------------------------------------------------------
  // Revive (rewarded ad)

  static const int maxRevives = 1;

  bool get canRevive =>
      status == SessionStatus.failed &&
      revivesUsed < maxRevives &&
      _history.isNotEmpty;

  /// Undoes the fatal move and adds one shelf slot for the rest of the stage.
  bool revive() {
    if (!canRevive) return false;
    _history.removeLast().restore(this);
    status = SessionStatus.playing;
    failReason = null;
    revivesUsed++;
    shelfCapacity++;
    _events.add(const SessionEvent(SessionEventType.undone));
    return true;
  }

  // ---------------------------------------------------------------------------
  // Solver-facing state key (see solver.dart).

  String stateKey() {
    final lanePart = lanes.map((l) => l.length).join(',');
    final shelfPart = (shelf.map((p) => p.color).toList()..sort()).join('');
    final dockPart =
        (docks.map((t) => t == null ? '-' : '${t.color}${t.filled}').toList()
              ..sort())
            .join('|');
    return '$lanePart/$shelfPart/$dockPart/$_queueIndex/$shelfCapacity';
  }

  GameSession clone() {
    final s = GameSession._empty(config, shelfCapacity, freeUndos);
    _Snapshot.of(this).restore(s);
    s.status = status;
    return s;
  }

  GameSession._empty(this.config, this.shelfCapacity, this.freeUndos);
}

class _Snapshot {
  _Snapshot.of(GameSession s)
    : lanes = [
        for (final l in s.lanes) [for (final p in l) p.copy()],
      ],
      docks = [for (final t in s.docks) t?.copy()],
      shelf = [for (final p in s.shelf) p.copy()],
      queueIndex = s._queueIndex,
      truckIds = s._truckIds,
      score = s.score,
      moves = s.moves,
      shipped = s.shipped,
      delivered = s.delivered,
      shelfPlacements = s.shelfPlacements,
      maxChain = s.maxChain;

  final List<List<Package>> lanes;
  final List<Truck?> docks;
  final List<Package> shelf;
  final int queueIndex, truckIds, score, moves, shipped, delivered;
  final int shelfPlacements, maxChain;

  void restore(GameSession s) {
    s.lanes
      ..clear()
      ..addAll([
        for (final l in lanes) [for (final p in l) p.copy()],
      ]);
    s.docks
      ..clear()
      ..addAll([for (final t in docks) t?.copy()]);
    s.shelf
      ..clear()
      ..addAll([for (final p in shelf) p.copy()]);
    s._queueIndex = queueIndex;
    s._truckIds = truckIds;
    s.score = score;
    s.moves = moves;
    s.shipped = shipped;
    s.delivered = delivered;
    s.shelfPlacements = shelfPlacements;
    s.maxChain = maxChain;
  }
}

// -----------------------------------------------------------------------------
// Events (drive animations and sounds)

sealed class Origin {
  const Origin();
}

class LaneOrigin extends Origin {
  const LaneOrigin(this.lane);
  final int lane;
}

class ShelfOrigin extends Origin {
  const ShelfOrigin(this.slot);
  final int slot;
}

enum SessionEventType {
  move,
  depart,
  reveal,
  shelfCompacted,
  undone,
  cleared,
  failed,
}

class SessionEvent {
  const SessionEvent(
    this.type, {
    this.package,
    this.origin,
    this.destination,
    this.dock,
    this.departed,
    this.arrived,
    this.chain = 0,
    this.lane,
    this.failReason,
  });

  factory SessionEvent.move(Package p, Origin from, Destination to) =>
      SessionEvent(
        SessionEventType.move,
        package: p,
        origin: from,
        destination: to,
      );

  factory SessionEvent.depart(int dock, Truck gone, Truck? next, int chain) =>
      SessionEvent(
        SessionEventType.depart,
        dock: dock,
        departed: gone,
        arrived: next,
        chain: chain,
      );

  factory SessionEvent.reveal(int lane) =>
      SessionEvent(SessionEventType.reveal, lane: lane);

  factory SessionEvent.shelfCompacted() =>
      const SessionEvent(SessionEventType.shelfCompacted);

  final SessionEventType type;
  final Package? package;
  final Origin? origin;
  final Destination? destination;
  final int? dock;
  final Truck? departed;
  final Truck? arrived;
  final int chain;
  final int? lane;
  final FailReason? failReason;
}
