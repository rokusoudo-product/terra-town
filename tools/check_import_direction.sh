#!/usr/bin/env bash
# packages/core が location / Flutter / 地図SDK に依存していないことを検査する。
#
# 根拠: C:\Users\moets\.claude\GPS_ARCHITECTURE.md および specs/001-mvp/plan.md §1-D・§2
#   「core/（ゲームロジックの純粋な実装）は location/（GPS・地図）を import してはならない。
#     依存は常に location/ -> core/ の一方向」
# 目的: GPS まわりの実装を今後の GPS 利用アプリ間で使い回せる資産にすること。
#
# 規約ではなく仕組みで守るため、CI（.github/workflows/ci.yml）から実行し、
# 違反があれば exit 1 で落とす。
#
# Issue #50: シングルクォートのみを要求する正規表現だったため、
#   `import "package:terra_town_location/...";` のような二重引用符の import が
#   すり抜けていた。引用符スタイルに依存しない検出に修正済み。
#   このスクリプト自体の回帰は tools/check_import_direction_test.sh が検証する。
#
# 引数: 検査対象の core ディレクトリ（省略時は packages/core）。
#   tools/check_import_direction_test.sh がフィクスチャディレクトリを渡して
#   自己テストするために差し替え可能にしてある。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${1:-$REPO_ROOT/packages/core}"

if [ ! -d "$CORE_DIR" ]; then
  echo "SKIP: $CORE_DIR がまだ存在しません"
  exit 0
fi

fail=0

# --- 1. core のソースが禁止パッケージを import していないか ---
FORBIDDEN='package:terra_town_location|package:location|package:flutter/|package:maplibre|package:mapbox|package:google_maps|package:geolocator|dart:ui'

# 検査対象を lib/test だけでなく bin/example/tool にも広げる。
# 存在しないディレクトリは個別に SKIP する（黙って対象外になるのを防ぐため列挙する）。
SCAN_DIRS=()
for d in lib test bin example tool; do
  if [ -d "$CORE_DIR/$d" ]; then
    SCAN_DIRS+=("$CORE_DIR/$d")
  fi
done

echo "== 1. import チェック (packages/core: ${SCAN_DIRS[*]:-対象ディレクトリなし}) =="
if [ "${#SCAN_DIRS[@]}" -eq 0 ]; then
  echo "SKIP: 検査対象ディレクトリ(lib/test/bin/example/tool)が見つかりません"
else
  # シングルクォート('...')・二重引用符("...")のどちらの import/export もすり抜けないよう
  # ["'] で両方の引用符を許容する（Issue #50）。
  hits=$(grep -rnE "^[[:space:]]*(import|export)[[:space:]]+[\"']($FORBIDDEN)" \
          "${SCAN_DIRS[@]}" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "NG: packages/core が禁止パッケージを import/export しています"
    echo "$hits"
    fail=1
  else
    echo "OK: 禁止 import なし"
  fi
fi

# --- 2. pubspec の依存に禁止パッケージが入っていないか ---
echo
echo "== 2. pubspec 依存チェック (packages/core/pubspec.yaml) =="
PUBSPEC="$CORE_DIR/pubspec.yaml"
if [ -f "$PUBSPEC" ]; then
  # コメント行を除外したうえで、dependencies 配下の禁止依存を検出する
  dep_hits=$(grep -vE '^[[:space:]]*#' "$PUBSPEC" \
    | grep -nE '^[[:space:]]+(flutter|terra_town_location|location|maplibre[_a-z]*|mapbox[_a-z]*|google_maps[_a-z]*|geolocator)[[:space:]]*:' \
    || true)
  if [ -n "$dep_hits" ]; then
    echo "NG: packages/core/pubspec.yaml に禁止依存があります"
    echo "$dep_hits"
    fail=1
  else
    echo "OK: 禁止依存なし（core は純粋 Dart パッケージ）"
  fi
else
  echo "SKIP: pubspec.yaml が見つかりません"
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "=== FAILED: 依存方向の違反あり（location -> core の一方向を維持してください） ==="
  echo "対処: GPS/地図に関する処理は packages/location 側へ移し、"
  echo "      core 側にはインターフェース（抽象）だけを置いて依存注入してください。"
  exit 1
fi
echo "=== PASSED: 依存方向は location -> core の一方向です ==="
