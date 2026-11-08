import 'package:flutter/widgets.dart';

import '../data/progress_controller.dart';
import '../game/logic/stage_repository.dart';
import '../services/ads/ad_manager.dart';
import '../services/analytics/analytics.dart';
import '../services/audio/audio_service.dart';
import '../services/iap/purchase_service.dart';

/// Dependency container shared across screens.
class AppServices {
  AppServices({
    required this.progress,
    required this.stages,
    required this.ads,
    required this.purchases,
    required this.analytics,
    required this.audio,
  });

  final ProgressController progress;
  final StageCatalog stages;
  final AdManager ads;
  final PurchaseService purchases;
  final Analytics analytics;
  final AudioService audio;
}

class ServicesScope extends InheritedWidget {
  const ServicesScope({
    super.key,
    required this.services,
    required super.child,
  });

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServicesScope>()!.services;

  @override
  bool updateShouldNotify(ServicesScope oldWidget) =>
      services != oldWidget.services;
}

extension ServicesX on BuildContext {
  AppServices get services => ServicesScope.of(this);
}
