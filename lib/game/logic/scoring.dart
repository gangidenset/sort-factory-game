import 'models.dart';

/// Score rules, kept in one place so balancing is easy.
class Scoring {
  const Scoring._();

  static const int baseCorrect = 100;
  static const int comboStep = 10;
  static const int comboCap = 20;
  static const int truckBonus = 150;
  static const int timedBonus = 50;
  static const int shiftingBonus = 30;

  /// Points for a correct delivery. [combo] is the combo count *including*
  /// this delivery (1 for the first in a row).
  static int correct(Package p, int combo) {
    final comboPart = comboStep * (combo - 1).clamp(0, comboCap);
    final special = switch (p.kind) {
      PackageKind.timed => timedBonus,
      PackageKind.shifting => shiftingBonus,
      PackageKind.normal => 0,
    };
    return baseCorrect + comboPart + special;
  }
}
