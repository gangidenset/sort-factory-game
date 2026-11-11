#!/usr/bin/env python3
"""Generates assets/stages/stages.json for the turn-based sorting puzzle.

For each stage spec it creates random layouts, keeps only layouts that are
solvable, computes `par` (fewest shelf placements of a perfect solution, by
0-1 BFS) and estimates difficulty by letting a "greedy-random" player (sends
to a truck when possible, otherwise taps a random lane) play 200 times. The
candidate whose win rate is closest to the spec's target is written out.

Rules here MUST mirror lib/game/logic/game_session.dart; the Dart test
test/game/stage_catalog_test.dart re-verifies solvability and par.

    python3 tool/gen_stages.py
"""
import collections, json, os, random

# --------------------------------------------------------------------------
# Rules (mirror of GameSession)

class Sim:
    __slots__ = ('lanes', 'ptr', 'docks', 'shelf', 'qi', 'trucks', 'cap',
                 'shipped', 'placements', 'locks', 'status')

    def __init__(self, st):
        self.lanes = st['lanes']
        self.ptr = [0] * len(self.lanes)
        self.trucks = st['trucks_full']  # list of (color, capacity)
        self.qi = 0
        self.docks = []
        for _ in range(st['docks']):
            self.docks.append(self._next())
        self.shelf = []
        self.cap = st['shelf']
        self.shipped = 0
        self.placements = 0
        self.locks = st.get('locks', [])
        self.status = 'playing'

    def copy(self):
        o = Sim.__new__(Sim)
        o.lanes = self.lanes
        o.ptr = list(self.ptr)
        o.trucks = self.trucks
        o.qi = self.qi
        o.docks = [None if d is None else list(d) for d in self.docks]
        o.shelf = list(self.shelf)
        o.cap = self.cap
        o.shipped = self.shipped
        o.placements = self.placements
        o.locks = self.locks
        o.status = self.status
        return o

    def _next(self):
        if self.qi >= len(self.trucks):
            return None
        c, k = self.trucks[self.qi]
        self.qi += 1
        return [c, k, 0]  # color, capacity, filled

    def locked(self, lane):
        return any(l['lane'] == lane and self.shipped < l['after'] for l in self.locks)

    def can_tap(self, lane):
        return (self.status == 'playing' and self.ptr[lane] < len(self.lanes[lane])
                and not self.locked(lane))

    def dock_for(self, color):
        best = None
        for i, d in enumerate(self.docks):
            if d is None or d[0] != color or d[2] >= d[1]:
                continue
            if best is None or d[2] > self.docks[best][2]:
                best = i
        return best

    def front(self, lane):
        return self.lanes[lane][self.ptr[lane]]

    def tap(self, lane):
        c = self.front(lane)
        self.ptr[lane] += 1
        d = self.dock_for(c)
        if d is not None:
            self.docks[d][2] += 1
            self._resolve()
        elif len(self.shelf) < self.cap:
            self.shelf.append(c)
            self.placements += 1
        else:
            self.status = 'failed'
            return
        self._check_end()

    def _resolve(self):
        while True:
            full = next((i for i, d in enumerate(self.docks)
                         if d is not None and d[2] >= d[1]), -1)
            if full < 0:
                break
            self.shipped += 1
            self.docks[full] = self._next()
            i = 0
            while i < len(self.shelf):
                d = self.dock_for(self.shelf[i])
                if d is None:
                    i += 1
                    continue
                self.shelf.pop(i)
                self.docks[d][2] += 1

    def _check_end(self):
        if all(d is None for d in self.docks) and self.qi >= len(self.trucks):
            self.status = 'cleared'
            return
        if not any(self.can_tap(i) for i in range(len(self.lanes))):
            self.status = 'failed'

    def key(self):
        docks = sorted('-' if d is None else '%d%d' % (d[0], d[2]) for d in self.docks)
        return (tuple(self.ptr), tuple(sorted(self.shelf)), tuple(docks), self.qi)

    def moves(self):
        return [i for i in range(len(self.lanes)) if self.can_tap(i)]


def par_of(st, limit=400000):
    """Fewest shelf placements to clear (0-1 BFS). None if unsolvable."""
    start = Sim(st)
    start_key = start.key()
    best = {start_key: 0}
    dq = collections.deque([(0, start)])
    seen = 0
    while dq:
        cost, s = dq.popleft()
        if cost > best.get(s.key(), 1 << 30):
            continue
        seen += 1
        if seen > limit:
            return None
        for m in s.moves():
            n = s.copy()
            n.tap(m)
            if n.status == 'failed':
                continue
            if n.status == 'cleared':
                return n.placements  # first clear popped in cost order
            k = n.key()
            if n.placements < best.get(k, 1 << 30):
                best[k] = n.placements
                if n.placements == cost:
                    dq.appendleft((cost, n))
                else:
                    dq.append((n.placements, n))
    return None


