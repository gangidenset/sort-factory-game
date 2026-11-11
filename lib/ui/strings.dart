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
    FailReason.shelfOverflow => '棚があふれた…',
    FailReason.stuck => '動かせる荷物がなくなった…',
  };

  static String reviveLabel(FailReason r) => '広告を見て復活（1手戻す＋棚+1）';
}

class Tutorial {
  const Tutorial(this.title, this.lines);
  final String title;
  final List<String> lines;
}

const tutorials = <String, Tutorial>{
  'basic': Tutorial('出荷のきほん', [
    'レーンをタップすると、一番上の荷物が同じ色のトラックへ飛んでいきます。',
    'トラックが満タンになると出荷！次のトラックがやってきます。',
    '全部のトラックを出荷できたらクリア。時間制限はありません。',
  ]),
  'shelf': Tutorial('棚', [
    '同じ色のトラックがいない荷物は「棚」に置かれます。',
    '棚の荷物は、合うトラックが来ると自動で積まれます。',
    '棚があふれたら失敗。上の「NEXT」でトラックの順番を確認しよう。',
  ]),
  'chain': Tutorial('連鎖出荷', [
    'トラックが出荷 → 次のトラックが棚から荷物を積む → また満タンで出荷…',
    'これが「連鎖」！ 連鎖するほど高得点です。',
    '棚に荷物をためておいて、一気に連鎖させよう。',
  ]),
  'queue': Tutorial('順番を読む', [
    'トラックは「NEXT」の順に来ます。',
    'どのレーンから崩すか、先を読んで選ぶのがコツ。',
    '困ったら「戻す」で1手やりなおせます。',
  ]),
  'hidden': Tutorial('見えない荷物', [
    '「?」の荷物は、一番上に来るまで色がわかりません。',
    '見えている荷物から確実に片付けよう。',
  ]),
  'lock': Tutorial('閉ざされたレーン', ['鍵のかかったレーンは、表示された台数を出荷すると開きます。']),
  'big': Tutorial('大型トラック', ['大型トラックは4個積めます。棚の使い方がより大切に。']),
  'hard': Tutorial('HARD', ['棚が少ない上級ステージです。', '★3の条件は「棚に置く回数」。最小手を目指してみよう。']),
};
