import 'dart:convert';

/// Per-stage progress.
class StageRecord {
  StageRecord({
    this.stars = 0,
    this.bestScore = 0,
    this.clears = 0,
    this.attempts = 0,
  });

  int stars;
  int bestScore;
  int clears;
  int attempts;

  bool get cleared => clears > 0;

  Map<String, dynamic> toJson() => {
    'stars': stars,
    'best': bestScore,
    'clears': clears,
    'attempts': attempts,
  };

  factory StageRecord.fromJson(Map<String, dynamic> j) => StageRecord(
    stars: _int(j['stars']).clamp(0, 3),
    bestScore: _int(j['best']),
    clears: _int(j['clears']),
    attempts: _int(j['attempts']),
  );
}

class Settings {
  Settings({
    this.sound = true,
    this.haptics = true,
    this.interstitialEvery = 4,
    this.showHints = true,
  });

  bool sound;
  bool haptics;

  /// Clears between interstitial ads (user-adjustable: 4 / 6 / 8).
  int interstitialEvery;
  bool showHints;

  Map<String, dynamic> toJson() => {
    'sound': sound,
    'haptics': haptics,
    'interstitialEvery': interstitialEvery,
    'showHints': showHints,
  };

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
    sound: j['sound'] as bool? ?? true,
    haptics: j['haptics'] as bool? ?? true,
    interstitialEvery: _int(j['interstitialEvery'], 4).clamp(2, 20),
    showHints: j['showHints'] as bool? ?? true,
  );
}

/// Daily mission progress for one day.
class DailyState {
  DailyState({
    required this.day,
    Map<String, int>? progress,
    Set<String>? claimed,
  }) : progress = progress ?? {},
       claimed = claimed ?? {};

  /// yyyymmdd of the local day this state belongs to.
  final int day;
  final Map<String, int> progress;
  final Set<String> claimed;

  Map<String, dynamic> toJson() => {
    'day': day,
    'progress': progress,
    'claimed': claimed.toList(),
  };

  factory DailyState.fromJson(Map<String, dynamic> j) => DailyState(
    day: _int(j['day']),
    progress:
        (j['progress'] as Map?)?.map(
          (k, v) => MapEntry(k as String, _int(v)),
        ) ??
        {},
    claimed: (j['claimed'] as List?)?.cast<String>().toSet() ?? {},
  );
}

/// Local, anonymous play statistics (used for retention KPIs).
class PlayStats {
  PlayStats({
    this.installDay = 0,
    this.lastOpenDay = 0,
    this.daysPlayed = 0,
    this.sessions = 0,
    this.totalPlaySeconds = 0,
    this.totalScore = 0,
    this.totalDeliveries = 0,
    this.clearsSinceInterstitial = 0,
  });

  int installDay;
  int lastOpenDay;
  int daysPlayed;
  int sessions;
  int totalPlaySeconds;
  int totalScore;
  int totalDeliveries;
  int clearsSinceInterstitial;

  Map<String, dynamic> toJson() => {
    'installDay': installDay,
    'lastOpenDay': lastOpenDay,
    'daysPlayed': daysPlayed,
    'sessions': sessions,
    'playSeconds': totalPlaySeconds,
    'totalScore': totalScore,
    'deliveries': totalDeliveries,
    'clearsSinceInterstitial': clearsSinceInterstitial,
  };

  factory PlayStats.fromJson(Map<String, dynamic> j) => PlayStats(
    installDay: _int(j['installDay']),
    lastOpenDay: _int(j['lastOpenDay']),
    daysPlayed: _int(j['daysPlayed']),
    sessions: _int(j['sessions']),
    totalPlaySeconds: _int(j['playSeconds']),
    totalScore: _int(j['totalScore']),
    totalDeliveries: _int(j['deliveries']),
    clearsSinceInterstitial: _int(j['clearsSinceInterstitial']),
  );
}

