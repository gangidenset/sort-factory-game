/// Platform-independent deterministic PRNG (mulberry32).
///
/// `dart:math` Random is not guaranteed to produce identical sequences across
/// platforms (VM / web), so stages use this to stay reproducible.
class SeededRng {
  SeededRng(int seed) : _state = seed & 0xFFFFFFFF;

  int _state;

  /// Returns a value in [0, 2^32).
  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _state;
    t = _imul(t ^ (t >> 15), t | 1);
    t ^= (t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF;
    return (t ^ (t >> 14)) & 0xFFFFFFFF;
  }

  /// Returns a double in [0, 1).
  double nextDouble() => nextUint32() / 4294967296.0;

  /// Returns an int in [0, max).
  int nextInt(int max) {
    assert(max > 0);
    return (nextDouble() * max).floor();
  }

  bool chance(double p) => nextDouble() < p;

  T pick<T>(List<T> items) => items[nextInt(items.length)];

  static int _imul(int a, int b) => (a * b) & 0xFFFFFFFF;
}
