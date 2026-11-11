#!/usr/bin/env python3
"""Synthesizes the game's sound effects into assets/audio/*.wav.

All sounds are generated from scratch by this script (no third-party
samples), so they carry no external license obligations.
    python3 tool/gen_sfx.py
"""
import math, os, struct, wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')

def tone(freqs, dur, vol=0.5, shape='sine', attack=0.005, decay=None):
    """freqs: list of (start_hz, end_hz) sweeps played back-to-back."""
    out = []
    seg = dur / len(freqs)
    phase = 0.0
    for f0, f1 in freqs:
        n = int(seg * RATE)
        for i in range(n):
            t = i / RATE
            f = f0 + (f1 - f0) * (i / max(1, n - 1))
            phase += 2 * math.pi * f / RATE
            if shape == 'sine':
                v = math.sin(phase)
            elif shape == 'square':
                v = 0.6 if math.sin(phase) >= 0 else -0.6
            else:  # triangle
                v = 2 / math.pi * math.asin(math.sin(phase))
            out.append(v)
    total = len(out)
    d = decay if decay is not None else dur
    res = []
    for i, v in enumerate(out):
        t = i / RATE
        env = min(1.0, t / attack) * math.exp(-3.0 * t / d)
        # 10ms fade-out to avoid clicks
        env *= min(1.0, (total - i) / (0.01 * RATE))
        res.append(v * env * vol)
    return res

def chord(parts):
    n = max(len(p) for p in parts)
    return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]

def concat(*parts):
    r = []
    for p in parts:
        r.extend(p)
    return r

def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + '.wav'), 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(
            struct.pack('<h', int(max(-1, min(1, s)) * 32000)) for s in samples))

write('tap', tone([(900, 700)], 0.05, 0.35, 'triangle'))
write('correct', tone([(660, 1320)], 0.09, 0.45, 'triangle'))
write('wrong', tone([(220, 160)], 0.22, 0.45, 'square'))
write('store', tone([(500, 650)], 0.08, 0.4, 'triangle'))
write('truck', concat(tone([(660, 660)], 0.08, 0.4, 'triangle'),
                      tone([(990, 990)], 0.08, 0.4, 'triangle'),
                      tone([(1320, 1320)], 0.16, 0.4, 'triangle')))
write('combo', tone([(800, 1600)], 0.18, 0.4, 'sine'))
write('clear', concat(
    chord([tone([(523, 523)], 0.12, 0.3, 'triangle'), tone([(659, 659)], 0.12, 0.25)]),
    chord([tone([(659, 659)], 0.12, 0.3, 'triangle'), tone([(784, 784)], 0.12, 0.25)]),
    chord([tone([(784, 784)], 0.4, 0.3, 'triangle'), tone([(1047, 1047)], 0.4, 0.25)])))
write('fail', concat(tone([(392, 392)], 0.15, 0.35, 'triangle'),
                     tone([(330, 330)], 0.15, 0.35, 'triangle'),
                     tone([(262, 200)], 0.35, 0.35, 'triangle')))
# Rising chain stings: each chain level is a higher arpeggio.
base = 523.25
for level in range(2, 7):
    f = base * (2 ** ((level - 2) * 3 / 12))
    write('chain%d' % level, concat(
        tone([(f, f)], 0.07, 0.35, 'triangle'),
        tone([(f * 1.26, f * 1.26)], 0.07, 0.35, 'triangle'),
        chord([tone([(f * 1.5, f * 1.5)], 0.25, 0.3, 'triangle'), tone([(f * 2, f * 2)], 0.25, 0.2)])))
print('ok')
