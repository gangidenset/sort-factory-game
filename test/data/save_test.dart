import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/data/progress_controller.dart';
import 'package:sort_factory/data/save_data.dart';
import 'package:sort_factory/data/save_repository.dart';
import 'package:sort_factory/economy/economy.dart';

StageResult result({
  int id = 1,
  bool cleared = true,
  int score = 1000,
  int stars = 2,
  int combo = 5,
  int deliveries = 10,
  int timed = 0,
}) => StageResult(
  stageId: id,
  cleared: cleared,
  score: score,
  stars: stars,
  deliveries: deliveries,
  maxCombo: combo,
  timedDelivered: timed,
  seconds: 30,
);

void main() {
  group('SaveRepository', () {
    test('round-trips all fields', () async {
      final store = MemoryStore();
      final repo = SaveRepository(store);
      final d = SaveData(coins: 123, xp: 45)
        ..record(3).stars = 2
        ..record(3).bestScore = 999
        ..record(3).clears = 1
        ..upgrades['conveyor'] = 2
        ..unlocked.add('skin_mint')
        ..equippedSkin = 'skin_mint'
        ..entitlements.add('remove_ads')
        ..tutorialsSeen.add('basic')
        ..settings.sound = false
        ..settings.interstitialEvery = 6
        ..daily = DailyState(day: 20261108, progress: {'clear_3': 2});
      await repo.save(d);

      final loaded = await SaveRepository(store).load();
      expect(loaded.coins, 123);
      expect(loaded.xp, 45);
      expect(loaded.stages[3]!.stars, 2);
      expect(loaded.stages[3]!.bestScore, 999);
      expect(loaded.highestCleared, 3);
      expect(loaded.upgradeLevel('conveyor'), 2);
      expect(loaded.unlocked, contains('skin_mint'));
      expect(loaded.equippedSkin, 'skin_mint');
      expect(loaded.adsRemoved, isTrue);
      expect(loaded.tutorialsSeen, {'basic'});
      expect(loaded.settings.sound, isFalse);
      expect(loaded.settings.interstitialEvery, 6);
      expect(loaded.daily!.progress['clear_3'], 2);
    });

    test('new player gets defaults', () async {
      final repo = SaveRepository(MemoryStore());
      final d = await repo.load();
      expect(repo.lastLoadSource, 'new');
      expect(d.coins, 0);
      expect(d.unlocked, containsAll(['skin_default', 'box_default']));
      expect(d.adsRemoved, isFalse);
    });

    test('corrupted primary falls back to backup', () async {
      final store = MemoryStore();
      final repo = SaveRepository(store);
      await repo.save(SaveData(coins: 77));
      store.data[SaveRepository.primaryKey] = '{"coins": 1, broken';
      final d = await repo.load();
      expect(repo.lastLoadSource, SaveRepository.backupKey);
      expect(d.coins, 77);
    });

    test('both corrupted gives a fresh save instead of crashing', () async {
      final store = MemoryStore()
        ..data[SaveRepository.primaryKey] = 'garbage'
        ..data[SaveRepository.backupKey] = '[1,2,3]';
      final d = await SaveRepository(store).load();
      expect(d.coins, 0);
    });

    test('bad values are sanitized', () async {
      final store = MemoryStore()
        ..data[SaveRepository.primaryKey] = jsonEncode({
          'schemaVersion': 1,
          'coins': -50,
          'stages': {
            '1': {'stars': 9, 'clears': 1},
            'x': {'stars': 1},
          },
          'settings': {'interstitialEvery': 0},
        });
      final d = await SaveRepository(store).load();
      expect(d.coins, 0);
      expect(d.stages[1]!.stars, 3);
      expect(d.stages.length, 1);
      expect(d.settings.interstitialEvery, 2);
    });

    test('data without version is treated as v1 and migrated', () {
      final migrated = SaveMigrations.migrate({'coins': 5});
      expect(SaveData.fromJson(migrated).coins, 5);
    });

    test('encode includes schema version', () {
      final j = jsonDecode(SaveData().encode()) as Map;
      expect(j['schemaVersion'], SaveData.currentVersion);
    });
  });

  group('ProgressController', () {
    late MemoryStore store;
    late ProgressController pc;
    var now = DateTime(2026, 11, 8, 10);

    setUp(() async {
      store = MemoryStore();
      now = DateTime(2026, 11, 8, 10);
      pc = await ProgressController.load(
        SaveRepository(store),
        clock: () => now,
      );
    });

    test('stage unlock order', () async {
      expect(pc.isUnlocked(1), isTrue);
      expect(pc.isUnlocked(2), isFalse);
      await pc.recordResult(result(id: 1));
      expect(pc.isUnlocked(2), isTrue);
      expect(pc.isUnlocked(3), isFalse);
    });

    test('failed play does not unlock next stage', () async {
      await pc.recordResult(result(id: 1, cleared: false, stars: 0));
      expect(pc.isUnlocked(2), isFalse);
    });

    test('first clear rewards more and best score/stars are kept', () async {
      final first = await pc.recordResult(result(score: 1000, stars: 2));
      expect(first.firstClear, isTrue);
      expect(first.newBest, isTrue);
      final second = await pc.recordResult(result(score: 500, stars: 1));
      expect(second.firstClear, isFalse);
      expect(second.newBest, isFalse);
      expect(second.coins, lessThan(first.coins));
      expect(pc.recordOf(1)!.bestScore, 1000);
      expect(pc.recordOf(1)!.stars, 2);
      expect(pc.recordOf(1)!.clears, 2);
    });

    test('progress persists across reload', () async {
      await pc.recordResult(result());
      final reloaded = await ProgressController.load(SaveRepository(store));
      expect(reloaded.data.coins, pc.data.coins);
      expect(reloaded.isUnlocked(2), isTrue);
    });

    test('upgrades cost coins and apply modifiers', () async {
      expect(await pc.buyUpgrade('conveyor'), isFalse);
      await pc.addCoins(1000);
      expect(await pc.buyUpgrade('conveyor'), isTrue);
      expect(pc.data.coins, 800);
      expect(pc.modifiers.extraBelt, 1);
      expect(await pc.buyUpgrade('conveyor'), isTrue);
      expect(await pc.buyUpgrade('conveyor'), isFalse); // max level
      expect(pc.data.coins, 300);
    });

    test('center upgrade boosts coins', () {
      final base = Economy.stageCoins(
        cleared: true,
        stars: 3,
        firstClear: false,
        centerLevel: 0,
      );
      final boosted = Economy.stageCoins(
        cleared: true,
        stars: 3,
        firstClear: false,
        centerLevel: 3,
      );
      expect(boosted, greaterThan(base));
    });

    test('cosmetics: buy with coins, equip only when owned', () async {
      expect(await pc.equip('skin_mint'), isFalse);
      await pc.addCoins(300);
      expect(await pc.buyCosmetic('skin_mint'), isTrue);
      expect(await pc.equip('skin_mint'), isTrue);
      expect(pc.data.equippedSkin, 'skin_mint');
      // purchase-only items cannot be bought with coins
      await pc.addCoins(99999);
      expect(await pc.buyCosmetic('skin_neon'), isFalse);
    });

    test('stage-milestone cosmetics unlock automatically', () async {
      final r = await pc.recordResult(result(id: 10));
      expect(r.newUnlocks.map((c) => c.id), contains('box_gift'));
    });

    test('entitlements unlock purchase cosmetics', () async {
      await pc.setEntitlements({'skin_neon', 'remove_ads'});
      expect(pc.isOwned('skin_neon'), isTrue);
      expect(pc.data.adsRemoved, isTrue);
    });

    test(
      'daily missions track progress, claim once and reset next day',
      () async {
        final missions = pc.missions();
        expect(missions.length, 3);
        for (var i = 0; i < 6; i++) {
          await pc.recordResult(
            result(score: 3000, combo: 16, deliveries: 15, timed: 2),
          );
        }
        final done = pc.missions().where((m) => m.complete).toList();
        expect(done, isNotEmpty);
        final coins = pc.data.coins;
        expect(await pc.claimMission(done.first.def.id), isTrue);
        expect(pc.data.coins, coins + done.first.def.reward);
        expect(await pc.claimMission(done.first.def.id), isFalse);

        now = now.add(const Duration(days: 1));
        expect(
          pc.missions().every((m) => m.progress == 0 && !m.claimed),
          isTrue,
        );
      },
    );

    test('app open tracks days since install', () async {
      expect(await pc.onAppOpen(), 0);
      now = now.add(const Duration(days: 1));
      expect(await pc.onAppOpen(), 1);
      now = now.add(const Duration(days: 6));
      expect(await pc.onAppOpen(), 7);
      expect(pc.data.stats.daysPlayed, 3);
      expect(pc.data.stats.sessions, 3);
    });
  });

  group('Economy', () {
    test('level curve', () {
      expect(Economy.levelForXp(0), 1);
      expect(Economy.levelForXp(Economy.xpForLevel(2)), 2);
      expect(Economy.levelForXp(Economy.xpForLevel(5) - 1), 4);
      expect(Economy.levelProgress(0), 0);
    });

    test('missions are deterministic per day and unique by kind', () {
      final a = Economy.missionsForDay(20261108);
      final b = Economy.missionsForDay(20261108);
      expect(a.map((m) => m.id), b.map((m) => m.id));
      expect(a.map((m) => m.kind).toSet().length, 3);
    });
  });
}
