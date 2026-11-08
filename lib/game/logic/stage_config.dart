import 'models.dart';

enum Difficulty { easy, normal, hard }

/// Immutable stage definition, loaded from `assets/stages/stages.json`.
///
/// Every field has a safe default so stage files stay short and new fields can
/// be added without touching existing stages.
class StageConfig {
  const StageConfig({
    required this.id,
    this.name = '',
    this.difficulty = Difficulty.easy,
    this.colors = const [0, 1],
    this.docks = 2,
    this.dockCapacity = 3,
    this.targetDeliveries = 10,
    this.maxMistakes = 3,
    this.spawnInterval = 2.0,
    this.beltSpeed = 3.0,
    this.beltCapacity = 6,
    this.bufferSlots = 0,
    this.initialPackages = 1,
    this.timeLimit,
    this.moveLimit,
    this.offRate = 0.1,
    this.timedRate = 0,
    this.timedSeconds = 9,
    this.shiftRate = 0,
    this.shiftPeriod = 2.0,
    this.useMarks = false,
    this.markDockRate = 0,
    this.markOnlyRate = 0,
    this.starScores = const [0, 0],
    this.seed = 1,
    this.tutorial,
  });

  final int id;
  final String name;
  final Difficulty difficulty;

  /// Palette indices used in this stage.
  final List<int> colors;
  final int docks;
  final int dockCapacity;
  final int targetDeliveries;
  final int maxMistakes;

  /// Seconds between package spawns.
  final double spawnInterval;

  /// Belt speed in slots per second.
  final double beltSpeed;

  /// Packages the belt can hold before it jams.
  final int beltCapacity;
  final int bufferSlots;
  final int initialPackages;

  /// Optional time limit in seconds.
  final double? timeLimit;

  /// Optional move limit (every store / sort / discard counts as one move).
  final int? moveLimit;

  /// Probability that a spawned package does not fit any currently open dock
  /// (it fits an upcoming truck instead, which rewards using the buffer).
  final double offRate;
  final double timedRate;
  final double timedSeconds;
  final double shiftRate;
  final double shiftPeriod;

  /// Whether packages carry marks (star / circle / triangle).
  final bool useMarks;

  /// Probability that a truck requires color AND mark.
  final double markDockRate;

  /// Probability that a truck requires a mark only (any color).
  final double markOnlyRate;

  /// Score thresholds for 2 and 3 stars (1 star = clear).
  final List<int> starScores;
  final int seed;

  /// Key of a tutorial shown before the stage starts.
  final String? tutorial;

  int starsFor(int score) {
    if (starScores.length >= 2 && score >= starScores[1]) return 3;
    if (starScores.isNotEmpty && score >= starScores[0]) return 2;
    return 1;
  }

  factory StageConfig.fromJson(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    int i(String k, int def) => (j[k] as num?)?.toInt() ?? def;
    final cfg = StageConfig(
      id: i('id', 0),
      name: j['name'] as String? ?? '',
      difficulty: Difficulty.values.byName(
        j['difficulty'] as String? ?? 'easy',
      ),
      colors:
          (j['colors'] as List?)?.map((e) => (e as num).toInt()).toList() ??
          const [0, 1],
      docks: i('docks', 2),
      dockCapacity: i('dockCapacity', 3),
      targetDeliveries: i('targetDeliveries', 10),
      maxMistakes: i('maxMistakes', 3),
      spawnInterval: d('spawnInterval', 2.0),
      beltSpeed: d('beltSpeed', 3.0),
      beltCapacity: i('beltCapacity', 6),
      bufferSlots: i('bufferSlots', 0),
      initialPackages: i('initialPackages', 1),
      timeLimit: (j['timeLimit'] as num?)?.toDouble(),
      moveLimit: (j['moveLimit'] as num?)?.toInt(),
      offRate: d('offRate', 0.1),
      timedRate: d('timedRate', 0),
      timedSeconds: d('timedSeconds', 9),
      shiftRate: d('shiftRate', 0),
      shiftPeriod: d('shiftPeriod', 2.0),
      useMarks: j['useMarks'] as bool? ?? false,
      markDockRate: d('markDockRate', 0),
      markOnlyRate: d('markOnlyRate', 0),
      starScores:
          (j['starScores'] as List?)?.map((e) => (e as num).toInt()).toList() ??
          const [0, 0],
      seed: i('seed', 1),
      tutorial: j['tutorial'] as String?,
    );
    cfg.validate();
    return cfg;
  }

  /// Throws [FormatException] for stage data that would break the game.
  void validate() {
    void check(bool ok, String msg) {
      if (!ok) throw FormatException('Stage $id: $msg');
    }

    check(id > 0, 'id must be > 0');
    check(colors.isNotEmpty, 'colors must not be empty');
    check(colors.every((c) => c >= 0 && c < kColorCount), 'bad color index');
    check(docks >= 1 && docks <= 4, 'docks must be 1..4');
    check(dockCapacity >= 1, 'dockCapacity must be >= 1');
    check(targetDeliveries >= 1, 'targetDeliveries must be >= 1');
    check(maxMistakes >= 1, 'maxMistakes must be >= 1');
    check(spawnInterval > 0, 'spawnInterval must be > 0');
    check(beltSpeed > 0, 'beltSpeed must be > 0');
    check(beltCapacity >= 2, 'beltCapacity must be >= 2');
    check(bufferSlots >= 0 && bufferSlots <= 3, 'bufferSlots must be 0..3');
    check(
      initialPackages >= 0 && initialPackages < beltCapacity,
      'initialPackages out of range',
    );
    check(shiftRate == 0 || colors.length >= 2, 'shifting needs 2+ colors');
    check(
      moveLimit == null || moveLimit! >= targetDeliveries,
      'moveLimit below targetDeliveries',
    );
  }
}

/// Run-time modifiers from factory upgrades (assist only, never required).
class SessionModifiers {
  const SessionModifiers({this.extraBelt = 0, this.extraBuffer = 0});

  final int extraBelt;

  /// Only applied on stages that already have a buffer.
  final int extraBuffer;

  static const none = SessionModifiers();
}
