import 'models.dart';

enum Difficulty { easy, normal, hard }

/// Immutable puzzle definition, loaded from `assets/stages/stages.json`.
///
/// `solution[i]` is the box that belongs to `trucks[i]`. Row / column clues
/// are derived from the solution. `tool/gen_stages.py` guarantees the solution
/// is unique and reachable by deduction (no guessing).
class StageConfig {
  StageConfig({
    required this.id,
    this.name = '',
    this.difficulty = Difficulty.easy,
    required this.size,
    required this.trucks,
    required this.solution,
    this.tier = 1,
    this.tutorial,
  }) : rowClues = List.generate(
         size,
         (r) => solution.where((b) => b.$1 == r).length,
       ),
       colClues = List.generate(
         size,
         (c) => solution.where((b) => b.$2 == c).length,
       );

  final int id;
  final String name;
  final Difficulty difficulty;

  /// Grid is size x size.
  final int size;
  final List<Truck> trucks;
  final List<Cell> solution;
  final List<int> rowClues;
  final List<int> colClues;

  /// Hardest deduction technique needed (1 counting, 2 patterns, 3 what-if).
  final int tier;
  final String? tutorial;

  int get boxCount => solution.length;

  factory StageConfig.fromJson(Map<String, dynamic> j) {
    final cfg = StageConfig(
      id: (j['id'] as num).toInt(),
      name: j['name'] as String? ?? '',
      difficulty: Difficulty.values.byName(
        j['difficulty'] as String? ?? 'easy',
      ),
      size: (j['size'] as num).toInt(),
      tier: (j['tier'] as num?)?.toInt() ?? 1,
      trucks: [
        for (final t in j['trucks'] as List)
          Truck((
            ((t as List)[0] as num).toInt(),
            (t[1] as num).toInt(),
          ), t.length > 2 ? (t[2] as num).toInt() : 0),
      ],
      solution: [
        for (final b in j['solution'] as List)
          (((b as List)[0] as num).toInt(), (b[1] as num).toInt()),
      ],
      tutorial: j['tutorial'] as String?,
    );
    cfg.validate();
    return cfg;
  }

  /// Throws [FormatException] if the stored solution breaks the rules.
  void validate() {
    void check(bool ok, String msg) {
      if (!ok) throw FormatException('Stage $id: $msg');
    }

    bool inside(Cell c) => c.$1 >= 0 && c.$1 < size && c.$2 >= 0 && c.$2 < size;

    check(id > 0, 'id must be > 0');
    check(size >= 3 && size <= 9, 'size must be 3..9');
    check(trucks.isNotEmpty, 'no trucks');
    check(trucks.length == solution.length, 'one box per truck required');
    final truckCells = {for (final t in trucks) t.cell};
    final boxes = solution.toSet();
    check(truckCells.length == trucks.length, 'duplicate truck');
    check(boxes.length == solution.length, 'duplicate box');
    check(truckCells.every(inside) && boxes.every(inside), 'cell out of grid');
    check(truckCells.intersection(boxes).isEmpty, 'box on a truck');
    check(
      trucks.every((t) => t.color >= 0 && t.color < kColorCount),
      'bad color',
    );
    for (var i = 0; i < trucks.length; i++) {
      final t = trucks[i].cell, b = solution[i];
      check(
        (t.$1 - b.$1).abs() + (t.$2 - b.$2).abs() == 1,
        'box $i is not next to its truck',
      );
    }
    for (final a in boxes) {
      for (final d in around8) {
        check(!boxes.contains((a.$1 + d.$1, a.$2 + d.$2)), 'boxes touch at $a');
      }
    }
  }
}

/// Run-time modifiers from factory upgrades (assist only, never required).
class SessionModifiers {
  const SessionModifiers({this.extraHints = 0});
  final int extraHints;
  static const none = SessionModifiers();
}
