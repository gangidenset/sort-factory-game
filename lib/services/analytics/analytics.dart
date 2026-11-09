import 'package:flutter/foundation.dart';

/// Analytics abstraction. Swap [DebugAnalytics] for a Firebase-backed
/// implementation later without touching game code.
///
/// Privacy: events carry only gameplay data (stage id, score, placement...).
/// Never log names, emails, device identifiers or free text.
abstract class Analytics {
  void log(String event, [Map<String, Object> params = const {}]);
}

class DebugAnalytics implements Analytics {
  /// Recent events, viewable from the debug panel in settings.
  final List<String> recent = [];

  @override
  void log(String event, [Map<String, Object> params = const {}]) {
    final line = '$event $params';
    recent.add(line);
    if (recent.length > 100) recent.removeAt(0);
    if (kDebugMode) debugPrint('[analytics] $line');
  }
}

class MultiAnalytics implements Analytics {
  MultiAnalytics(this.sinks);
  final List<Analytics> sinks;
  @override
  void log(String event, [Map<String, Object> params = const {}]) {
    for (final s in sinks) {
      try {
        s.log(event, params);
      } catch (_) {
        // Analytics must never break the game.
      }
    }
  }
}
