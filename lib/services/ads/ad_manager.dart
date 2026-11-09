import '../../data/progress_controller.dart';
import '../analytics/analytics.dart';
import 'ad_service.dart';
import 'interstitial_policy.dart';

/// Glue between game flow, ad frequency rules, purchases and analytics.
class AdManager {
  AdManager({
    required this.service,
    required this.progress,
    required this.analytics,
    this.policy = const InterstitialPolicy(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _lastInterstitial = _clock();
  }

  final AdService service;
  final ProgressController progress;
  final Analytics analytics;
  final InterstitialPolicy policy;
  final DateTime Function() _clock;
  late DateTime _lastInterstitial;

  bool get rewardedAvailable => service.rewardedReady;

  /// Shows a rewarded ad chosen by the user. True if the reward was earned.
  Future<bool> showRewarded(RewardPlacement placement) async {
    analytics.log('rewarded_start', {'placement': placement.name});
    final earned = await service.showRewarded(placement);
    analytics.log(earned ? 'rewarded_complete' : 'rewarded_fail', {
      'placement': placement.name,
    });
    return earned;
  }

  /// Call at the natural break after a stage clear (never during play).
  Future<void> onStageClearBreak() async {
    final d = progress.data;
    final ok = policy.shouldShow(
      adsRemoved: d.adsRemoved,
      highestCleared: d.highestCleared,
      clearsSinceLast: d.stats.clearsSinceInterstitial,
      everyNClears: d.settings.interstitialEvery,
      now: _clock(),
      lastShownOrAppStart: _lastInterstitial,
    );
    if (!ok) return;
    final shown = await service.showInterstitial();
    if (shown) {
      _lastInterstitial = _clock();
      await progress.onInterstitialShown();
      analytics.log('interstitial_shown', {'highest': d.highestCleared});
    }
  }
}
