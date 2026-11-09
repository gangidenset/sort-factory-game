import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Ad unit IDs are injected at build time, never hard-coded:
///
/// ```
/// flutter build appbundle --release \
///   --dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-xxx/yyy \
///   --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-xxx/zzz
/// ```
///
/// Debug/profile builds (or `--dart-define=USE_TEST_ADS=true`) use Google's
/// public sample IDs, which never generate revenue and are safe to click.
/// A release build without IDs simply disables ads (the game still works).
class AdConfig {
  const AdConfig._();

  static const bool useTestAds = bool.fromEnvironment(
    'USE_TEST_ADS',
    defaultValue: !kReleaseMode,
  );

  static const _rewardedAndroid = String.fromEnvironment(
    'ADMOB_REWARDED_ANDROID',
  );
  static const _interstitialAndroid = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ANDROID',
  );
  static const _rewardedIos = String.fromEnvironment('ADMOB_REWARDED_IOS');
  static const _interstitialIos = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_IOS',
  );

  // Google's official sample ad units:
  // https://developers.google.com/admob/android/test-ads
  // https://developers.google.com/admob/ios/test-ads
  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';
  static const _testInterstitialIos = 'ca-app-pub-3940256099942544/4411468910';

  static bool get _isIos => !kIsWeb && Platform.isIOS;
  static bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static String? get rewardedUnitId {
    if (!_isMobile) return null;
    if (useTestAds) return _isIos ? _testRewardedIos : _testRewardedAndroid;
    final id = _isIos ? _rewardedIos : _rewardedAndroid;
    return id.isEmpty ? null : id;
  }

  static String? get interstitialUnitId {
    if (!_isMobile) return null;
    if (useTestAds) {
      return _isIos ? _testInterstitialIos : _testInterstitialAndroid;
    }
    final id = _isIos ? _interstitialIos : _interstitialAndroid;
    return id.isEmpty ? null : id;
  }

  static bool get enabled =>
      rewardedUnitId != null || interstitialUnitId != null;
}
