# 収益化設計

## 方針
- 主収益 = 広告（リワード中心）、副収益 = 買い切り課金（広告削除が主力）。
- 「遊びを止める広告」は最小限。広告はすべて **自然な区切り** か **ユーザーが選んだ時** だけ。
- 広告・課金が失敗してもゲームは必ず続行できる（全API呼び出しは例外を投げず `false` を返す）。

## 1. リワード広告（任意視聴）

| 配置 | タイミング | 報酬 | 実装 |
|---|---|---|---|
| 復活 | 失敗画面 | 致命的な1手を取り消し＋棚+1（1プレイ1回） | `GameSession.revive()` |
| コイン2倍 | クリア画面 | 獲得コインをもう1回分 | `ProgressController.addCoins` |
| ヒント | プレイ中のHUDボタン（ステージ1〜3は無料） | ソルバーの解の次の1手（レーン）を光らせる | `Solver.hint` |
| 戻す | HUDボタン（無料1回/ステージを使い切った後） | 1手戻す | `GameSession.undo(paid: true)` |
| 特別報酬 | （予約: `RewardPlacement.dailyBonus`） | デイリーボーナス等 | 未使用 |

広告が読み込めていない場合、復活・2倍ボタンは表示しない（押してから失敗させない）。

## 2. インタースティシャル

`lib/services/ads/interstitial_policy.dart`（純ロジック・テスト済み）

| ルール | 初期値 | 調整方法 |
|---|---|---|
| 猶予 | 最初の5ステージをクリアするまで出さない | `InterstitialPolicy.graceStages` |
| 頻度 | 4クリアごと | ユーザー設定: 標準4 / 少6 / 最少8 |
| 最短間隔 | 180秒（アプリ起動直後も180秒は出さない） | `InterstitialPolicy.minInterval` |
| 広告削除購入者 | 出さない | `remove_ads` エンタイトルメント |
| 表示位置 | クリア画面から「次へ／リトライ／ステージ選択」を押した直後のみ | `AdManager.onStageClearBreak()` |

プレイ中・操作中・失敗直後には呼ばれない。値はすべて仮説。将来は Remote Config で A/B テストできるよう、ポリシーはコンストラクタ引数で差し替え可能。

## 3. バナー
使用しない（ゲーム画面を狭めるため）。

## 4. 広告IDの管理（ソースに埋め込まない）

| 種類 | 注入方法 | 未指定時 |
|---|---|---|
| 広告ユニットID | `--dart-define=ADMOB_REWARDED_ANDROID=...` 等（4種） | debug/profile: Googleの公開テストID / release: 広告無効 |
| AdMob App ID (Android) | `-PADMOB_APP_ID_ANDROID=...`（gradle property） | Googleの公開テストApp ID |
| AdMob App ID (iOS) | `ios/Flutter/AdMob.local.xcconfig`（git管理外）に `ADMOB_APP_ID_IOS = ...` | Googleの公開テストApp ID |
| テスト強制 | `--dart-define=USE_TEST_ADS=true` | |

設定画面のDEBUG欄（debugビルドのみ）で、現在 TEST/PROD/無効 のどれかを確認できる。

## 5. 同意・プライバシー
- **UMP（User Messaging Platform）**: 起動時に同意情報を更新し、必要な地域（EEA/UK等）では同意フォームを表示。`canRequestAds` が true の場合のみSDK初期化。最大8秒で打ち切り、起動をブロックしない。
- **プライバシーオプション**: 必要な地域では設定画面に「プライバシー設定（広告の同意）」を表示。
- **iOS ATT**: `NSUserTrackingUsageDescription` を設定済み。ATTダイアログはAdMob管理画面の「IDFA説明メッセージ」をUMPで配信する方式を推奨（アプリ側の追加実装不要）。
- **SKAdNetwork**: Google の `cstr6suwn9.skadnetwork` を登録済み。メディエーション導入時は各社IDを追加。
- **子ども向け**: 対象年齢は「13歳以上」想定。子ども向け（ファミリー）指定にする場合は `RequestConfiguration` の `tagForChildDirectedTreatment` 設定が必要。

## 6. アプリ内課金

`lib/services/iap/products.dart`

| 商品ID | 種類 | 参考価格 | 内容 | 状態 |
|---|---|---:|---|---|
| `remove_ads` | 非消耗型 | 600円 | インタースティシャル停止（リワードは任意で利用可） | **初回リリース対象** |
| `starter_pack` | 非消耗型 | 300円 | 1,500コイン + ミント工場スキン | 実装済・ストア登録待ち |
| `factory_skin_neon` | 非消耗型 | 150円 | 限定スキン「ネオン」 | 実装済・ストア登録待ち |
| `premium_pack` | 非消耗型 | 800円 | 広告削除 + ネオン + 3,000コイン | 実装済・ストア登録待ち |

- 表示価格は常にストアから取得（ハードコードしない）。
- 購入状態 = エンタイトルメント集合としてセーブに保存。**付与は冪等**（復元で同じ商品が届いてもコインは二重付与されない — テスト済み）。
- 「購入を復元」ボタンあり（iOS審査要件）。
- ストアに接続できない／商品未登録の場合は「購入できません」と表示し、**購入を偽装しない**。
- `Products.enabled` から外せば、その商品はUIから消える（初回リリースで広告削除だけにする場合）。

### 既知の制約（スケール前に対応）
- 購入レシートのサーバー検証なし（端末内で信頼）。不正対策として、売上が立ったら Cloud Functions 等で検証を追加する。
- 端末内エンタイトルメントは改ざん可能。高額商品を追加する前にサーバー検証を必須とする。
- 返金（Play の voided purchases）反映なし。

## 7. 収益モデルの初期仮説
- 想定 ARPDAU: リワード 0.5〜1回/DAU、インタースティシャル 1〜2回/DAU。
- 広告削除の購入率 0.5〜1%（ヘビーユーザー層）。
- KPI計測後、`interstitialEvery`・`graceStages`・復活回数を調整する（docs/ANALYTICS.md）。
