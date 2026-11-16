#!/usr/bin/env python3
"""Generates assets/stages/stages.json for the deduction puzzle.

Puzzle ("loading logic"): an n x n warehouse floor with trucks on it.
Place boxes so that
  1. every truck gets exactly one box on an orthogonally adjacent cell
     (one box per truck, one truck per box),
  2. no two boxes touch, not even diagonally,
  3. each row / column holds exactly the number of boxes shown on its edge.

For every stage this script
  * builds a random solution and derives the clues,
  * proves the solution is UNIQUE (exhaustive backtracking + matching),
  * solves it with human-style deduction rules and records the hardest rule
    tier needed (1 = counting, 2 = line patterns, 3 = "what if" look-ahead),
  * keeps the puzzle only if its tier matches the stage spec.
No stage ever requires guessing.

The rule tiers mirror lib/game/logic/deduction.dart (used for hints).

    python3 tool/gen_stages.py
"""
import itertools, json, os, random

ORTH = ((-1, 0), (1, 0), (0, -1), (0, 1))
ALL8 = tuple((dr, dc) for dr in (-1, 0, 1) for dc in (-1, 0, 1) if dr or dc)


class Contradiction(Exception):
    pass


class State:
    def __init__(self, n, trucks, rows, cols):
        self.n = n
        self.trucks = list(trucks)
        self.truck_set = set(trucks)
        self.rows = rows
        self.cols = cols
        self.boxes = set()
        self.cross = set()

    def copy(self):
        s = State(self.n, self.trucks, self.rows, self.cols)
        s.boxes = set(self.boxes)
        s.cross = set(self.cross)
        return s

    def inside(self, r, c):
        return 0 <= r < self.n and 0 <= c < self.n

    def row_count(self, r):
        return sum(1 for b in self.boxes if b[0] == r)

    def col_count(self, c):
        return sum(1 for b in self.boxes if b[1] == c)

    def is_candidate(self, cell):
        r, c = cell
        if not self.inside(r, c):
            return False
        if cell in self.truck_set or cell in self.boxes or cell in self.cross:
            return False
        if not any((r + dr, c + dc) in self.truck_set for dr, dc in ORTH):
            return False
        if any((r + dr, c + dc) in self.boxes for dr, dc in ALL8):
            return False
        if self.row_count(r) >= self.rows[r] or self.col_count(c) >= self.cols[c]:
            return False
        return True

    def candidates(self):
        return [(r, c) for r in range(self.n) for c in range(self.n)
                if self.is_candidate((r, c))]

    def line_cells(self, kind, i):
        return [(i, k) if kind == 'r' else (k, i) for k in range(self.n)]

    def need(self, kind, i):
        return (self.rows[i] - self.row_count(i)) if kind == 'r' else (self.cols[i] - self.col_count(i))

    def line_options(self, kind, i):
        """All ways to place the missing boxes of a line on its candidates
        without two of them being neighbours in the line."""
        need = self.need(kind, i)
        cands = [x for x in self.line_cells(kind, i) if self.is_candidate(x)]
        pos = 1 if kind == 'r' else 0
        out = []
        for combo in itertools.combinations(cands, need):
            if all(abs(a[pos] - b[pos]) > 1 for a, b in zip(combo, combo[1:])):
                out.append(combo)
        return cands, out

    def check(self):
        for kind in 'rc':
            for i in range(self.n):
                need = self.need(kind, i)
                if need < 0:
                    raise Contradiction
                if need > 0 and not self.line_options(kind, i)[1]:
                    raise Contradiction
        for t in self.trucks:
            adj = [(t[0] + dr, t[1] + dc) for dr, dc in ORTH]
            if not any(a in self.boxes for a in adj) and not any(self.is_candidate(a) for a in adj):
                raise Contradiction
        for b in self.boxes:
            if any((b[0] + dr, b[1] + dc) in self.boxes for dr, dc in ALL8):
                raise Contradiction
        if not has_matching(self.trucks, self.boxes, partial=True):
            raise Contradiction

    # ---- deduction rules; each returns (cell, is_box) or None -------------
    def rule_tier1(self):
        # Counting: a line whose remaining candidates all must be boxes.
        for kind in 'rc':
            for i in range(self.n):
                need = self.need(kind, i)
                if need <= 0:
                    continue
                cands = [x for x in self.line_cells(kind, i) if self.is_candidate(x)]
                if len(cands) == need:
                    return cands[0], True
        # A truck with no box yet and a single free neighbour.
        for t in self.trucks:
            adj = [(t[0] + dr, t[1] + dc) for dr, dc in ORTH]
            if any(a in self.boxes for a in adj):
                continue
            free = [a for a in adj if self.inside(*a) and self.is_candidate(a)]
            if len(free) == 1:
                return free[0], True
        return None

    def rule_tier2(self):
        # Line patterns: cells used by every / no arrangement of a line.
        for kind in 'rc':
            for i in range(self.n):
                if self.need(kind, i) <= 0:
                    continue
                cands, opts = self.line_options(kind, i)
                if not opts:
                    continue
                for cell in cands:
                    uses = sum(1 for o in opts if cell in o)
                    if uses == len(opts):
                        return cell, True
                    if uses == 0:
                        return cell, False
        return None

    def propagate(self, max_tier):
        """Applies rules up to max_tier until stuck. Returns highest tier used."""
        used = 0
        while True:
            self.check()
            move = self.rule_tier1()
            tier = 1
            if move is None and max_tier >= 2:
                move = self.rule_tier2()
                tier = 2
            if move is None:
                return used
            cell, is_box = move
            (self.boxes if is_box else self.cross).add(cell)
            used = max(used, tier)

    def rule_tier3(self):
        # "What if": assume a cell, follow tier 1-2 consequences, find a clash.
        for cell in self.candidates():
            for assume_box in (True, False):
                t = self.copy()
                (t.boxes if assume_box else t.cross).add(cell)
                try:
                    t.propagate(2)
                except Contradiction:
                    return cell, not assume_box
        return None


