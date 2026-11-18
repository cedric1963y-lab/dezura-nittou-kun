#!/usr/bin/env bash
# Simulator screenshots of the 1.0.7 flows. Debug build only.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$HOME/Downloads/dezura_107}"
BUNDLE=jp.dezura.app
mkdir -p "$OUT"
xcrun simctl list devices booted | grep -q Booted || { echo "boot a simulator first" >&2; exit 1; }
xcrun simctl status_bar booted override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true

build_for() {
  local tab=$1
  flutter build ios --simulator --debug --dart-define=SCREENSHOT=true \
    --dart-define=SCREENSHOT_PREMIUM=true --dart-define=SCREENSHOT_TAB="$tab"
  xcrun simctl terminate booted $BUNDLE 2>/dev/null || true
  xcrun simctl install booted build/ios/iphonesimulator/Runner.app
  local data
  data="$(xcrun simctl get_app_container booted $BUNDLE data)"
  python3 tool/seed_demo_data_v4.py "$data/Documents"
}

shot() {
  local name=$1 tab=$2
  build_for "$tab"
  xcrun simctl launch booted $BUNDLE >/dev/null
  sleep 10
  xcrun simctl io booted screenshot "$OUT/$name.png"
  sips -g pixelWidth -g pixelHeight "$OUT/$name.png" | tail -2
}

shot 01-area-site-dialog 12
shot 02-allowance-sheet 14
shot 03-summary-split 1
shot 04-toolbox 13
shot 05-expenses-sheet 15
shot 06-worker-pdf 16
echo "saved to $OUT"
