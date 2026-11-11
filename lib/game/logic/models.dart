/// Pure puzzle models. No Flutter / Flame dependency so they are unit-testable.
library;

/// Package colors are indices into the palette (see `ui/palette.dart`).
/// 0 red, 1 blue, 2 green, 3 yellow, 4 purple, 5 orange.
const int kColorCount = 6;

class Package {
  Package({required this.id, required this.color, this.hidden = false});

  final int id;
  final int color;

  /// Covered box ("?") until it reaches the front of its lane.
  bool hidden;

  Package copy() => Package(id: id, color: color, hidden: hidden);
}

/// A truck parked at a dock, waiting to be filled with one color.
class Truck {
  Truck({
    required this.id,
    required this.color,
    required this.capacity,
    this.filled = 0,
  });

  final int id;
  final int color;
  final int capacity;
  int filled;

  bool get isFull => filled >= capacity;

  Truck copy() =>
      Truck(id: id, color: color, capacity: capacity, filled: filled);
}

/// Truck definition in the stage queue.
class TruckSpec {
  const TruckSpec(this.color, this.capacity);
  final int color;
  final int capacity;
}

enum SessionStatus { ready, playing, cleared, failed }

enum FailReason {
  /// A package had nowhere to go and the shelf was full.
  shelfOverflow,

  /// No lane can be tapped but trucks are still waiting (locked lanes).
  stuck,
}

/// Where a moved package ended up.
sealed class Destination {
  const Destination();
}

class ToTruck extends Destination {
  const ToTruck(this.dock);
  final int dock;
}

class ToShelf extends Destination {
  const ToShelf(this.slot);
  final int slot;
}

/// The package fell because the shelf was full (stage failed).
class Overflow extends Destination {
  const Overflow();
}