def greedy_random_rate(st, runs=200, seed=0):
    rng = random.Random(seed)
    wins = 0
    for _ in range(runs):
        s = Sim(st)
        while s.status == 'playing':
            ms = s.moves()
            direct = [m for m in ms if s.dock_for(s.front(m)) is not None]
            s.tap(rng.choice(direct or ms))
        wins += s.status == 'cleared'
    return wins / runs

# --------------------------------------------------------------------------
# Generation

def make_layout(rng, spec):
    colors = spec['colors']
    cap = spec.get('cap', 3)
    trucks = []
    per_color = spec['trucks'] // len(colors)
    extra = spec['trucks'] - per_color * len(colors)
    for i, c in enumerate(colors):
        trucks += [c] * (per_color + (1 if i < extra else 0))
    rng.shuffle(trucks)
    # Avoid long runs of the same color in the queue (boring).
    for _ in range(50):
        bad = [i for i in range(1, len(trucks)) if trucks[i] == trucks[i - 1]]
        if not bad:
            break
        i = rng.choice(bad)
        j = rng.randrange(len(trucks))
        trucks[i], trucks[j] = trucks[j], trucks[i]
    pkgs = [c for c in trucks for _ in range(cap)]
    rng.shuffle(pkgs)
    n = spec['lanes']
    lanes = [[] for _ in range(n)]
    # Uneven lane lengths look more natural.
    for i, c in enumerate(pkgs):
        lanes[rng.randrange(n) if rng.random() < 0.35 else i % n].append(c)
    lanes = [l for l in lanes if l] 
    st = dict(lanes=lanes, trucks=trucks, trucks_full=[(c, cap) for c in trucks],
              docks=spec['docks'], shelf=spec['shelf'], truckCapacity=cap)
    hidden = []
    for li, l in enumerate(lanes):
        for idx in range(1, len(l)):
            if rng.random() < spec.get('hidden', 0):
                hidden.append([li, idx])
    if hidden:
        st['hidden'] = hidden
    if spec.get('locks'):
        locks = []
        for k in range(spec['locks']):
            locks.append({'lane': len(lanes) - 1 - k, 'after': spec.get('lockAfter', 2) + k * 2})
        st['locks'] = locks
    return st


def build(spec, seed):
    rng = random.Random(seed)
    best = None
    for attempt in range(spec.get('tries', 60)):
        st = make_layout(rng, spec)
        if max(len(l) for l in st['lanes']) > 9:
            continue
        par = par_of(st)
        if par is None:
            continue
        rate = greedy_random_rate(st, seed=attempt)
        score = abs(rate - spec['target'])
        if best is None or score < best[0]:
            best = (score, st, par, rate)
        if score < 0.04:
            break
    assert best, 'no solvable layout for %s' % spec
    return best[1], best[2], best[3]


