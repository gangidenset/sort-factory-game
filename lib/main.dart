import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/services.dart';
import 'data/progress_controller.dart';
import 'data/save_repository.dart';
import 'game/logic/stage_repository.dart';
import 'services/ads/ad_manager.dart';
import 'services/ads/ad_service.dart';
import 'services/ads/admob_service.dart';
import 'services/analytics/analytics.dart';
import 'services/audio/audio_service.dart';
import 'services/iap/purchase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final analytics = DebugAnalytics();
  final progress = await ProgressController.load(
    SaveRepository(SharedPrefsStore(SharedPreferencesAsync())),
    // Playtest only: https://.../?unlock=all opens every stage on the web build.
    unlockAllStages: kIsWeb && Uri.base.queryParameters['unlock'] == 'all',
  );
  final stages = StageCatalog.fromJsonString(
    await rootBundle.loadString('assets/stages/stages.json'),
  );

  final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  final AdService adService = isMobile ? AdMobService() : NoAdService();
  final PurchaseService purchases = isMobile
      ? StorePurchaseService(progress, analytics)
      : UnavailablePurchaseService();
  final audio = AudioService(
    soundEnabled: () => progress.data.settings.sound,
    hapticsEnabled: () => progress.data.settings.haptics,
  );

  final services = AppServices(
    progress: progress,
    stages: stages,
    ads: AdManager(
      service: adService,
      progress: progress,
      analytics: analytics,
    ),
    purchases: purchases,
    analytics: analytics,
    audio: audio,
  );

  runApp(SortFactoryApp(services: services));

  // Non-critical startup work runs after the first frame so the title shows
  // immediately; every step tolerates failure (offline etc.).
  final daysSinceInstall = await progress.onAppOpen();
  analytics.log('app_open', {
    'days_since_install': daysSinceInstall,
    'highest_stage': progress.data.highestCleared,
  });
  await audio.preload();
  await purchases.initialize();
  await adService.initialize();
}
