#!/usr/bin/env bash
# Simulator screenshots of the 1.0.8 flows. Debug build only.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$HOME/Downloads/dezura_108}"
BUNDLE=jp.dezura.app
DEV="${DEV:-C50205C2-CFB1-4C3C-B3E5-8E6704133DCE}"
mkdir -p "$OUT"
xcrun simctl boot "$DEV" 2>/dev/null || true
xcrun simctl status_bar "$DEV" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true

build_for() {
  local tab=$1
  flutter build ios --simulator --debug --dart-define=SCREENSHOT=true \
    --dart-define=SCREENSHOT_PREMIUM=true --dart-define=SCREENSHOT_TAB="$tab"
  xcrun simctl terminate "$DEV" $BUNDLE 2>/dev/null || true
  xcrun simctl install "$DEV" build/ios/iphonesimulator/Runner.app
  local data
  data="$(xcrun simctl get_app_container "$DEV" $BUNDLE data)"
  python3 tool/seed_demo_data_v4.py "$data/Documents"
}

shot() {
  local name=$1 tab=$2
  build_for "$tab"
  xcrun simctl launch "$DEV" $BUNDLE >/dev/null
  sleep 10
  xcrun simctl io "$DEV" screenshot "$OUT/$name.png"
  sips -g pixelWidth -g pixelHeight "$OUT/$name.png" | tail -2
}

shot 01-site-address-dialog 17
shot 02-units-chips 18
shot 03-summary-address 19
shot 04-worker-pdf-address 20
echo "saved to $OUT"
