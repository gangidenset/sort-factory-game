/// Pure game models. No Flutter / Flame dependency so they are unit-testable.
library;

/// Package colors are indices into the palette (see `ui/palette.dart`).
/// 0 red, 1 blue, 2 green, 3 yellow, 4 purple, 5 orange.
const int kColorCount = 6;

/// Marks printed on packages. 0 = none.
/// 1 star, 2 circle, 3 triangle.
const int kMarkNone = 0;
const int kMarkCount = 4;

enum PackageKind {
  /// Plain package.
  normal,

  /// Must be sorted before its timer runs out, otherwise it counts as a miss.
  timed,

  /// Alternates between two colors over time.
  shifting,
}

class Package {
  Package({
    required this.id,
    required this.colorA,
    this.colorB,
    this.mark = kMarkNone,
    this.kind = PackageKind.normal,
    this.timeLimit,
    this.shiftPeriod = 2.0,
    this.pos = 0,
  }) : assert(kind != PackageKind.shifting || colorB != null),
       assert(kind != PackageKind.timed || timeLimit != null);

  final int id;
  final int colorA;
  final int? colorB;
  final int mark;
  final PackageKind kind;

  /// Seconds until a timed package expires (measured from spawn).
  final double? timeLimit;

  /// Seconds per color for shifting packages.
  final double shiftPeriod;

  /// Seconds since spawn.
  double age = 0;

  /// Position on the belt in slot units. 0 = at the sorting point.
  double pos;

  /// Current color (shifting packages change over time).
  int get color {
    if (kind != PackageKind.shifting) return colorA;
    final phase = (age / shiftPeriod).floor();
    return phase.isEven ? colorA : colorB!;
  }

  /// Seconds left for timed packages, null otherwise.
  double? get remaining => timeLimit == null ? null : timeLimit! - age;

  bool get isExpired => remaining != null && remaining! <= 0;
}

/// What a dock (truck) accepts. A null field means "any".
class Requirement {
  const Requirement({this.color, this.mark});

  final int? color;
  final int? mark;

  bool matches(Package p) =>
      (color == null || p.color == color) && (mark == null || p.mark == mark);

  @override
  bool operator ==(Object other) =>
      other is Requirement && other.color == color && other.mark == mark;

  @override
  int get hashCode => Object.hash(color, mark);

  @override
  String toString() => 'Req(color: $color, mark: $mark)';
}

/// A delivery dock with a truck waiting to be filled.
class Dock {
  Dock({required this.requirement, required this.next, required this.capacity});

  Requirement requirement;

  /// The requirement of the truck that arrives after this one departs.
  Requirement next;

  final int capacity;
  int filled = 0;

  /// Total trucks dispatched from this dock (for animation / stats).
  int departures = 0;

  bool get isFull => filled >= capacity;
}

/// Where a package is taken from.
sealed class Source {
  const Source();
}

class FrontSource extends Source {
  const FrontSource();
  @override
  bool operator ==(Object other) => other is FrontSource;
  @override
  int get hashCode => 1;
}

class BufferSource extends Source {
  const BufferSource(this.slot);
  final int slot;
  @override
  bool operator ==(Object other) => other is BufferSource && other.slot == slot;
  @override
  int get hashCode => Object.hash(2, slot);
}

/// Where a package is sent.
sealed class Target {
  const Target();
}

class DockTarget extends Target {
  const DockTarget(this.dock);
  final int dock;
  @override
  bool operator ==(Object other) => other is DockTarget && other.dock == dock;
  @override
  int get hashCode => Object.hash(3, dock);
  @override
  String toString() => 'DockTarget($dock)';
}

class BufferTarget extends Target {
  const BufferTarget(this.slot);
  final int slot;
  @override
  bool operator ==(Object other) => other is BufferTarget && other.slot == slot;
  @override
  int get hashCode => Object.hash(4, slot);
  @override
  String toString() => 'BufferTarget($slot)';
}

class ChuteTarget extends Target {
  const ChuteTarget();
  @override
  bool operator ==(Object other) => other is ChuteTarget;
  @override
  int get hashCode => 5;
  @override
  String toString() => 'ChuteTarget';
}

enum MoveOutcome {
  /// Delivered to the right dock.
  correct,

  /// Delivered to the wrong dock (counts as a mistake).
  wrong,

  /// Put into a buffer slot.
  stored,

  /// Thrown into the return chute (no mistake, breaks combo).
  discarded,

  /// The move was not allowed; state unchanged.
  invalid,
}

class MoveResult {
  const MoveResult(
    this.outcome, {
    this.scoreDelta = 0,
    this.truckDeparted = false,
    this.combo = 0,
    this.package,
  });

  static const invalid = MoveResult(MoveOutcome.invalid);

  final MoveOutcome outcome;
  final int scoreDelta;
  final bool truckDeparted;
  final int combo;
  final Package? package;
}

enum SessionStatus { ready, playing, cleared, failed }

enum FailReason { mistakes, jam, timeUp, outOfMoves }
