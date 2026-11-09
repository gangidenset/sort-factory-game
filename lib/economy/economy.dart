import 'dart:math' as math;

import '../game/logic/rng.dart';
import 'catalog.dart';

/// Reward / level formulas.
class Economy {
  const Economy._();

  static int stageCoins({
    required bool cleared,
    required int stars,
    required bool firstClear,
    required int centerLevel,
  }) {
    if (!cleared) return 5; // small consolation so failing still progresses
    final base = 20 + 10 * stars + (firstClear ? 30 : 0);
    return (base * (1 + 0.1 * centerLevel)).round();
  }

  static int stageXp({required int score, required bool cleared}) =>
      score ~/ 20 + (cleared ? 10 : 0);

  /// Cumulative XP required to reach [level] (level 1 = 0 XP).
  static int xpForLevel(int level) => 50 * (level - 1) * level;

  static int levelForXp(int xp) {
    var level = 1;
    while (xpForLevel(level + 1) <= xp) {
      level++;
    }
    return level;
  }

  /// Progress (0..1) within the current level.
  static double levelProgress(int xp) {
    final l = levelForXp(xp);
    final lo = xpForLevel(l), hi = xpForLevel(l + 1);
    return (xp - lo) / math.max(1, hi - lo);
  }

  /// Three missions for a local day (yyyymmdd), deterministic per day.
  static List<MissionDef> missionsForDay(int day) {
    final rng = SeededRng(day * 2654435761);
    final pool = List.of(missionPool);
    final picked = <MissionDef>[];
    while (picked.length < 3 && pool.isNotEmpty) {
      final m = pool.removeAt(rng.nextInt(pool.length));
      // At most one mission of each kind per day.
      if (picked.any((p) => p.kind == m.kind)) continue;
      picked.add(m);
    }
    return picked;
  }

  static int dayKey(DateTime t) => t.year * 10000 + t.month * 100 + t.day;
}