E, N, H = 'easy', 'normal', 'hard'
# lanes, docks, colors, trucks, shelf, target greedy-random win rate
SPECS = [
    # EASY: learn the loop, first chains
    dict(name='はじめての出荷', d=E, lanes=3, docks=2, colors=[0, 1], trucks=4, shelf=5, target=1.0, tutorial='basic'),
    dict(name='棚をつかう', d=E, lanes=3, docks=2, colors=[0, 1, 2], trucks=5, shelf=5, target=0.9, tutorial='shelf'),
    dict(name='連鎖出荷', d=E, lanes=3, docks=2, colors=[0, 1, 2], trucks=6, shelf=5, target=0.85, tutorial='chain'),
    dict(name='3台ならび', d=E, lanes=4, docks=3, colors=[0, 1, 2], trucks=6, shelf=5, target=0.85),
    dict(name='順番を読む', d=E, lanes=4, docks=2, colors=[0, 1, 2], trucks=7, shelf=4, target=0.75, tutorial='queue'),
    dict(name='4色便', d=E, lanes=4, docks=3, colors=[0, 1, 2, 3], trucks=8, shelf=5, target=0.75),
    dict(name='ちいさな棚', d=E, lanes=4, docks=3, colors=[0, 1, 2], trucks=8, shelf=4, target=0.65),
    dict(name='見えない荷物', d=E, lanes=4, docks=3, colors=[0, 1, 2, 3], trucks=8, shelf=5, target=0.7, hidden=0.25, tutorial='hidden'),
    dict(name='倉庫の朝', d=E, lanes=5, docks=3, colors=[0, 1, 2, 3], trucks=9, shelf=5, target=0.6),
    dict(name='新人卒業', d=E, lanes=5, docks=3, colors=[0, 1, 2, 3], trucks=10, shelf=4, target=0.5),
    # NORMAL
    dict(name='閉ざされたレーン', d=N, lanes=5, docks=3, colors=[0, 1, 2, 3], trucks=10, shelf=5, target=0.5, locks=1, lockAfter=2, tutorial='lock'),
    dict(name='5色便', d=N, lanes=5, docks=3, colors=[0, 1, 2, 3, 4], trucks=10, shelf=5, target=0.45),
    dict(name='2台ドック', d=N, lanes=5, docks=2, colors=[0, 1, 2, 3], trucks=10, shelf=5, target=0.4),
    dict(name='霧の倉庫', d=N, lanes=5, docks=3, colors=[0, 1, 2, 3, 4], trucks=11, shelf=5, target=0.4, hidden=0.35),
    dict(name='大型トラック', d=N, lanes=5, docks=3, colors=[0, 1, 2, 3], trucks=9, cap=4, shelf=5, target=0.4, tutorial='big'),
    dict(name='棚4つ', d=N, lanes=5, docks=3, colors=[0, 1, 2, 3, 4], trucks=11, shelf=4, target=0.35),
    dict(name='夕方ラッシュ', d=N, lanes=6, docks=3, colors=[0, 1, 2, 3, 4], trucks=12, shelf=5, target=0.35, locks=1, lockAfter=3),
    dict(name='まぜこぜ', d=N, lanes=6, docks=3, colors=[0, 1, 2, 3, 4, 5], trucks=12, shelf=5, target=0.3, hidden=0.2),
    dict(name='細い通路', d=N, lanes=5, docks=2, colors=[0, 1, 2, 3, 4], trucks=11, shelf=5, target=0.3),
    dict(name='中堅昇格', d=N, lanes=6, docks=3, colors=[0, 1, 2, 3, 4, 5], trucks=13, shelf=5, target=0.25, hidden=0.2, locks=1, lockAfter=3),
    # HARD
    dict(name='棚3つ', d=H, lanes=5, docks=3, colors=[0, 1, 2, 3, 4], trucks=11, shelf=3, target=0.2, tutorial='hard'),
    dict(name='6色の迷路', d=H, lanes=6, docks=3, colors=[0, 1, 2, 3, 4, 5], trucks=13, shelf=4, target=0.2),
    dict(name='大型便ラッシュ', d=H, lanes=6, docks=3, colors=[0, 1, 2, 3, 4], trucks=11, cap=4, shelf=4, target=0.18),
    dict(name='深い霧', d=H, lanes=6, docks=3, colors=[0, 1, 2, 3, 4, 5], trucks=13, shelf=4, target=0.18, hidden=0.4),
    dict(name='2台だけ', d=H, lanes=6, docks=2, colors=[0, 1, 2, 3, 4], trucks=12, shelf=4, target=0.15),
    dict(name='二重ロック', d=H, lanes=6, docks=3, colors=[0, 1, 2, 3, 4, 5], trucks=14, shelf=4, target=0.15, locks=2, lockAfter=3),
    dict(name='夜間仕分け', d=H, lanes=6, docks=3, colors=[0, 1, 2, 3, 4, 5], trucks=14, shelf=3, target=0.12, hidden=0.25),
    dict(name='特大便', d=H, lanes=6, docks=3, colors=[0, 1, 2, 3, 4, 5], trucks=12, cap=4, shelf=4, target=0.12, hidden=0.2),
    dict(name='工場長の試練', d=H, lanes=6, docks=2, colors=[0, 1, 2, 3, 4, 5], trucks=14, shelf=4, target=0.1, locks=1, lockAfter=4),
    dict(name='SORT MASTER', d=H, lanes=6, docks=3, colors=[0, 1, 2, 3, 4, 5], trucks=16, shelf=4, target=0.08, hidden=0.3, locks=2, lockAfter=4),
]


def main():
    out = []
    report = []
    for i, spec in enumerate(SPECS, start=1):
        st, par, rate = build(spec, seed=7000 + i * 101)
        stage = {
            'id': i,
            'name': spec['name'],
            'difficulty': spec['d'],
            'docks': st['docks'],
            'shelf': st['shelf'],
            'truckCapacity': st['truckCapacity'],
            'trucks': st['trucks'],
            'lanes': st['lanes'],
            'par': par,
        }
        for k in ('hidden', 'locks'):
            if k in st:
                stage[k] = st[k]
        if spec.get('tutorial'):
            stage['tutorial'] = spec['tutorial']
        out.append(stage)
        line = '%2d %-6s pkgs=%2d par=%d greedy-random win=%3d%% (target %3d%%)' % (
            i, spec['d'], sum(len(l) for l in st['lanes']), par, rate * 100, spec['target'] * 100)
        report.append(line)
        print(line, flush=True)
    root = os.path.join(os.path.dirname(__file__), '..')
    with open(os.path.join(root, 'assets', 'stages', 'stages.json'), 'w', encoding='utf-8') as f:
        json.dump({'version': 2, 'stages': out}, f, ensure_ascii=False, separators=(',', ':'))
    with open(os.path.join(root, 'docs', 'balance_report.txt'), 'w', encoding='utf-8') as f:
        f.write('# tool/gen_stages.py output: greedy-random player win rate per stage\n')
        f.write('\n'.join(report) + '\n')


if __name__ == '__main__':
    main()