def has_matching(trucks, boxes, partial=False):
    """Perfect matching trucks<->boxes (partial: every box gets own truck)."""
    boxes = list(boxes)
    if not partial and len(boxes) != len(trucks):
        return False
    tset = {t: i for i, t in enumerate(trucks)}
    adj = [[tset[(b[0] + dr, b[1] + dc)] for dr, dc in ORTH if (b[0] + dr, b[1] + dc) in tset]
           for b in boxes]
    match = {}

    def try_box(i, seen):
        for t in adj[i]:
            if t in seen:
                continue
            seen.add(t)
            if t not in match or try_box(match[t], seen):
                match[t] = i
                return True
        return False

    return all(try_box(i, set()) for i in range(len(boxes)))


def logical_tier(n, trucks, rows, cols, solution):
    """Hardest rule tier needed (1-3), or None if deduction gets stuck."""
    s = State(n, trucks, rows, cols)
    top = 0
    try:
        while True:
            top = max(top, s.propagate(2))
            if s.boxes == solution:
                return max(top, 1)
            move = s.rule_tier3()
            if move is None:
                return None
            cell, is_box = move
            (s.boxes if is_box else s.cross).add(cell)
            top = 3
    except Contradiction:
        return None


def count_solutions(n, trucks, rows, cols, limit=2):
    truck_set = set(trucks)
    cells = [(r, c) for r in range(n) for c in range(n)
             if (r, c) not in truck_set and any((r + dr, c + dc) in truck_set for dr, dc in ORTH)]
    rc = [0] * n
    cc = [0] * n
    boxes = set()
    found = [0]
    # Candidate cells remaining per row from index i (for pruning).
    remaining_in_row = [[0] * n for _ in range(len(cells) + 1)]
    for i in range(len(cells) - 1, -1, -1):
        remaining_in_row[i] = list(remaining_in_row[i + 1])
        remaining_in_row[i][cells[i][0]] += 1

    def rec(i):
        if found[0] >= limit:
            return
        if any(rc[r] + remaining_in_row[i][r] < rows[r] for r in range(n)):
            return
        if i == len(cells):
            if rc == rows and cc == cols and has_matching(trucks, boxes):
                found[0] += 1
            return
        r, c = cells[i]
        if rc[r] < rows[r] and cc[c] < cols[c] and not any(
                (r + dr, c + dc) in boxes for dr, dc in ALL8):
            boxes.add((r, c)); rc[r] += 1; cc[c] += 1
            rec(i + 1)
            boxes.discard((r, c)); rc[r] -= 1; cc[c] -= 1
        rec(i + 1)

    rec(0)
    return found[0]


