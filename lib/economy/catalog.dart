/// Static definitions of upgrades, cosmetics and missions.
///
/// Balance numbers live here (not in UI code) so they can later be moved to
/// remote config without code changes elsewhere.
library;

enum UpgradeEffect { shelfSlots, freeUndo, coinBonus }

class UpgradeDef {
  const UpgradeDef({
    required this.id,
    required this.name,
    required this.description,
    required this.effect,
    required this.costs,
  });

  final String id;
  final String name;
  final String description;
  final UpgradeEffect effect;

  /// Cost of each level; `costs.length` is the max level.
  final List<int> costs;

  int get maxLevel => costs.length;

  int? costForNext(int currentLevel) =>
      currentLevel >= maxLevel ? null : costs[currentLevel];
}

const upgradeDefs = [
  UpgradeDef(
    id: 'manual',
    name: '作業マニュアル',
    description: '無料の「1手戻す」 +1回／ステージ',
    effect: UpgradeEffect.freeUndo,
    costs: [200, 500],
  ),
  UpgradeDef(
    id: 'shelf',
    name: '棚の増設',
    description: '棚のスロット +1（全ステージ）',
    effect: UpgradeEffect.shelfSlots,
    costs: [600],
  ),
  UpgradeDef(
    id: 'center',
    name: '配送センター',
    description: 'ステージ報酬コイン +10%',
    effect: UpgradeEffect.coinBonus,
    costs: [150, 350, 700],
  ),
];

UpgradeDef? upgradeById(String id) {
  for (final u in upgradeDefs) {
    if (u.id == id) return u;
  }
  return null;
}

enum CosmeticType { factorySkin, boxDesign, decoration }

/// How a cosmetic is obtained.
sealed class Unlock {
  const Unlock();
}

class CoinUnlock extends Unlock {
  const CoinUnlock(this.cost);
  final int cost;
}

class StageUnlock extends Unlock {
  const StageUnlock(this.stageId);
  final int stageId;
}

class StarsUnlock extends Unlock {
  const StarsUnlock(this.stars);
  final int stars;
}

/// Granted by an in-app purchase entitlement.
class PurchaseUnlock extends Unlock {
  const PurchaseUnlock(this.entitlement);
  final String entitlement;
}

class CosmeticDef {
  const CosmeticDef({
    required this.id,
    required this.type,
    required this.name,
    required this.unlock,
    required this.colors,
  });

  final String id;
  final CosmeticType type;
  final String name;
  final Unlock unlock;

  /// ARGB colors used when rendering (skin: [background, belt, accent]).
  final List<int> colors;
}

const cosmeticDefs = [
  // Factory skins
  CosmeticDef(
    id: 'skin_default',
    type: CosmeticType.factorySkin,
    name: 'スタンダード',
    unlock: CoinUnlock(0),
    colors: [0xFFEFF3F8, 0xFF3A4556, 0xFF2F80ED],
  ),
  CosmeticDef(
    id: 'skin_mint',
    type: CosmeticType.factorySkin,
    name: 'ミント工場',
    unlock: CoinUnlock(300),
    colors: [0xFFE6F7F1, 0xFF2E5E55, 0xFF1ABC9C],
  ),
  CosmeticDef(
    id: 'skin_sunset',
    type: CosmeticType.factorySkin,
    name: 'サンセット',
    unlock: CoinUnlock(600),
    colors: [0xFFFFF1E6, 0xFF5B3A4A, 0xFFFF7A45],
  ),
  CosmeticDef(
    id: 'skin_night',
    type: CosmeticType.factorySkin,
    name: 'ナイトシフト',
    unlock: StarsUnlock(60),
    colors: [0xFF1E2433, 0xFF0E121B, 0xFF7C8CFF],
  ),
  CosmeticDef(
    id: 'skin_neon',
    type: CosmeticType.factorySkin,
    name: 'ネオン工場',
    unlock: PurchaseUnlock('skin_neon'),
    colors: [0xFF140F2D, 0xFF2A1F5C, 0xFFFF3DCB],
  ),
  // Box designs (collection)
  CosmeticDef(
    id: 'box_default',
    type: CosmeticType.boxDesign,
    name: 'ダンボール',
    unlock: CoinUnlock(0),
    colors: [0xFFFFFFFF],
  ),
  CosmeticDef(
    id: 'box_gift',
    type: CosmeticType.boxDesign,
    name: 'ギフトボックス',
    unlock: StageUnlock(10),
    colors: [0xFFFFFFFF],
  ),
  CosmeticDef(
    id: 'box_crate',
    type: CosmeticType.boxDesign,
    name: '木箱',
    unlock: StageUnlock(20),
    colors: [0xFFFFFFFF],
  ),
  CosmeticDef(
    id: 'box_round',
    type: CosmeticType.boxDesign,
    name: 'まるいカプセル',
    unlock: CoinUnlock(400),
    colors: [0xFFFFFFFF],
  ),
  CosmeticDef(
    id: 'box_gold',
    type: CosmeticType.boxDesign,
    name: 'ゴールド便',
    unlock: StageUnlock(30),
    colors: [0xFFFFFFFF],
  ),
  // Decorations
  CosmeticDef(
    id: 'deco_plant',
    type: CosmeticType.decoration,
    name: '観葉植物',
    unlock: CoinUnlock(100),
    colors: [0xFF27AE60],
  ),
  CosmeticDef(
    id: 'deco_flag',
    type: CosmeticType.decoration,
    name: '社旗',
    unlock: CoinUnlock(150),
    colors: [0xFFEB5757],
  ),
  CosmeticDef(
    id: 'deco_clock',
    type: CosmeticType.decoration,
    name: '大時計',
    unlock: CoinUnlock(250),
    colors: [0xFF2F80ED],
  ),
  CosmeticDef(
    id: 'deco_robot',
    type: CosmeticType.decoration,
    name: '仕分けロボ',
    unlock: CoinUnlock(400),
    colors: [0xFF9B51E0],
  ),
  CosmeticDef(
    id: 'deco_trophy',
    type: CosmeticType.decoration,
    name: '金のトロフィー',
    unlock: StarsUnlock(90),
    colors: [0xFFF2C94C],
  ),
];

CosmeticDef? cosmeticById(String id) {
  for (final c in cosmeticDefs) {
    if (c.id == id) return c;
  }
  return null;
}

enum MissionKind { clears, maxChain, perfectClears, totalScore, deliveries }

class MissionDef {
  const MissionDef(
    this.id,
    this.kind,
    this.goal,
    this.label, {
    this.reward = 40,
  });
  final String id;
  final MissionKind kind;
  final int goal;
  final String label;
  final int reward;
}

const missionPool = [
  MissionDef('clear_3', MissionKind.clears, 3, 'ステージを3回クリア'),
  MissionDef('clear_5', MissionKind.clears, 5, 'ステージを5回クリア', reward: 60),
  MissionDef('chain_2', MissionKind.maxChain, 2, '2連鎖出荷を達成'),
  MissionDef('chain_3', MissionKind.maxChain, 3, '3連鎖出荷を達成', reward: 60),
  MissionDef('perfect_2', MissionKind.perfectClears, 2, '★3クリアを2回'),
  MissionDef('score_5000', MissionKind.totalScore, 5000, '累計スコア5,000'),
  MissionDef('deliver_80', MissionKind.deliveries, 80, '荷物を80個出荷'),
];
