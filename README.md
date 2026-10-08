# 出面・日当くん

一人親方・少人数の職長向けの iOS アプリ（Flutter）。誰がどの日にどの現場に出たか（出面）をタップで付けて、月ごとに人工と日当を集計し、LINE 用テキスト・出面表 PDF・CSV で送る。

- Bundle ID: `jp.dezura.app` / Version 1.0.0 (1)
- 日本語 UI のみ、iPhone のみ、縦向きのみ
- データは端末内の JSON（`Documents/dezura_nittou/`）。アカウント・サーバーなし、広告なし
- 権限の利用目的文字列なし（カメラ・位置情報などは使わない）

## プラン

| | 無料 | プレミアム |
|---|---|---|
| 職人 | 2人まで | 無制限 |
| 現場 | 1か所まで | 無制限 |
| 出面・集計 | 今月のみ | 過去の月も |
| LINE 用テキスト | ○ | ○ |
| 出面表 PDF / CSV | プレビューのみ | 書き出し・共有 |

自動更新サブスクリプション（グループ「出面・日当くん Premium」）

- `jp.dezura.app.premium.monthly` ¥100 / 1か月
- `jp.dezura.app.premium.yearly` ¥1,200 / 1年

ローカル確認用の StoreKit 設定は `ios/Runner/Products.storekit`（Runner スキームに設定済み）。

## 構成

- `lib/models/records.dart` 職人・現場・出面（1人1日1件、日当は記録時点の値を保持）
- `lib/logic/summary.dart` 月集計、LINE 用テキスト、CSV
- `lib/services/pdf_report.dart` 出面表 PDF（A4 横）
- `lib/state/app_controller.dart` 状態・保存・プラン制限・購入
- `lib/services/store_purchase_gateway.dart` StoreKit（in_app_purchase）
- `docs/` GitHub Pages（サポート・プライバシー・利用規約）
- `store/metadata-ja.md` App Store 文案

## 開発

```sh
flutter pub get
flutter analyze
flutter test
```

ストア用スクリーンショット（デバッグビルドのみ有効な起動オプション）:

```sh
tool/seed_demo_data.py "$(xcrun simctl get_app_container booted jp.dezura.app data)/Documents"
flutter run -d <sim> --dart-define=SCREENSHOT=true --dart-define=SCREENSHOT_PREMIUM=true --dart-define=SCREENSHOT_TAB=0
xcrun simctl io booted screenshot ~/Downloads/dezura-screenshots-raw/01-calendar.png
```

`SCREENSHOT_TAB`: 0 出面 / 1 集計 / 10 出力（PDF プレビュー）/ 11 プレミアム。`SCREENSHOT=true` のときは日本の価格（¥100 / ¥1,200、1週間無料）を表示する撮影用の購入ゲートウェイを使い、購入はしない。リリースビルドではどれも無視される。まとめて撮るときは `tool/capture_app_store_screenshots.sh`。
