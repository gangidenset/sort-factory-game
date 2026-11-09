/// Decides whether an interstitial may be shown at a natural break (after a
/// stage clear). Pure logic so the frequency rules are unit-tested.
///
/// Defaults are the initial hypothesis from the design doc and are meant to be
/// tuned (later via remote config) based on retention vs. ad revenue.
class InterstitialPolicy {
  const InterstitialPolicy({
    this.graceStages = 5,
    this.minInterval = const Duration(seconds: 180),
  });

  /// No interstitials until this many stages have been cleared.
  final int graceStages;

  /// Minimum time between two interstitials, and between app start and the
  /// first one.
  final Duration minInterval;

  bool shouldShow({
    required bool adsRemoved,
    required int highestCleared,
    required int clearsSinceLast,
    required int everyNClears,
    required DateTime now,
    required DateTime lastShownOrAppStart,
  }) {
    if (adsRemoved) return false;
    if (highestCleared < graceStages) return false;
    if (clearsSinceLast < everyNClears) return false;
    if (now.difference(lastShownOrAppStart) < minInterval) return false;
    return true;
  }
}
