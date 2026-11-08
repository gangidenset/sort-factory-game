/// Where a rewarded ad was offered (for analytics / per-placement tuning).
enum RewardPlacement { revive, doubleCoins, hint, dailyBonus }

/// Abstract ad backend. The game never depends on ads succeeding: every call
/// resolves (to `false` on failure) and never throws.
abstract class AdService {
  Future<void> initialize();

  bool get rewardedReady;

  /// Shows a rewarded ad. Resolves to true only if the user earned the reward.
  Future<bool> showRewarded(RewardPlacement placement);

  /// Shows an interstitial if one is loaded. Resolves when dismissed.
  Future<bool> showInterstitial();

  /// Whether a privacy options entry point must be offered (GDPR etc.).
  bool get privacyOptionsRequired;

  Future<void> showPrivacyOptions();

  void dispose();
}

/// Used in tests, unsupported platforms and when ads are not configured.
class NoAdService implements AdService {
  @override
  Future<void> initialize() async {}
  @override
  bool get rewardedReady => false;
  @override
  Future<bool> showRewarded(RewardPlacement placement) async => false;
  @override
  Future<bool> showInterstitial() async => false;
  @override
  bool get privacyOptionsRequired => false;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  void dispose() {}
}
