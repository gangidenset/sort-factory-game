/// All user-facing copy in one place to ease future localization (ARB).
library;

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

  /// Link appended to shared results (playtest URL until the store launch).
  static const shareUrl = 'https://gangidenset.github.io/sort-factory-game/';

  static const easy = 'EASY';
  static const normal = 'NORMAL';
  static const hard = 'HARD';
}

class Tutorial {
  const Tutorial(this.title, this.lines);
  final String title;
  final List<String> lines;
}

const tutorials = <String, Tutorial>{
  'basic': Tutorial('積み込みパズル', [
    'トラック1台に、箱を1つ。トラックの上下左右のどこかに置きます。',
    '外の数字は、その列・行に入る箱の数です。',
    'このステージは、光るマスを順番にタップするだけ。やりながら覚えよう！',
  ]),
  'count': Tutorial('自分で解いてみよう', [
    'ここからは自分で考えます。',
    '「0」の列・行には箱が入りません。薄い×はゲームが付けた「置けない」印です。',
    '困ったら「ヒント」。理由つきで次の一手を教えます（ここでは無料）。',
  ]),
  'touch': Tutorial('箱はくっつけない', [
    '箱どうしは、ななめでもくっつけられません。',
    '置けないマスをタップすると、理由が出ます。',
  ]),
  'pattern': Tutorial('ならびで決まる', [
    '空きが3マス並んでいて箱が2つなら、両はしで決まり！',
    '（まん中に置くと、もう1つが入らない）',
  ]),
  'whatif': Tutorial('もしもで考える', [
    '「もしここに箱を置いたら？」と1手先を考えます。',
    'どこかの数字が合わなくなるなら、そこは×です。',
  ]),
  'hard': Tutorial('HARD', [
    '8×8の大きな倉庫。これまでの考え方を組み合わせて解きます。',
    '必ず考えるだけで解けます。当てずっぽうは不要です。',
  ]),
};
