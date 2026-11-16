import 'package:flutter/foundation.dart';

import '../economy/catalog.dart';
import '../economy/economy.dart';
import '../game/logic/stage_config.dart';
import 'save_data.dart';
import 'save_repository.dart';

/// Summary of one finished play, produced by the game screen.
class StageResult {
  const StageResult({
    required this.stageId,
    required this.cleared,
    required this.score,
    required this.stars,
    required this.deliveries,
    required this.seconds,
  });

  final int stageId;
  final bool cleared;
  final int score;
  final int stars;
  final int deliveries;
  final double seconds;
}

class RewardSummary {
  const RewardSummary({
    required this.coins,
    required this.xp,
    required this.newBest,
    required this.firstClear,
    required this.levelBefore,
    required this.levelAfter,
    required this.newUnlocks,
  });

  final int coins;
  final int xp;
  final bool newBest;
  final bool firstClear;
  final int levelBefore;
  final int levelAfter;
  final List<CosmeticDef> newUnlocks;

  bool get leveledUp => levelAfter > levelBefore;
}

class MissionStatus {
  const MissionStatus(this.def, this.progress, this.claimed);
  final MissionDef def;
  final int progress;
  final bool claimed;
  bool get complete => progress >= def.goal;
}

/// App-wide player state. All mutations persist immediately.
class ProgressController extends ChangeNotifier {
  ProgressController(
    this._repo,
    this.data, {
    DateTime Function()? clock,
    this.unlockAllStages = false,
  }) : _clock = clock ?? DateTime.now;

  /// Playtest switch (web build with `?unlock=all`): every stage selectable.
  final bool unlockAllStages;

  final SaveRepository _repo;
  final DateTime Function() _clock;
  SaveData data;

  static Future<ProgressController> load(
    SaveRepository repo, {
    DateTime Function()? clock,
    bool unlockAllStages = false,
  }) async => ProgressController(
    repo,
    await repo.load(),
    clock: clock,
    unlockAllStages: unlockAllStages,
  );

  Future<void> _commit() async {
    notifyListeners();
    await _repo.save(data);
  }

  int get today => Economy.dayKey(_clock());
  int get level => Economy.levelForXp(data.xp);

  // ---------------------------------------------------------------------------
  // Session / retention bookkeeping

  /// Call once per app launch. Returns the number of days since install
  /// (0 on install day) for D1/D7 retention events.
  Future<int> onAppOpen() async {
    final s = data.stats;
    final d = today;
    if (s.installDay == 0) s.installDay = d;
    if (s.lastOpenDay != d) {
      s.daysPlayed++;
      s.lastOpenDay = d;
    }
    s.sessions++;
    await _commit();
    final install = _parseDay(s.installDay);
    final now = _parseDay(d);
    return now.difference(install).inDays;
  }

  static DateTime _parseDay(int d) =>
      DateTime.utc(d ~/ 10000, (d ~/ 100) % 100, d % 100);

  // ---------------------------------------------------------------------------
  // Stages

  bool isUnlocked(int stageId) =>
      unlockAllStages ||
      stageId <= 1 ||
      (data.stages[stageId - 1]?.cleared ?? false);

  StageRecord? recordOf(int stageId) => data.stages[stageId];

  SessionModifiers get modifiers {
    var hints = 0;
    for (final u in upgradeDefs) {
      if (u.effect == UpgradeEffect.freeHint) hints += data.upgradeLevel(u.id);
    }
    return SessionModifiers(extraHints: hints);
  }

  Future<void> recordAttempt(int stageId) async {
    data.record(stageId).attempts++;
    await _commit();
  }

  Future<RewardSummary> recordResult(StageResult r) async {
    final rec = data.record(r.stageId);
    final firstClear = r.cleared && !rec.cleared;
    final newBest = r.score > rec.bestScore;
    final levelBefore = level;
    final unlockedBefore = Set.of(data.unlocked);

    if (newBest) rec.bestScore = r.score;
    if (r.cleared) {
      rec.clears++;
      if (r.stars > rec.stars) rec.stars = r.stars;
      data.stats.clearsSinceInterstitial++;
    }
    final coins = Economy.stageCoins(
      cleared: r.cleared,
      stars: r.stars,
      firstClear: firstClear,
      centerLevel: data.upgradeLevel('center'),
    );
    final xp = Economy.stageXp(score: r.score, cleared: r.cleared);
    data.coins += coins;
    data.xp += xp;
    data.stats
      ..totalScore += r.score
      ..totalDeliveries += r.deliveries
      ..totalPlaySeconds += r.seconds.round();

    _trackMissions(r);
    _applyAutoUnlocks();
    await _commit();

    return RewardSummary(
      coins: coins,
      xp: xp,
      newBest: newBest,
      firstClear: firstClear,
      levelBefore: levelBefore,
      levelAfter: level,
      newUnlocks: [
        for (final id in data.unlocked.difference(unlockedBefore))
          ?cosmeticById(id),
      ],
    );
  }