def random_puzzle(rng, n, k):
    boxes, trucks = [], []
    cells = [(r, c) for r in range(n) for c in range(n)]
    rng.shuffle(cells)
    for cell in cells:
        if len(boxes) == k:
            break
        r, c = cell
        if cell in trucks or any((r + dr, c + dc) in boxes for dr, dc in ALL8) or cell in boxes:
            continue
        spots = [(r + dr, c + dc) for dr, dc in ORTH
                 if 0 <= r + dr < n and 0 <= c + dc < n
                 and (r + dr, c + dc) not in boxes and (r + dr, c + dc) not in trucks]
        # A truck cell must not be where a later box would need to sit; fine.
        if not spots:
            continue
        boxes.append(cell)
        trucks.append(rng.choice(spots))
    if len(boxes) < k:
        return None
    rows = [sum(1 for b in boxes if b[0] == r) for r in range(n)]
    cols = [sum(1 for b in boxes if b[1] == c) for c in range(n)]
    return trucks, boxes, rows, cols


E, N, H = 'easy', 'normal', 'hard'
# size, boxes, required tier
SPECS = [
    dict(name='はじめての積み込み', d=E, n=4, k=3, tier=1, tutorial='basic'),
    dict(name='数字をよむ', d=E, n=4, k=4, tier=1, tutorial='count'),
    dict(name='となりあわない', d=E, n=5, k=5, tier=1, tutorial='touch'),
    dict(name='小さな倉庫', d=E, n=5, k=5, tier=1),
    dict(name='朝の便', d=E, n=5, k=6, tier=1),
    dict(name='6マス倉庫', d=E, n=6, k=7, tier=1),
    dict(name='ゼロの列', d=E, n=6, k=7, tier=1),
    dict(name='はじめての決め手', d=E, n=5, k=6, tier=2, tutorial='pattern'),
    dict(name='昼の便', d=E, n=6, k=8, tier=2),
    dict(name='新人卒業', d=E, n=6, k=8, tier=2),
    dict(name='ひろい倉庫', d=N, n=7, k=10, tier=2),
    dict(name='ならびを読む', d=N, n=7, k=10, tier=2),
    dict(name='夕方の便', d=N, n=7, k=11, tier=2),
    dict(name='もしもの推理', d=N, n=6, k=8, tier=3, tutorial='whatif'),
    dict(name='混雑ドック', d=N, n=7, k=11, tier=2),
    dict(name='二択のわな', d=N, n=6, k=8, tier=3),
    dict(name='雨の日の便', d=N, n=7, k=10, tier=3),
    dict(name='8マス倉庫', d=N, n=8, k=13, tier=2),
    dict(name='夜の便', d=N, n=7, k=11, tier=3),
    dict(name='中堅昇格', d=N, n=8, k=13, tier=2),
    dict(name='大倉庫', d=H, n=8, k=13, tier=3, tutorial='hard'),
    dict(name='すきまを読む', d=H, n=8, k=14, tier=3),
    dict(name='深夜便', d=H, n=8, k=13, tier=3),
    dict(name='迷いの通路', d=H, n=8, k=14, tier=3),
    dict(name='満車ドック', d=H, n=8, k=15, tier=3),
    dict(name='朝焼け便', d=H, n=8, k=14, tier=3),
    dict(name='倉庫番の意地', d=H, n=8, k=15, tier=3),
    dict(name='最終チェック', d=H, n=8, k=14, tier=3),
    dict(name='工場長の試練', d=H, n=8, k=15, tier=3),
    dict(name='SORT MASTER', d=H, n=8, k=15, tier=3),
]


