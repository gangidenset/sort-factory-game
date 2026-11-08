import 'package:flutter/material.dart';

import '../economy/catalog.dart';

/// Package colors. Chosen for high contrast on light backgrounds and to stay
/// distinguishable from each other; marks provide a non-color cue.
const packageColors = <Color>[
  Color(0xFFEB5757), // red
  Color(0xFF2F80ED), // blue
  Color(0xFF27AE60), // green
  Color(0xFFF2C94C), // yellow
  Color(0xFF9B51E0), // purple
  Color(0xFFF2994A), // orange
];

const packageColorNames = ['赤', '青', '緑', '黄', '紫', 'オレンジ'];
const markNames = ['', '★', '●', '▲'];

class AppColors {
  static const primary = Color(0xFF2F80ED);
  static const success = Color(0xFF27AE60);
  static const danger = Color(0xFFEB5757);
  static const coin = Color(0xFFF2B01E);
  static const ink = Color(0xFF1F2733);
}

/// Colors of a factory skin, derived from its cosmetic definition.
class FactorySkin {
  const FactorySkin({
    required this.background,
    required this.belt,
    required this.accent,
  });

  final Color background;
  final Color belt;
  final Color accent;

  bool get isDark => background.computeLuminance() < 0.3;

  Color get onBackground => isDark ? Colors.white : AppColors.ink;

  static FactorySkin fromId(String id) {
    final def = cosmeticById(id) ?? cosmeticById('skin_default')!;
    return FactorySkin(
      background: Color(def.colors[0]),
      belt: Color(def.colors[1]),
      accent: Color(def.colors[2]),
    );
  }
}
