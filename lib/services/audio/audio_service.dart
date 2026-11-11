import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum Sfx { tap, correct, wrong, store, truck, combo, clear, fail }

/// Short sound effects + haptics. All failures are swallowed: missing audio
/// must never break gameplay.
class AudioService {
  AudioService({required this.soundEnabled, required this.hapticsEnabled});

  bool Function() soundEnabled;
  bool Function() hapticsEnabled;
  bool _ready = false;

  static String _file(Sfx s) => '${s.name}.wav';

  Future<void> preload() async {
    try {
      FlameAudio.audioCache.prefix = 'assets/audio/';
      await FlameAudio.audioCache.loadAll([
        ...Sfx.values.map(_file),
        for (var i = 2; i <= 6; i++) 'chain$i.wav',
      ]);
      _ready = true;
    } catch (e) {
      debugPrint('Audio preload failed: $e');
    }
  }

  void play(Sfx s) {
    if (!_ready || !soundEnabled()) return;
    try {
      FlameAudio.play(_file(s), volume: s == Sfx.tap ? 0.5 : 0.8);
    } catch (_) {}
  }

  /// Extra rising "ding" for chain level >= 2 (pitch climbs with the chain).
  void chainPitch(int chain) {
    if (chain < 2 || !_ready || !soundEnabled()) return;
    try {
      FlameAudio.play('chain${chain.clamp(2, 6)}.wav', volume: 0.8);
    } catch (_) {}
  }

  void haptic(Sfx s) {
    if (!hapticsEnabled()) return;
    switch (s) {
      case Sfx.wrong || Sfx.fail:
        HapticFeedback.heavyImpact();
      case Sfx.truck || Sfx.clear || Sfx.combo:
        HapticFeedback.mediumImpact();
      default:
        HapticFeedback.selectionClick();
    }
  }

  void feedback(Sfx s) {
    play(s);
    haptic(s);
  }
}