def build(spec, seed):
    rng = random.Random(seed)
    for _ in range(20000):
        p = random_puzzle(rng, spec['n'], spec['k'])
        if p is None:
            continue
        trucks, boxes, rows, cols = p
        tier = logical_tier(spec['n'], trucks, rows, cols, set(boxes))
        if tier != spec['tier']:
            continue
        if count_solutions(spec['n'], trucks, rows, cols) != 1:
            continue
        return trucks, boxes, rows, cols
    raise SystemExit('could not build %s' % spec.get('name', spec))


# Daily puzzles: difficulty by weekday (Monday = 0 ... Sunday = 6).
DAILY_WEEKDAY = [
    dict(n=6, k=7, tier=1),   # Mon
    dict(n=6, k=8, tier=2),   # Tue
    dict(n=7, k=10, tier=2),  # Wed
    dict(n=7, k=11, tier=2),  # Thu
    dict(n=7, k=10, tier=3),  # Fri
    dict(n=8, k=13, tier=3),  # Sat
    dict(n=8, k=14, tier=3),  # Sun
]
DAILY_PER_WEEKDAY = 53  # ~1 year before repeating


def build_daily(root):
    """assets/stages/daily.json: 7 weekday pools, all unique & deducible."""
    pools = []
    seen = set()
    for wd, spec in enumerate(DAILY_WEEKDAY):
        pool = []
        seed = 50000 + wd * 10007
        while len(pool) < DAILY_PER_WEEKDAY:
            seed += 1
            trucks, boxes, rows, cols = build(spec, seed)
            key = tuple(sorted(trucks))
            if key in seen:
                continue
            seen.add(key)
            rng = random.Random(seed)
            pool.append({
                'size': spec['n'],
                'tier': spec['tier'],
                'trucks': [[r, c, rng.randrange(6)] for r, c in trucks],
                'solution': [[r, c] for r, c in boxes],
            })
        pools.append(pool)
        print('daily weekday %d: %d puzzles' % (wd, len(pool)), flush=True)
    with open(os.path.join(root, 'assets', 'stages', 'daily.json'), 'w', encoding='utf-8') as f:
        json.dump({'version': 1, 'weekdays': pools}, f, separators=(',', ':'))


def main():
    out, report = [], []
    for i, spec in enumerate(SPECS, start=1):
        trucks, boxes, rows, cols = build(spec, 9000 + i * 131)
        rng = random.Random(i)
        stage = {
            'id': i,
            'name': spec['name'],
            'difficulty': spec['d'],
            'size': spec['n'],
            'tier': spec['tier'],
            # truck i is paired with box i (used for the shipping finale)
            'trucks': [[r, c, rng.randrange(6)] for r, c in trucks],
            'solution': [[r, c] for r, c in boxes],
        }
        if spec.get('tutorial'):
            stage['tutorial'] = spec['tutorial']
        out.append(stage)
        line = '%2d %-6s %dx%d boxes=%2d tier=%d rows=%s cols=%s' % (
            i, spec['d'], spec['n'], spec['n'], spec['k'], spec['tier'], rows, cols)
        report.append(line)
        print(line, flush=True)
    root = os.path.join(os.path.dirname(__file__), '..')
    with open(os.path.join(root, 'assets', 'stages', 'stages.json'), 'w', encoding='utf-8') as f:
        json.dump({'version': 3, 'stages': out}, f, ensure_ascii=False, separators=(',', ':'))
    build_daily(root)
    with open(os.path.join(root, 'docs', 'balance_report.txt'), 'w', encoding='utf-8') as f:
        f.write('# tool/gen_stages.py: every stage has a unique solution and is solvable by deduction.\n'
                '# tier 1 = counting, 2 = line patterns, 3 = "what if" look-ahead\n')
        f.write('\n'.join(report) + '\n')


if __name__ == '__main__':
    main()
