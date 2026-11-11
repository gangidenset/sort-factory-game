import 'models.dart';

enum Difficulty { easy, normal, hard }

/// A lane that opens only after [after] trucks have departed.
class LaneLock {
  const LaneLock(this.lane, this.after);
  final int lane;
  final int after;
}

/// Immutable puzzle definition, loaded from `assets/stages/stages.json`.
///
/// Layouts are stored explicitly (not generated at runtime) so every stage is
/// hand-editable and verified solvable by `test/game/stage_catalog_test.dart`.
class StageConfig {
  StageConfig({
    required this.id,
    this.name = '',
    this.difficulty = Difficulty.easy,
    required this.lanes,
    required this.trucks,
    this.docks = 2,
    this.shelf = 5,
    this.hidden = const {},
    this.locks = const [],
    this.par = 0,
    this.tutorial,
  });

  final int id;
  final String name;
  final Difficulty difficulty;

  /// Package colors per lane, front (index 0) to back.
  final List<List<int>> lanes;

  /// Truck queue in arrival order.
  final List<TruckSpec> trucks;

  /// Number of trucks parked at once.
  final int docks;

  /// Shelf slots.
  final int shelf;

  /// Hidden packages as "lane:index" keys.
  final Set<String> hidden;
  final List<LaneLock> locks;

  /// Fewest shelf placements a perfect solution needs (computed by the
  /// solver in `tool/gen_stages.py`). Used for star rating.
  final int par;
  final String? tutorial;

  int get packageCount => lanes.fold(0, (a, l) => a + l.length);

  /// ★3 = at most [par] shelf placements, ★2 = par + 2, otherwise ★1.
  int starsFor(int shelfPlacements) {
    if (shelfPlacements <= par) return 3;
    if (shelfPlacements <= par + 2) return 2;
    return 1;
  }

  factory StageConfig.fromJson(Map<String, dynamic> j) {
    final cap = (j['truckCapacity'] as num?)?.toInt() ?? 3;
    final caps = (j['truckCaps'] as List?)
        ?.map((e) => (e as num).toInt())
        .toList();
    final colors = (j['trucks'] as List)
        .map((e) => (e as num).toInt())
        .toList();
    final cfg = StageConfig(
      id: (j['id'] as num).toInt(),
      name: j['name'] as String? ?? '',
      difficulty: Difficulty.values.byName(
        j['difficulty'] as String? ?? 'easy',
      ),
      lanes: [
        for (final l in j['lanes'] as List)
          [for (final c in l as List) (c as num).toInt()],
      ],
      trucks: [
        for (var i = 0; i < colors.length; i++)
          TruckSpec(colors[i], caps != null ? caps[i] : cap),
      ],
      docks: (j['docks'] as num?)?.toInt() ?? 2,
      shelf: (j['shelf'] as num?)?.toInt() ?? 5,
      hidden: {
        for (final h in (j['hidden'] as List?) ?? const [])
          '${(h as List)[0]}:${h[1]}',
      },
      locks: [
        for (final l in (j['locks'] as List?) ?? const [])
          LaneLock(
            ((l as Map)['lane'] as num).toInt(),
            (l['after'] as num).toInt(),
          ),
      ],
      par: (j['par'] as num?)?.toInt() ?? 0,
      tutorial: j['tutorial'] as String?,
    );
    cfg.validate();
    return cfg;
  }

  /// Throws [FormatException] for data that would break the game.
  void validate() {
    void check(bool ok, String msg) {
      if (!ok) throw FormatException('Stage $id: $msg');
    }

    check(id > 0, 'id must be > 0');
    check(lanes.isNotEmpty && lanes.length <= 6, 'lanes must be 1..6');
    check(docks >= 1 && docks <= 4, 'docks must be 1..4');
    check(shelf >= 1 && shelf <= 8, 'shelf must be 1..8');
    check(trucks.isNotEmpty, 'trucks must not be empty');
    check(
      trucks.every((t) => t.capacity >= 1 && t.capacity <= 5),
      'bad capacity',
    );
    final all = [for (final l in lanes) ...l];
    check(all.every((c) => c >= 0 && c < kColorCount), 'bad color index');
    // Every package must have a truck seat and every seat a package.
    for (var c = 0; c < kColorCount; c++) {
      final pk = all.where((x) => x == c).length;
      final seats = trucks
          .where((t) => t.color == c)
          .fold(0, (a, t) => a + t.capacity);
      check(pk == seats, 'color $c: $pk packages but $seats seats');
    }
    for (final l in locks) {
      check(l.lane >= 0 && l.lane < lanes.length, 'lock lane out of range');
    }
  }
}

/// Run-time modifiers from factory upgrades (assist only, never required).
class SessionModifiers {
  const SessionModifiers({this.extraShelf = 0, this.extraUndo = 0});

  final int extraShelf;
  final int extraUndo;

  static const none = SessionModifiers();
}
