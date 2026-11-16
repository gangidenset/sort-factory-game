# 分析・KPI設計

`lib/services/analytics/analytics.dart` の `Analytics` インターフェースに全イベントを送る。
現在は `DebugAnalytics`（ログ＋設定画面のDEBUG欄に直近20件）。Firebase Analytics 等を導入する場合は
`Analytics` を実装したクラスを作り、`main.dart` で `MultiAnalytics([DebugAnalytics(), FirebaseAnalyticsSink()])` に差し替えるだけでよい。

## 送信イベント

| イベント | パラメータ | 発火箇所 |
|---|---|---|
| `app_open` | `days_since_install`, `highest_stage` | 起動時 |
| `stage_start` | `stage`, `attempt` | プレイ開始 |
| `stage_clear` | `stage`, `stars`, `hints`, `moves`, `seconds` | クリア（フィナーレ後） |
| `daily_start` | `day`, `attempt` | 今日のパズル開始 |
| `daily_clear` | `day`, `hints`, `seconds`, `streak`, `first` | 今日のパズルをクリア |
| `daily_share` | `day` | 結果をコピー |
| `stage_retry` | `stage` | リトライ |
| `stage_quit` | `stage`, `placed`, `seconds` | 解かずに退出（＝詰まった指標） |
| `hint_used` | `stage`, `n` | ヒント使用 |
| `rewarded_start` / `rewarded_complete` / `rewarded_fail` | `placement` | リワード広告 |
| `interstitial_shown` | `highest` | インタースティシャル表示 |
| `purchase_start` / `purchase_complete` / `purchase_restored` / `purchase_error` | `product` | 課金 |

## KPI の算出方法

| KPI | 算出 |
|---|---|
| DAU | `app_open` のユニークユーザー数/日 |
| D1 / D7 Retention | `app_open.days_since_install` が 1 / 7 のユーザー ÷ インストール数（端末内で install 日を保持） |
| 平均プレイ時間 | `stage_clear.seconds` + `stage_quit.seconds` の合計 / DAU |
| ステージ到達率 | `stage_start` の `stage` 別ユニークユーザー数 ÷ 全ユーザー |
| ステージ別クリア率 | `stage_clear` ÷ `stage_start`（stage別）。失敗がないので未クリア＝途中離脱 |
| リトライ率 | `stage_retry` ÷ `stage_start` |
| リワード視聴率 | `rewarded_complete` ÷ DAU（placement別） |
| インタースティシャル表示回数 | `interstitial_shown` / DAU |
| 課金率 | `purchase_complete` のユニークユーザー ÷ ユーザー |
| デイリー参加率 | `daily_start` のユニークユーザー ÷ DAU（習慣化の先行指標） |
| 連続日数の分布 | `daily_clear.streak` |
| ARPDAU | （広告収益: AdMob管理画面 + 課金収益: ストア）÷ DAU |
| LTV | ARPDAU × 平均継続日数（リテンションカーブから推定） |

## 改善サイクル
1. 途中離脱（`stage_quit`）やヒント使用が多いステージ → 盤面を小さくする・tier を下げる（gen_stages.py）。
2. クリア時間が極端に長いステージ → 並び順を後ろへ移す。
3. D1 が低い → 序盤（1〜5）のプレイ時間・チュートリアルを短縮。
4. インタースティシャル後の離脱が多い → `interstitialEvery` / `graceStages` を緩める。

## プライバシー
- 送るのはゲーム内の数値のみ。氏名・メール・端末ID・自由入力文字列は送らない。
- 端末内統計はセーブデータ内のみに保持し、外部送信しない（現状）。
