import 'package:flutter_test/flutter_test.dart';
import 'package:sort_factory/data/progress_controller.dart';
import 'package:sort_factory/data/save_repository.dart';
import 'package:sort_factory/services/ads/ad_manager.dart';
import 'package:sort_factory/services/ads/ad_service.dart';
import 'package:sort_factory/services/ads/interstitial_policy.dart';
import 'package:sort_factory/services/analytics/analytics.dart';
import 'package:sort_factory/services/iap/products.dart';
import 'package:sort_factory/services/iap/purchase_service.dart';

class FakeAds implements AdService {
  int interstitials = 0;
  bool reward = true;
  @override
  Future<void> initialize() async {}
  @override
  bool get rewardedReady => true;
  @override
  Future<bool> showRewarded(RewardPlacement placement) async => reward;
  @override
  Future<bool> showInterstitial() async {
    interstitials++;
    return true;
  }

  @override
  bool get privacyOptionsRequired => false;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  void dispose() {}
}

StageResult clear(int id) => StageResult(
  stageId: id,
  cleared: true,
  score: 100,
  stars: 1,
  deliveries: 5,
  maxCombo: 2,
  timedDelivered: 0,
  seconds: 20,
);

void main() {
  group('InterstitialPolicy', () {
    const policy = InterstitialPolicy();
    final t0 = DateTime(2026, 1, 1, 12);

    bool show({
      bool removed = false,
      int highest = 10,
      int since = 4,
      int every = 4,
      Duration elapsed = const Duration(minutes: 5),
    }) => policy.shouldShow(
      adsRemoved: removed,
      highestCleared: highest,
      clearsSinceLast: since,
      everyNClears: every,
      now: t0.add(elapsed),
      lastShownOrAppStart: t0,
    );

    test('shows when all conditions are met', () => expect(show(), isTrue));
    test('never after ads removed', () => expect(show(removed: true), isFalse));
    test(
      'not during the first stages',
      () => expect(show(highest: 4), isFalse),
    );
    test('only every N clears', () => expect(show(since: 3), isFalse));
    test('respects the minimum interval of 180s', () {
      expect(show(elapsed: const Duration(seconds: 179)), isFalse);
      expect(show(elapsed: const Duration(seconds: 180)), isTrue);
    });
    test('frequency setting is honored', () {
      expect(show(since: 5, every: 6), isFalse);
      expect(show(since: 6, every: 6), isTrue);
    });
  });

  group('AdManager', () {
    test('counts clears, shows interstitial and resets the counter', () async {
      var now = DateTime(2026, 1, 1, 12);
      final progress = await ProgressController.load(
        SaveRepository(MemoryStore()),
      );
      final ads = FakeAds();
      final mgr = AdManager(
        service: ads,
        progress: progress,
        analytics: DebugAnalytics(),
        clock: () => now,
      );
      for (var i = 1; i <= 8; i++) {
        await progress.recordResult(clear(i));
        now = now.add(const Duration(minutes: 1));
        await mgr.onStageClearBreak();
      }
      // Grace period of 5 stages and 180s interval → only one ad so far.
      expect(ads.interstitials, 1);
      expect(progress.data.stats.clearsSinceInterstitial, lessThan(4));
    });

    test('no interstitials after remove_ads purchase', () async {
      final progress = await ProgressController.load(
        SaveRepository(MemoryStore()),
      );
      await grantProduct(progress, Products.removeAds);
      final ads = FakeAds();
      var now = DateTime(2026, 1, 1);
      final mgr = AdManager(
        service: ads,
        progress: progress,
        analytics: DebugAnalytics(),
        clock: () => now,
      );
      for (var i = 1; i <= 20; i++) {
        await progress.recordResult(clear(i));
        now = now.add(const Duration(minutes: 5));
        await mgr.onStageClearBreak();
      }
      expect(ads.interstitials, 0);
    });

    test('NoAdService never grants rewards', () async {
      expect(await NoAdService().showRewarded(RewardPlacement.revive), isFalse);
    });
  });

  group('Purchases', () {
    test('granting is idempotent (restore does not duplicate coins)', () async {
      final progress = await ProgressController.load(
        SaveRepository(MemoryStore()),
      );
      await grantProduct(progress, Products.starterPack);
      final coins = progress.data.coins;
      expect(coins, Products.starterPack.bonusCoins);
      await grantProduct(progress, Products.starterPack);
      expect(progress.data.coins, coins);
      expect(progress.isOwned('skin_mint'), isTrue);
    });

    test('premium pack removes ads and unlocks neon skin', () async {
      final progress = await ProgressController.load(
        SaveRepository(MemoryStore()),
      );
      await grantProduct(progress, Products.premiumPack);
      expect(progress.data.adsRemoved, isTrue);
      expect(progress.isOwned('skin_neon'), isTrue);
    });

    test('product ids are unique', () {
      final ids = Products.enabled.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });
}
