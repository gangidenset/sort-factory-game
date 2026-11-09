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
    required this.maxCombo,
    required this.timedDelivered,
    required this.seconds,
  });

  final int stageId;
  final bool cleared;
  final int score;
  final int stars;
  final int deliveries;
  final int maxCombo;
  final int timedDelivered;
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
    var belt = 0, buffer = 0;
    for (final u in upgradeDefs) {
      final lvl = data.upgradeLevel(u.id);
      switch (u.effect) {
        case UpgradeEffect.beltCapacity:
          belt += lvl;
        case UpgradeEffect.bufferSlots:
          buffer += lvl;
        case UpgradeEffect.coinBonus:
          break;
      }
    }
    return SessionModifiers(extraBelt: belt, extraBuffer: buffer);
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

  void _trackMissions(StageResult r) {
    final daily = _daily();
    for (final m in Economy.missionsForDay(daily.day)) {
      final cur = daily.progress[m.id] ?? 0;
      final next = switch (m.kind) {
        MissionKind.clears => cur + (r.cleared ? 1 : 0),
        MissionKind.maxCombo => r.maxCombo > cur ? r.maxCombo : cur,
        MissionKind.timedDeliveries => cur + r.timedDelivered,
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
