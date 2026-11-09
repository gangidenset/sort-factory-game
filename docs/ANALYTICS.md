# 分析・KPI設計

`lib/services/analytics/analytics.dart` の `Analytics` インターフェースに全イベントを送る。
現在は `DebugAnalytics`（ログ＋設定画面のDEBUG欄に直近20件）。Firebase Analytics 等を導入する場合は
`Analytics` を実装したクラスを作り、`main.dart` で `MultiAnalytics([DebugAnalytics(), FirebaseAnalyticsSink()])` に差し替えるだけでよい。

## 送信イベント

| イベント | パラメータ | 発火箇所 |
|---|---|---|
| `app_open` | `days_since_install`, `highest_stage` | 起動時 |
| `stage_start` | `stage`, `attempt` | プレイ開始 |
| `stage_clear` | `stage`, `score`, `stars`, `seconds`, `mistakes`, `revived` | クリア |
| `stage_fail` | `stage`, `reason`(mistakes/jam/timeUp/outOfMoves), `delivered`, `seconds` | 失敗を確定（リトライ/退出）した時 |
| `stage_retry` | `stage` | リトライ |
| `stage_quit` | `stage` | プレイ中に退出 |
| `revive` | `stage` | 復活成功 |
| `hint_used` | `stage` | ヒント獲得 |
| `rewarded_start` / `rewarded_complete` / `rewarded_fail` | `placement` | リワード広告 |
| `interstitial_shown` | `highest` | インタースティシャル表示 |
| `purchase_start` / `purchase_complete` / `purchase_restored` / `purchase_error` | `product` | 課金 |

## KPI の算出方法

| KPI | 算出 |
|---|---|
| DAU | `app_open` のユニークユーザー数/日 |
| D1 / D7 Retention | `app_open.days_since_install` が 1 / 7 のユーザー ÷ インストール数（端末内で install 日を保持） |
| 平均プレイ時間 | `stage_clear.seconds` + `stage_fail.seconds` の合計 / DAU（端末内累計は `PlayStats.totalPlaySeconds`） |
| ステージ到達率 | `stage_start` の `stage` 別ユニークユーザー数 ÷ 全ユーザー |
| ステージ別クリア率 | `stage_clear` ÷ `stage_start`（stage別） |
| リトライ率 | `stage_retry` ÷ `stage_start` |
| リワード視聴率 | `rewarded_complete` ÷ DAU（placement別） |
| インタースティシャル表示回数 | `interstitial_shown` / DAU |
| 課金率 | `purchase_complete` のユニークユーザー ÷ ユーザー |
| ARPDAU | （広告収益: AdMob管理画面 + 課金収益: ストア）÷ DAU |
| LTV | ARPDAU × 平均継続日数（リテンションカーブから推定） |

## 改善サイクル
1. ステージ別クリア率が 60% を下回るステージ → 目標数/出現間隔を緩める（stages.json）。
2. 失敗理由の偏り（例: jam が多い）→ 該当ステージのベルト容量/出現間隔を見直す。
3. D1 が低い → 序盤（1〜5）のプレイ時間・チュートリアルを短縮。
4. インタースティシャル後の離脱が多い → `interstitialEvery` / `graceStages` を緩める。

## プライバシー
- 送るのはゲーム内の数値のみ。氏名・メール・端末ID・自由入力文字列は送らない。
- 端末内統計はセーブデータ内のみに保持し、外部送信しない（現状）。