  /// Rewarded-ad bonus coins.
  Future<void> addCoins(int amount) async {
    if (amount <= 0) return;
    data.coins += amount;
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Factory

  Future<bool> buyUpgrade(String id) async {
    final def = upgradeById(id);
    if (def == null) return false;
    final cost = def.costForNext(data.upgradeLevel(id));
    if (cost == null || data.coins < cost) return false;
    data.coins -= cost;
    data.upgrades[id] = data.upgradeLevel(id) + 1;
    await _commit();
    return true;
  }

  bool isOwned(String cosmeticId) => data.unlocked.contains(cosmeticId);

  Future<bool> buyCosmetic(String id) async {
    final def = cosmeticById(id);
    if (def == null || isOwned(id)) return false;
    final unlock = def.unlock;
    if (unlock is! CoinUnlock || data.coins < unlock.cost) return false;
    data.coins -= unlock.cost;
    data.unlocked.add(id);
    await _commit();
    return true;
  }

  Future<bool> equip(String id) async {
    final def = cosmeticById(id);
    if (def == null || !isOwned(id)) return false;
    switch (def.type) {
      case CosmeticType.factorySkin:
        data.equippedSkin = id;
      case CosmeticType.boxDesign:
        data.equippedBox = id;
      case CosmeticType.decoration:
        return true; // decorations are displayed once owned
    }
    await _commit();
    return true;
  }

  void _applyAutoUnlocks() {
    for (final c in cosmeticDefs) {
      if (data.unlocked.contains(c.id)) continue;
      final ok = switch (c.unlock) {
        StageUnlock(:final stageId) => data.stages[stageId]?.cleared ?? false,
        StarsUnlock(:final stars) => data.totalStars >= stars,
        PurchaseUnlock(:final entitlement) => data.entitlements.contains(
          entitlement,
        ),
        CoinUnlock() => false,
      };
      if (ok) data.unlocked.add(c.id);
    }
  }

  // ---------------------------------------------------------------------------
  // Purchases (called by the purchase service after store confirmation)

  Future<void> setEntitlements(
    Set<String> granted, {
    int bonusCoins = 0,
  }) async {
    final added = granted.difference(data.entitlements);
    if (added.isEmpty) return; // already owned (e.g. restore): no double grant
    data.entitlements.addAll(granted);
    // Entitlements that name a cosmetic unlock it directly.
    for (final id in granted) {
      if (cosmeticById(id) != null) data.unlocked.add(id);
    }
    data.coins += bonusCoins;
    _applyAutoUnlocks();
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Settings & tutorials

  Future<void> updateSettings(void Function(Settings s) change) async {
    change(data.settings);
    await _commit();
  }

  bool tutorialSeen(String key) => data.tutorialsSeen.contains(key);

  Future<void> markTutorialSeen(String key) async {
    if (data.tutorialsSeen.add(key)) await _commit();
  }

  Future<void> onInterstitialShown() async {
    data.stats.clearsSinceInterstitial = 0;
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Daily puzzle

  DailyPuzzleRecord? dailyRecord(int day) => data.dailyPuzzles[day];

  bool get todaysPuzzleSolved => data.dailyPuzzles.containsKey(today);

  /// Solved on the day itself (counts toward the streak).
  bool _onTime(int day) => data.dailyPuzzles[day]?.late == false;

  static DateTime _date(int day) =>
      DateTime(day ~/ 10000, (day ~/ 100) % 100, day % 100);

  /// Consecutive days solved on the day itself, ending today (or yesterday
  /// if today's is still open, so the streak isn't shown as lost mid-day).
  /// Puzzles solved later from the calendar never repair a streak.
  int get dailyStreak {
    var d = _date(today);
    if (!_onTime(Economy.dayKey(d))) {
      d = DateTime(d.year, d.month, d.day - 1);
    }
    var n = 0;
    while (_onTime(Economy.dayKey(d))) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }

  /// On-time solved flags for the last [days] days, oldest first.
  List<bool> recentDaily(int days) {
    final t = _date(today);
    return [
      for (var i = days - 1; i >= 0; i--)
        _onTime(Economy.dayKey(DateTime(t.year, t.month, t.day - i))),
    ];
  }

  /// Daily coins: 50, +10 per streak day up to +70.
  static int dailyCoins(int streak) => 50 + 10 * (streak - 1).clamp(0, 7);

  // ---- past puzzles (calendar) ----------------------------------------------

  /// How far back the calendar reaches.
  static const pastDays = 28;

  /// Coins to open a missed day (alternative to a rewarded ad).
  static const pastUnlockCost = 100;

  /// Reward for solving a past puzzle the first time.
  static const pastReward = 20;

  /// Whether [day] is a past day inside the calendar window.
  bool isPastInWindow(int day) {
    if (day >= today) return false;
    final t = _date(today);
    final first = Economy.dayKey(DateTime(t.year, t.month, t.day - pastDays));
    return day >= first;
  }

  /// A day can be played if it is today, already solved, or opened.
  bool canPlayDaily(int day) =>
      day == today ||
      data.dailyPuzzles.containsKey(day) ||
      (isPastInWindow(day) && data.unlockedPastDailies.contains(day));

  /// Opens a missed past day. With [payWithCoins] it costs [pastUnlockCost];
  /// otherwise the caller has already shown a rewarded ad.
  Future<bool> unlockPastDaily(int day, {required bool payWithCoins}) async {
    if (!isPastInWindow(day) || canPlayDaily(day)) return false;
    if (payWithCoins) {
      if (data.coins < pastUnlockCost) return false;
      data.coins -= pastUnlockCost;
    }
    data.unlockedPastDailies.add(day);
    // Forget unlocks that fell out of the window.
    data.unlockedPastDailies.removeWhere((d) => !isPastInWindow(d));
    await _commit();
    return true;
  }

  /// Records a solved daily puzzle for [day]. Rewards are paid only the
  /// first time each day; replays just keep the best time. Days before
  /// today count as late (small fixed reward, no streak).
  Future<(RewardSummary, int)> recordDaily({
    required int day,
    required StageResult result,
    required int hints,
  }) async {
    final levelBefore = level;
    final existing = data.dailyPuzzles[day];
    final late = day < today;
    var coins = 0;
    var xp = 0;
    final secs = result.seconds.round();
    if (existing == null) {
      data.dailyPuzzles[day] = DailyPuzzleRecord(
        seconds: secs,
        hints: hints,
        stars: result.stars,
        late: late,
      );
      // Keep the save small: drop records older than ~400 days.
      if (data.dailyPuzzles.length > 400) {
        final keys = data.dailyPuzzles.keys.toList()..sort();
        for (final k in keys.take(keys.length - 400)) {
          data.dailyPuzzles.remove(k);
        }
      }
      final base = late ? pastReward : dailyCoins(dailyStreak);
      coins = (base * (1 + 0.1 * data.upgradeLevel('center'))).round();
      xp = Economy.stageXp(score: result.score, cleared: true);
      data.coins += coins;
      data.xp += xp;
      data.stats
        ..totalScore += result.score
        ..totalDeliveries += result.deliveries
        ..totalPlaySeconds += secs
        ..clearsSinceInterstitial += 1;
      _trackMissions(result, dailyPuzzle: !late);
    } else {
      if (secs < existing.seconds) existing.seconds = secs;
      if (result.stars > existing.stars) existing.stars = result.stars;
    }
    final unlockedBefore = Set.of(data.unlocked);
    _applyAutoUnlocks();
    await _commit();
    return (
      RewardSummary(
        coins: coins,
        xp: xp,
        newBest: existing != null && secs <= existing.seconds,
        firstClear: existing == null,
        levelBefore: levelBefore,
        levelAfter: level,
        newUnlocks: [
          for (final id in data.unlocked.difference(unlockedBefore))
            ?cosmeticById(id),
        ],
      ),
      dailyStreak,
    );
  }

  // ---------------------------------------------------------------------------
  // Daily missions

  DailyState _daily() {
    final d = today;
    if (data.daily?.day != d) data.daily = DailyState(day: d);
    return data.daily!;
  }

  List<MissionStatus> missions() {
    final daily = _daily();
    return [
      for (final m in Economy.missionsForDay(daily.day))
        MissionStatus(
          m,
          daily.progress[m.id] ?? 0,
          daily.claimed.contains(m.id),
        ),
    ];
  }

  void _trackMissions(StageResult r, {bool dailyPuzzle = false}) {
    final daily = _daily();
    for (final m in Economy.missionsForDay(daily.day)) {
      final cur = daily.progress[m.id] ?? 0;
      final next = switch (m.kind) {
        MissionKind.clears => cur + (r.cleared ? 1 : 0),
        MissionKind.dailyPuzzle => cur + (dailyPuzzle ? 1 : 0),
        MissionKind.perfectClears => cur + (r.cleared && r.stars == 3 ? 1 : 0),
        MissionKind.totalScore => cur + r.score,
        MissionKind.deliveries => cur + r.deliveries,
      };
      daily.progress[m.id] = next;
    }
  }

  Future<bool> claimMission(String id) async {
    final status = missions().where((m) => m.def.id == id).firstOrNull;
    if (status == null || !status.complete || status.claimed) return false;
    data.daily!.claimed.add(id);
    data.coins += status.def.reward;
    await _commit();
    return true;
  }
}
