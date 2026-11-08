import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_service.dart';

/// Google AdMob implementation with UMP consent handling.
///
/// Flow: request consent info -> show consent form if required -> initialize
/// the SDK only when `canRequestAds` -> preload one rewarded + one
/// interstitial, reloading after each show with exponential backoff.
class AdMobService implements AdService {
  RewardedAd? _rewarded;
  InterstitialAd? _interstitial;
  bool _initialized = false;
  bool _showing = false;
  int _rewardedRetry = 0;
  int _interstitialRetry = 0;
  bool _privacyRequired = false;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    if (!AdConfig.enabled) return;
    try {
      await _gatherConsent();
      if (!await ConsentInformation.instance.canRequestAds()) return;
      await MobileAds.instance.initialize();
      _initialized = true;
      _loadRewarded();
      _loadInterstitial();
    } catch (e) {
      debugPrint('Ads init failed: $e');
    }
  }

  Future<void> _gatherConsent() async {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) debugPrint('Consent form: ${error.message}');
        });
        final status = await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus();
        _privacyRequired = status == PrivacyOptionsRequirementStatus.required;
        if (!done.isCompleted) done.complete();
      },
      (error) {
        debugPrint('Consent info: ${error.message}');
        if (!done.isCompleted) done.complete();
      },
    );
    // Never block startup for long on consent.
    await done.future.timeout(const Duration(seconds: 8), onTimeout: () {});
  }

  Duration _backoff(int attempt) =>
      Duration(seconds: [5, 15, 30, 60, 120][attempt.clamp(0, 4)]);

  void _loadRewarded() {
    final id = AdConfig.rewardedUnitId;
    if (!_initialized || id == null || _disposed) return;
    RewardedAd.load(
      adUnitId: id,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          _rewardedRetry = 0;
        },
        onAdFailedToLoad: (err) {
          debugPrint('Rewarded load failed: ${err.message}');
          Timer(_backoff(_rewardedRetry++), _loadRewarded);
        },
      ),
    );
  }

  void _loadInterstitial() {
    final id = AdConfig.interstitialUnitId;
    if (!_initialized || id == null || _disposed) return;
    InterstitialAd.load(
      adUnitId: id,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _interstitialRetry = 0;
        },
        onAdFailedToLoad: (err) {
          debugPrint('Interstitial load failed: ${err.message}');
          Timer(_backoff(_interstitialRetry++), _loadInterstitial);
        },
      ),
    );
  }

  @override
  bool get rewardedReady => _rewarded != null && !_showing;

  @override
  Future<bool> showRewarded(RewardPlacement placement) async {
    final ad = _rewarded;
    if (ad == null || _showing) return false;
    _rewarded = null;
    _showing = true;
    var earned = false;
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      },
    );
    try {
      await ad.show(onUserEarnedReward: (_, _) => earned = true);
      await closed.future.timeout(const Duration(minutes: 3), onTimeout: () {});
    } catch (e) {
      debugPrint('Rewarded show failed: $e');
    } finally {
      _showing = false;
      _loadRewarded();
    }
    return earned;
  }

  @override
  Future<bool> showInterstitial() async {
    final ad = _interstitial;
    if (ad == null || _showing) return false;
    _interstitial = null;
    _showing = true;
    final closed = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete(false);
      },
    );
    try {
      await ad.show();
      return await closed.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => false,
      );
    } catch (e) {
      debugPrint('Interstitial show failed: $e');
      return false;
    } finally {
      _showing = false;
      _loadInterstitial();
    }
  }

  @override
  bool get privacyOptionsRequired => _privacyRequired;

  @override
  Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((_) {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
  }

  @override
  void dispose() {
    _disposed = true;
    _rewarded?.dispose();
    _interstitial?.dispose();
  }
}
