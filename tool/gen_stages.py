#!/usr/bin/env python3
"""Generates assets/stages/stages.json.

Stage data is plain JSON so designers can also edit the output by hand; this
script just encodes the initial difficulty curve. Run:
    python3 tool/gen_stages.py
"""
import json, os

def perfect_score(target, cap, docks, timed=0.0, shift=0.0):
    s = sum(100 + 10 * min(k, 20) for k in range(target))
    s += (target // cap) * 150
    s += int(target * (timed * 50 + shift * 30))
    return s

S = []
def stage(name, difficulty, **kw):
    sid = len(S) + 1
    d = dict(id=sid, name=name, difficulty=difficulty, seed=1000 + sid * 37)
    d.update(kw)
    # Length scaling (keeps the tutorial stages short).
    factor = {'easy': 1.2, 'normal': 1.25, 'hard': 1.2}[difficulty]
    if sid > 2:
        d['targetDeliveries'] = int(round(d['targetDeliveries'] * factor))
    if 'moveSlack' in d:
        d['moveLimit'] = d['targetDeliveries'] + d.pop('moveSlack')
    cap = d.get('dockCapacity', 3)
    best = perfect_score(d['targetDeliveries'], cap, d.get('docks', 2),
                         d.get('timedRate', 0), d.get('shiftRate', 0))
    d['starScores'] = [int(round(best * 0.6, -1)), int(round(best * 0.9, -1))]
    S.append(d)

# ---- EASY (1-10): learn the rules ------------------------------------------
stage('はじめての仕分け', 'easy', colors=[0,1], docks=2, targetDeliveries=8,
      spawnInterval=2.6, offRate=0, maxMistakes=3, tutorial='basic')
stage('トラックを満タンに', 'easy', colors=[0,1], docks=2, targetDeliveries=10,
      spawnInterval=2.4, offRate=0, tutorial='truck')
stage('3つのドック', 'easy', colors=[0,1,2], docks=3, targetDeliveries=12,
      spawnInterval=2.3, offRate=0.05)
stage('一時保管エリア', 'easy', colors=[0,1,2], docks=3, targetDeliveries=12,
      spawnInterval=2.3, offRate=0.2, bufferSlots=1, tutorial='buffer')
stage('流れに乗る', 'easy', colors=[0,1,2], docks=3, targetDeliveries=14,
      spawnInterval=2.1, offRate=0.15, bufferSlots=1)
stage('4色の荷物', 'easy', colors=[0,1,2,3], docks=3, targetDeliveries=14,
      spawnInterval=2.1, offRate=0.2, bufferSlots=1)
stage('お急ぎ便', 'easy', colors=[0,1,2], docks=3, targetDeliveries=14,
      spawnInterval=2.1, offRate=0.1, bufferSlots=1, timedRate=0.2,
      timedSeconds=12, tutorial='timed')
stage('連続仕分け', 'easy', colors=[0,1,2,3], docks=3, targetDeliveries=16,
      spawnInterval=1.9, offRate=0.15, bufferSlots=1, tutorial='combo')
stage('返品シュート', 'easy', colors=[0,1,2,3], docks=3, targetDeliveries=16,
      spawnInterval=1.9, offRate=0.3, bufferSlots=1, tutorial='chute')
stage('新人卒業試験', 'easy', colors=[0,1,2,3], docks=3, targetDeliveries=18,
      spawnInterval=1.8, offRate=0.2, bufferSlots=1, timedRate=0.15,
      timedSeconds=11)

# ---- NORMAL (11-20): more trucks, new package types ------------------------
stage('4番ドック開放', 'normal', colors=[0,1,2,3], docks=4, dockCapacity=4,
      targetDeliveries=18, spawnInterval=1.9, offRate=0.2, bufferSlots=2,
      tutorial='buffer2')
stage('色変わり荷物', 'normal', colors=[0,1,2], docks=3, dockCapacity=4,
      targetDeliveries=18, spawnInterval=2.0, offRate=0.15, bufferSlots=1,
      shiftRate=0.25, shiftPeriod=2.0, tutorial='shifting')
stage('5色ライン', 'normal', colors=[0,1,2,3,4], docks=4, dockCapacity=4,
      targetDeliveries=20, spawnInterval=1.8, offRate=0.25, bufferSlots=2)
stage('配送マーク', 'normal', colors=[0,1,2], docks=3, dockCapacity=4,
      targetDeliveries=18, spawnInterval=2.1, offRate=0.15, bufferSlots=1,
      useMarks=True, markDockRate=0.45, tutorial='marks')
stage('タイムセール', 'normal', colors=[0,1,2,3], docks=3, dockCapacity=4,
      targetDeliveries=20, spawnInterval=1.7, offRate=0.15, bufferSlots=2,
      timeLimit=55, tutorial='timeLimit')
stage('混載便', 'normal', colors=[0,1,2,3,4], docks=4, dockCapacity=4,
      targetDeliveries=20, spawnInterval=1.8, offRate=0.2, bufferSlots=2,
      timedRate=0.15, timedSeconds=10, shiftRate=0.1)
stage('マーク専用便', 'normal', colors=[0,1,2,3], docks=3, dockCapacity=4,
      targetDeliveries=20, spawnInterval=1.9, offRate=0.15, bufferSlots=2,
      useMarks=True, markDockRate=0.3, markOnlyRate=0.3)
stage('ピークタイム', 'normal', colors=[0,1,2,3,4], docks=4, dockCapacity=4,
      targetDeliveries=22, spawnInterval=1.6, offRate=0.2, bufferSlots=2,
      timedRate=0.1, timedSeconds=10)
stage('せわしない色', 'normal', colors=[0,1,2,3], docks=4, dockCapacity=4,
      targetDeliveries=22, spawnInterval=1.7, offRate=0.2, bufferSlots=2,
      shiftRate=0.3, shiftPeriod=1.6)
stage('中堅昇格試験', 'normal', colors=[0,1,2,3,4], docks=4, dockCapacity=4,
      targetDeliveries=25, spawnInterval=1.6, offRate=0.2, bufferSlots=2,
      timedRate=0.12, timedSeconds=10, shiftRate=0.12, useMarks=True,
      markDockRate=0.25)

# ---- HARD (21-30): move limits, speed, everything combined -----------------
def hard(name, target, slack, **kw):
    base = dict(docks=4, dockCapacity=4, bufferSlots=2, targetDeliveries=target,
                moveSlack=slack, maxMistakes=3)
    base.update(kw)
    stage(name, 'hard', **base)

hard('節約仕分け', 20, 8, colors=[0,1,2,3,4], spawnInterval=1.7, offRate=0.2,
     tutorial='moves')
hard('6色ライン', 22, 8, colors=[0,1,2,3,4,5], spawnInterval=1.7, offRate=0.2)
hard('時限便ラッシュ', 22, 7, colors=[0,1,2,3,4], spawnInterval=1.6,
     offRate=0.15, timedRate=0.3, timedSeconds=9)
hard('マーク＆カラー', 22, 7, colors=[0,1,2,3,4], spawnInterval=1.7,
     offRate=0.2, useMarks=True, markDockRate=0.45, markOnlyRate=0.15)
hard('短いコンベア', 24, 7, colors=[0,1,2,3,4], spawnInterval=1.6,
     offRate=0.2, beltCapacity=5, shiftRate=0.15)
hard('夜間配送', 24, 6, colors=[0,1,2,3,4,5], spawnInterval=1.5, offRate=0.2,
     timedRate=0.15, timedSeconds=9, shiftRate=0.15, timeLimit=60)
hard('一発勝負', 24, 6, colors=[0,1,2,3,4], spawnInterval=1.6, offRate=0.2,
     maxMistakes=2, useMarks=True, markDockRate=0.35)
hard('高速ライン', 26, 6, colors=[0,1,2,3,4,5], spawnInterval=1.4,
     offRate=0.2, beltSpeed=4.0, timedRate=0.12, timedSeconds=8)
hard('全部のせ', 26, 6, colors=[0,1,2,3,4,5], spawnInterval=1.45, offRate=0.22,
     timedRate=0.12, timedSeconds=9, shiftRate=0.12, useMarks=True,
     markDockRate=0.3, markOnlyRate=0.1)
hard('工場長への道', 30, 6, colors=[0,1,2,3,4,5], spawnInterval=1.4,
     offRate=0.22, timedRate=0.15, timedSeconds=8, shiftRate=0.15,
     useMarks=True, markDockRate=0.35, markOnlyRate=0.15, maxMistakes=3)

assert len(S) == 30
out = os.path.join(os.path.dirname(__file__), '..', 'assets', 'stages', 'stages.json')
with open(out, 'w', encoding='utf-8') as f:
    json.dump({'version': 1, 'stages': S}, f, ensure_ascii=False, indent=1)
print('wrote', len(S), 'stages')
