import 'game_session.dart';
import 'models.dart';

/// Depth-first puzzle solver with memoization.
///
/// Used by the hint feature and by tests that prove every stage is solvable.
/// Hidden packages are treated as known (the solver sees everything).
class Solver {
  Solver({this.maxNodes = 200000});

  final int maxNodes;
  int _nodes = 0;
  final Set<String> _dead = {};

  /// Returns a winning lane sequence from [start], or null if none was found
  /// within [maxNodes].
  List<int>? solve(GameSession start) {
    _nodes = 0;
    _dead.clear();
    final s = start.clone()..status = SessionStatus.playing;
    final path = <int>[];
    return _dfs(s, path) ? path : null;
  }

  /// First move of a solution, or a heuristic move if the search gives up.
  int? hint(GameSession s) {
    final sol = solve(s);
    if (sol != null && sol.isNotEmpty) return sol.first;
    return _ordered(s).firstOrNull;
  }

  bool _dfs(GameSession s, List<int> path) {
    if (s.status == SessionStatus.cleared) return true;
    if (s.status == SessionStatus.failed) return false;
    if (++_nodes > maxNodes) return false;
    final key = s.stateKey();
    if (_dead.contains(key)) return false;
    for (final lane in _ordered(s)) {
      final next = s.clone();
      next.tap(lane);
      path.add(lane);
      if (_dfs(next, path)) return true;
      path.removeLast();
      if (_nodes > maxNodes) return false;
    }
    _dead.add(key);
    return false;
  }

  /// Moves that load a truck first (fewest shelf uses), then the rest.
  List<int> _ordered(GameSession s) {
    final lanes = [
      for (var i = 0; i < s.lanes.length; i++)
        if (s.canTap(i)) i,
    ];
    int rank(int lane) => s.dockFor(s.lanes[lane].first.color) != null ? 0 : 1;
    lanes.sort((a, b) => rank(a).compareTo(rank(b)));
    return lanes;
  }
}
