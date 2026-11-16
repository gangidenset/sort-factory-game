import 'dart:convert';

import 'stage_config.dart';

/// Daily puzzle pool: one puzzle per calendar day, the same for everyone.
///
/// `assets/stages/daily.json` holds seven pools (Monday … Sunday) generated
/// and verified by `tool/gen_stages.py`; difficulty rises through the week.
/// The puzzle for a date is `pools[weekday][weeksSinceEpoch % poolLength]`,
/// so a puzzle only repeats after about a year.
class DailyCatalog {
  DailyCatalog(this._pools) : assert(_pools.length == 7);

  final List<List<Map<String, dynamic>>> _pools;

  /// A Monday; week numbers count from here.
  static final DateTime epoch = DateTime.utc(2026, 1, 5);

  static const weekdayNames = ['月', '火', '水', '木', '金', '土', '日'];
  static const levelNames = [
    'かんたん',
    'かんたん',
    'ふつう',
    'ふつう',
    'ちょいむず',
    'むずかしい',
    'むずかしい',
  ];

  factory DailyCatalog.fromJsonString(String source) {
    final root = jsonDecode(source) as Map<String, dynamic>;
    return DailyCatalog([
      for (final pool in root['weekdays'] as List)
        [for (final p in pool as List) (p as Map).cast<String, dynamic>()],
    ]);
  }

  int get totalPuzzles => _pools.fold(0, (a, p) => a + p.length);

  /// yyyymmdd for the local calendar day of [t].
  static int dayKey(DateTime t) => t.year * 10000 + t.month * 100 + t.day;

  static DateTime dateOf(int dayKey) =>
      DateTime(dayKey ~/ 10000, (dayKey ~/ 100) % 100, dayKey % 100);

  /// "11/16(月)"
  static String label(DateTime d) =>
      '${d.month}/${d.day}(${weekdayNames[d.weekday - 1]})';

  static String levelOf(DateTime d) => levelNames[d.weekday - 1];

  /// The puzzle for the local calendar day of [date].
  StageConfig forDate(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final weeks = (day.difference(epoch).inDays / 7).floor();
    final weekday = date.weekday - 1;
    final pool = _pools[weekday];
    final p = pool[weeks % pool.length];
    return StageConfig.fromJson({
      ...p,
      'id': dayKey(date),
      'name': 'デイリー ${label(date)}',
      'difficulty': weekday <= 1
          ? 'easy'
          : weekday <= 4
          ? 'normal'
          : 'hard',
    });
  }

  /// Every stored puzzle (for tests).
  Iterable<StageConfig> all() sync* {
    var id = 1;
    for (final pool in _pools) {
      for (final p in pool) {
        yield StageConfig.fromJson({...p, 'id': id++});
      }
    }
  }
}
