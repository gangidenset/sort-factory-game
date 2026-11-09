# リリース手順・公開準備チェックリスト

> 🔒 の項目はユーザー（事業者）の承認・アカウント・秘密情報が必要。開発側では実施しない。

## 1. 事前に決める事項 🔒
- [ ] 正式アプリ名・パッケージ名（現在 `com.sortfactory.sort_factory` は仮）
  - Android: `android/app/build.gradle.kts` の `namespace` / `applicationId`
  - iOS: Xcode の Bundle Identifier
- [ ] 開発者アカウント（Google Play Console / Apple Developer Program）
- [ ] AdMob アカウント、アプリ登録、広告ユニット（リワード・インタースティシャル × Android/iOS）
- [ ] プライバシーポリシーの公開URL・問い合わせ先

## 2. Android 本番ビルド
1. 署名鍵を作成（リポジトリ外で保管）し `android/key.properties` を作成（git管理外）:
   ```
   storePassword=...
   keyPassword=...
   keyAlias=upload
   storeFile=/絶対パス/upload-keystore.jks
   ```
2. ビルド:
   ```bash
   flutter build appbundle --release \
     -PADMOB_APP_ID_ANDROID=ca-app-pub-XXXX~YYYY \
     --dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-XXXX/AAAA \
     --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-XXXX/BBBB
   ```
   ※ `-P` は gradle プロパティ。`~/.gradle/gradle.properties` に `ADMOB_APP_ID_ANDROID=...` と書いてもよい。
3. Play Console: 内部テスト → クローズドテスト → 製品版。
4. アプリ内アイテム（MONETIZATION.md の商品ID）を登録し、ライセンステスターで購入テスト。

## 3. iOS 本番ビルド
1. `ios/Flutter/AdMob.local.xcconfig`（git管理外）を作成:
   ```
   ADMOB_APP_ID_IOS = ca-app-pub-XXXX~YYYY
   ```
2. ビルド:
   ```bash
   flutter build ipa --release \
     --dart-define=ADMOB_REWARDED_IOS=ca-app-pub-XXXX/CCCC \
     --dart-define=ADMOB_INTERSTITIAL_IOS=ca-app-pub-XXXX/DDDD
   ```
3. App Store Connect: 課金アイテム登録、Sandbox テスターで購入・復元テスト、TestFlight。
4. 審査用メモ: 「購入を復元」はショップ画面下部、広告削除後もリワード広告は任意で利用可能。

## 4. ストア申告
### Google Play データセーフティ（想定回答。SDKの最新ドキュメントで要確認）
- 収集: デバイスID等（広告ID）— AdMob SDK による、広告・分析目的、第三者と共有あり
- アプリ内の位置情報・個人情報・連絡先: 収集しない
- 購入履歴: Google Play が処理
- データの暗号化（送信時）: はい（SDK）
- 削除リクエスト: ローカルデータのみ（アプリ削除で消える）

### App Store「Appのプライバシー」
- トラッキングに使用されるデータ: 識別子（広告ID）— ATT許可時のみ
- 広告データ・診断データ（SDK由来）
- プライバシーマニフェスト: google_mobile_ads / 各SDK同梱の `PrivacyInfo.xcprivacy` を確認

### コンテンツレーティング
暴力・ギャンブル要素なし。広告ありとして申告。

## 5. リリース前QAチェックリスト
- [ ] `flutter analyze` 警告なし / `flutter test` 全件成功
- [ ] Android 実機（低価格端末含む 2台以上）、iOS 実機（SE系の小画面＋最新機種）
- [ ] 機内モードで起動・プレイ・保存ができる
- [ ] プレイ中にホームへ戻る → 自動ポーズ、復帰後に続行できる
- [ ] アプリを強制終了 → 進行・コイン・設定が残っている
- [ ] 広告: テストIDでリワード完了時のみ報酬、途中で閉じたら報酬なし、ロード失敗でもボタンが出ずゲーム続行
- [ ] インタースティシャル: ステージ1〜5で出ない、4クリアごと、180秒以内に連続しない、プレイ中に出ない
- [ ] 課金: 購入 → 即反映、アプリ再インストール → 復元で戻る、コイン二重付与なし
- [ ] EEA 地域（VPN等）で同意フォームが表示され、設定から変更できる
- [ ] 文字サイズ「大」設定でUIが崩れない

## 6. 素材
- [ ] アプリアイコン（1024×1024）— 現在はFlutter既定アイコン
- [ ] スクリーンショット（6.7"/6.5"/5.5" iPhone、Android 縦）
- [ ] フィーチャーグラフィック（1024×500）
- [ ] ストア説明文（短い説明80字・詳細説明）
