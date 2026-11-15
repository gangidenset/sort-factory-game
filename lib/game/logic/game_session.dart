import 'models.dart';
import 'stage_config.dart';

/// State of one play of a deduction puzzle.
///
/// The player marks cells as box / cross. There is no fail state and no
/// timer: the stage is cleared the moment the boxes match the (unique)
/// solution. Rule violations are reported so the UI can show them, and
/// "auto" crosses are derived for bookkeeping the player should not have to
/// do by hand.
class GameSession {
  GameSession(this.config, {SessionModifiers modifiers = SessionModifiers.none})
    : freeHints = 1 + modifiers.extraHints,
      _truckAt = {for (final t in config.trucks) t.cell: t},
      _solution = config.solution.toSet();

  final StageConfig config;
  final Map<Cell, Truck> _truckAt;
  final Set<Cell> _solution;
  final Map<Cell, Mark> _marks = {};
  final List<Map<Cell, Mark>> _history = [];

  SessionStatus status = SessionStatus.ready;

  /// Hints available without watching an ad.
  int freeHints;
  int hintsUsed = 0;
  int moves = 0;

  int get size => config.size;
  bool get isCleared => status == SessionStatus.cleared;

  // ---------------------------------------------------------------------------
  // Queries

  bool inside(Cell c) => c.$1 >= 0 && c.$1 < size && c.$2 >= 0 && c.$2 < size;

  Truck? truckAt(Cell c) => _truckAt[c];
  bool isTruck(Cell c) => _truckAt.containsKey(c);
  Mark markAt(Cell c) => _marks[c] ?? Mark.none;
  bool isBox(Cell c) => _marks[c] == Mark.box;

  Iterable<Cell> get boxes =>
      _marks.entries.where((e) => e.value == Mark.box).map((e) => e.key);

  int get boxesPlaced => boxes.length;

  int rowCount(int r) => boxes.where((b) => b.$1 == r).length;
  int colCount(int c) => boxes.where((b) => b.$2 == c).length;

  LineState rowState(int r) => _state(rowCount(r), config.rowClues[r]);
  LineState colState(int c) => _state(colCount(c), config.colClues[c]);

  static LineState _state(int have, int want) => have == want
      ? LineState.done
      : (have > want ? LineState.over : LineState.open);

  bool nextToTruck(Cell c) =>
      orthogonal.any((d) => isTruck((c.$1 + d.$1, c.$2 + d.$2)));

  bool touchesBox(Cell c) =>
      around8.any((d) => isBox((c.$1 + d.$1, c.$2 + d.$2)));

  /// Why an unmarked cell can be ruled out by plain bookkeeping, or null.
  /// Shown as a faint cross so players can focus on real deductions.
  String? autoCrossReason(Cell c) {
    if (isTruck(c) || markAt(c) != Mark.none) return null;
    if (!nextToTruck(c)) return 'トラックのとなりではない';
    if (touchesBox(c)) return '箱のとなり';
    if (rowState(c.$1) != LineState.open) return 'この行はもう満杯';
    if (colState(c.$2) != LineState.open) return 'この列はもう満杯';
    return null;
  }

  /// A cell where a box is still possible.
  bool isCandidate(Cell c) =>
      inside(c) &&
      !isTruck(c) &&
      markAt(c) == Mark.none &&
      autoCrossReason(c) == null;

  /// Boxes that break a rule right now (shown in red).
  Set<Cell> get violations {
    final out = <Cell>{};
    for (final b in boxes) {
      if (!nextToTruck(b) ||
          touchesBox(b) ||
          rowState(b.$1) == LineState.over ||
          colState(b.$2) == LineState.over) {
        out.add(b);
      }
    }
    return out;
  }

  /// Boxes that are not part of the solution (used by hints).
  List<Cell> get wrongBoxes =>
      boxes.where((b) => !_solution.contains(b)).toList();

  /// Player crosses sitting on a solution cell (used by hints).
  List<Cell> get wrongCrosses => _marks.entries
      .where((e) => e.value == Mark.cross && _solution.contains(e.key))
      .map((e) => e.key)
      .toList();

  bool inSolution(Cell c) => _solution.contains(c);

  /// Stars: 3 = solved without hints, 2 = up to two hints, 1 = more.
  int get stars {
    if (!isCleared) return 0;
    if (hintsUsed == 0) return 3;
    return hintsUsed <= 2 ? 2 : 1;
  }

  int get score => isCleared
      ? size * size * 10 + (hintsUsed == 0 ? 200 : 0) + config.tier * 50
      : 0;

  bool get canUndo => _history.isNotEmpty && status == SessionStatus.playing;

  // ---------------------------------------------------------------------------
  // Actions

  void start() {
    if (status == SessionStatus.ready) status = SessionStatus.playing;
  }

  /// The mark a tap on [c] would produce: none → box → cross → none.
  Mark nextMark(Cell c) => switch (markAt(c)) {
    Mark.none => Mark.box,
    Mark.box => Mark.cross,
    Mark.cross => Mark.none,
  };

  /// Sets a mark. Returns false (unchanged) if not allowed.
  bool setMark(Cell c, Mark m) {
    if (status != SessionStatus.playing || !inside(c) || isTruck(c)) {
      return false;
    }
    if (markAt(c) == m) return false;
    _history.add(Map.of(_marks));
    if (_history.length > 200) _history.removeAt(0);
    if (m == Mark.none) {
      _marks.remove(c);
    } else {
      _marks[c] = m;
    }
    moves++;
    _checkCleared();
    return true;
  }

  bool tap(Cell c) => setMark(c, nextMark(c));

  bool undo() {
    if (!canUndo) return false;
    _marks
      ..clear()
      ..addAll(_history.removeLast());
    return true;
  }

  void reset() {
    if (status != SessionStatus.playing || _marks.isEmpty) return;
    _history.add(Map.of(_marks));
    _marks.clear();
  }

  void _checkCleared() {
    final placed = boxes.toSet();
    if (placed.length == _solution.length && placed.containsAll(_solution)) {
      status = SessionStatus.cleared;
    }
  }

  /// Records that a hint was consumed. [paid] = granted by a rewarded ad.
  void consumeHint({bool paid = false}) {
    if (!paid && freeHints > 0) freeHints--;
    hintsUsed++;
  }
}
