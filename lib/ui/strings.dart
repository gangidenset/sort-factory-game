/// All user-facing copy in one place to ease future localization (ARB).
library;

import '../game/logic/models.dart';

class S {
  const S._();

  static const appTitle = 'SORT FACTORY';
  static const tagline = '流れる荷物を、正しいトラックへ。';
  static const play = 'プレイ';
  static const stages = 'ステージ';
  static const factory = '工場';
  static const shop = 'ショップ';
  static const settings = '設定';
  static const missions = 'デイリーミッション';

  static const easy = 'EASY';
  static const normal = 'NORMAL';
  static const hard = 'HARD';

  static String failReason(FailReason r) => switch (r) {
    FailReason.mistakes => 'ミスが多すぎた…',
    FailReason.jam => 'コンベアが詰まった…',
    FailReason.timeUp => '時間切れ…',
    FailReason.outOfMoves => '操作回数が尽きた…',
  };

  static String reviveLabel(FailReason r) => switch (r) {
    FailReason.mistakes => '広告を見て復活（ミス回復）',
    FailReason.jam => '広告を見て復活（荷物3個撤去）',
    FailReason.timeUp => '広告を見て復活（+15秒）',
    FailReason.outOfMoves => '広告を見て復活（+5手）',
  };
}

class Tutorial {
  const Tutorial(this.title, this.lines);
  final String title;
  final List<String> lines;
}

const tutorials = <String, Tutorial>{
  'basic': Tutorial('仕分けの基本', [
    'コンベアの一番下（枠の中）の荷物を仕分けます。',
    '同じ色のトラックをタップ、またはドラッグして届けよう。',
    '色を間違えるとミス。ミスが上限に達すると失敗です。',
  ]),
  'truck': Tutorial('トラックを満タンに', [
    'トラックは満タンになると出発し、ボーナス＋150点！',
    '次に来るトラックは右下の「NEXT」で確認できます。',
  ]),
  'buffer': Tutorial('一時保管エリア', [
    '合うトラックがない荷物は左の「保管」へ。',
    '保管した荷物はタップで選び、トラックをタップで届けます。',
    'NEXTのトラックに合う荷物を取っておくのがコツ！',
  ]),
  'timed': Tutorial('お急ぎ便', [
    '時計マークの荷物は時間内に届けないとミスになります。',
    '保管エリアの中でも時間は進むので注意！',
  ]),
  'combo': Tutorial('連続正解ボーナス', [
    '連続で正しく届けるとコンボで得点アップ。',
    'コンボは5回ごとにお祝い。★3を狙おう！',
  ]),
  'chute': Tutorial('返品シュート', [
    'どうしても行き先がない荷物は右の「返品」へ。',
    'ミスにはなりませんが、コンボが途切れます。',
  ]),
  'buffer2': Tutorial('4つのドック', [
    'ドックが4つ、保管スロットが2つに増えました。',
    '複数のトラックを同時に意識して仕分けよう。',
  ]),
  'shifting': Tutorial('色変わり荷物', [
    '角に別の色がついた荷物は、時間で色が入れ替わります。',
    '白い輪が一周すると色が変わる合図。タイミングを見て届けよう。',
  ]),
  'marks': Tutorial('配送マーク', [
    'トラックによっては ★ ● ▲ のマークも指定されます。',
    '色とマークの両方が合う荷物だけ受け付けます。',
  ]),
  'timeLimit': Tutorial('タイムセール', [
    'このステージには制限時間があります（画面上部）。',
    '迷っている時間はありません！',
  ]),
  'moves': Tutorial('操作回数の制限', [
    'HARDでは操作回数（保管・返品も1手）に上限があります。',
    '無駄な保管や返品を減らしてクリアを目指そう。',
  ]),
};
