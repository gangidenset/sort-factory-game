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
    'トラック1台につき箱を1つ、上下左右のとなりのマスに置きます。',
    '外側の数字は、その行・列に入る箱の数です。',
    'マスをタップ：箱 → ×（箱なしのメモ）→ 消す。時間制限もミスの罰もありません。',
    '全部正しく置けたら、トラックがいっせいに出荷！',
  ]),
  'count': Tutorial('数字をよむ', [
    '「0」の行・列には箱が入りません。',
    '薄い×は「ここには置けない」とゲームが自動で付ける印です。',
    '残ったマスの数と、数字を見くらべてみましょう。',
  ]),
  'touch': Tutorial('となりあわない', [
    '箱どうしは、ななめでも隣り合えません。',
    '箱を1つ置くと、まわり8マスに薄い×が付きます。',
    '迷ったら「ヒント」。理由つきで次の一手を教えます（ここでは無料）。',
  ]),
  'pattern': Tutorial('ならびで決まる', [
    '数字ぴったりのマスが残っていなくても、決まる場所があります。',
    '例：3マス並んだ空きに箱2つ → 両はしで確定（まん中に置くと入りきらない）。',
  ]),
  'whatif': Tutorial('もしもの推理', [
    '「もしここに箱を置いたら？」と1〜2手先を考えます。',
    'どこかの数字が合わなくなるなら、そこは×で確定です。',
  ]),
  'hard': Tutorial('HARD', [
    '8×8の大きな倉庫。これまでの推理を組み合わせて解きます。',
    '必ず論理だけで解けます。当てずっぽうは不要です。',
  ]),
};