/// Root of everything persisted locally.
///
/// Bump [currentVersion] and add a step in `SaveMigrations` whenever the
/// format changes in a non-additive way.
class SaveData {
  SaveData({
    this.coins = 0,
    this.xp = 0,
    Map<int, StageRecord>? stages,
    Map<String, int>? upgrades,
    Set<String>? unlocked,
    this.equippedSkin = 'skin_default',
    this.equippedBox = 'box_default',
    Settings? settings,
    Set<String>? entitlements,
    Set<String>? tutorialsSeen,
    this.daily,
    PlayStats? stats,
  }) : stages = stages ?? {},
       upgrades = upgrades ?? {},
       unlocked = unlocked ?? {'skin_default', 'box_default'},
       settings = settings ?? Settings(),
       entitlements = entitlements ?? {},
       tutorialsSeen = tutorialsSeen ?? {},
       stats = stats ?? PlayStats();

  static const int currentVersion = 1;

  int coins;
  int xp;
  final Map<int, StageRecord> stages;
  final Map<String, int> upgrades;

  /// Unlocked cosmetic item ids (skins, box designs, decorations).
  final Set<String> unlocked;
  String equippedSkin;
  String equippedBox;
  final Settings settings;

  /// Product-backed entitlements, e.g. `remove_ads`. Mirrors store purchases;
  /// re-synced on restore.
  final Set<String> entitlements;
  final Set<String> tutorialsSeen;
  DailyState? daily;
  final PlayStats stats;

  StageRecord record(int stageId) =>
      stages.putIfAbsent(stageId, StageRecord.new);

  int upgradeLevel(String id) => upgrades[id] ?? 0;

  /// Highest stage id that is cleared (0 if none).
  int get highestCleared {
    var best = 0;
    stages.forEach((id, r) {
      if (r.cleared && id > best) best = id;
    });
    return best;
  }

  int get totalStars => stages.values.fold(0, (a, r) => a + r.stars);

  bool get adsRemoved => entitlements.contains('remove_ads');

  Map<String, dynamic> toJson() => {
    'schemaVersion': currentVersion,
    'coins': coins,
    'xp': xp,
    'stages': stages.map((k, v) => MapEntry('$k', v.toJson())),
    'upgrades': upgrades,
    'unlocked': unlocked.toList()..sort(),
    'equippedSkin': equippedSkin,
    'equippedBox': equippedBox,
    'settings': settings.toJson(),
    'entitlements': entitlements.toList()..sort(),
    'tutorialsSeen': tutorialsSeen.toList()..sort(),
    'daily': daily?.toJson(),
    'stats': stats.toJson(),
  };

  String encode() => jsonEncode(toJson());

  /// Parses an already-migrated JSON map. Unknown keys are ignored and missing
  /// keys fall back to defaults, so additive changes need no migration.
  factory SaveData.fromJson(Map<String, dynamic> j) {
    final stages = <int, StageRecord>{};
    (j['stages'] as Map?)?.forEach((k, v) {
      final id = int.tryParse('$k');
      if (id != null && v is Map) {
        stages[id] = StageRecord.fromJson(v.cast<String, dynamic>());
      }
    });
    return SaveData(
      coins: _int(j['coins']).clamp(0, 1 << 31),
      xp: _int(j['xp']),
      stages: stages,
      upgrades: (j['upgrades'] as Map?)?.map(
        (k, v) => MapEntry(k as String, _int(v)),
      ),
      unlocked: {
        'skin_default',
        'box_default',
        ...?(j['unlocked'] as List?)?.cast<String>(),
      },
      equippedSkin: j['equippedSkin'] as String? ?? 'skin_default',
      equippedBox: j['equippedBox'] as String? ?? 'box_default',
      settings: j['settings'] is Map
          ? Settings.fromJson((j['settings'] as Map).cast<String, dynamic>())
          : null,
      entitlements: (j['entitlements'] as List?)?.cast<String>().toSet(),
      tutorialsSeen: (j['tutorialsSeen'] as List?)?.cast<String>().toSet(),
      daily: j['daily'] is Map
          ? DailyState.fromJson((j['daily'] as Map).cast<String, dynamic>())
          : null,
      stats: j['stats'] is Map
          ? PlayStats.fromJson((j['stats'] as Map).cast<String, dynamic>())
          : null,
    );
  }
}

int _int(Object? v, [int def = 0]) => v is num ? v.toInt() : def;
