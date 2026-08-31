#!/usr/bin/env bash
# tools/check_import_direction.sh 自身の検出ロジックが壊れていないかを検証する自己テスト。
#
# 背景（Issue #50）: 依存方向チェックの正規表現がシングルクォートの import しか
#   検出できず、`import "package:terra_town_location/...";` のような二重引用符の
#   import をすり抜けていた。しかも自己テストが無かったため、正規表現が壊れても
#   CI は常に green のまま "PASSED" と出力し続けていた。
#   この自己テストは NG/OK フィクスチャに対してスクリプトの exit code を検証し、
#   ガード自身の回帰を CI で検出できるようにする。
#
# .github/workflows/ci.yml から依存方向チェック本体の直前に実行する。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_SCRIPT="$REPO_ROOT/tools/check_import_direction.sh"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

fail=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo "OK: $desc (exit $actual)"
  else
    echo "NG: $desc (expected exit $expected, got $actual)"
    fail=1
  fi
}

# --- ケース1: 禁止 import (シングルクォート) は検出されるべき ---
NG_SINGLE="$WORKDIR/ng_single"
mkdir -p "$NG_SINGLE/lib"
cat > "$NG_SINGLE/lib/bad.dart" <<'DART'
import 'package:terra_town_location/terra_town_location.dart';
DART
bash "$CHECK_SCRIPT" "$NG_SINGLE" >/dev/null 2>&1
assert_exit "禁止 import (シングルクォート) は検出される" 1 "$?"

# --- ケース2: 禁止 import (二重引用符) は検出されるべき ---（Issue #50 本体の穴）
NG_DOUBLE="$WORKDIR/ng_double"
mkdir -p "$NG_DOUBLE/lib"
cat > "$NG_DOUBLE/lib/bad.dart" <<'DART'
import "package:terra_town_location/terra_town_location.dart";
DART
bash "$CHECK_SCRIPT" "$NG_DOUBLE" >/dev/null 2>&1
assert_exit "禁止 import (二重引用符) は検出される" 1 "$?"

# --- ケース3: 禁止 export (二重引用符・export 形式) も検出されるべき ---
NG_EXPORT="$WORKDIR/ng_export"
mkdir -p "$NG_EXPORT/lib"
cat > "$NG_EXPORT/lib/bad.dart" <<'DART'
export "package:flutter/material.dart";
DART
bash "$CHECK_SCRIPT" "$NG_EXPORT" >/dev/null 2>&1
assert_exit "禁止 export (二重引用符) は検出される" 1 "$?"

# --- ケース4: 許可された import (両引用符・lib/test/bin/example/tool 全て) は通過するべき ---
OK_DIR="$WORKDIR/ok"
mkdir -p "$OK_DIR/lib" "$OK_DIR/test" "$OK_DIR/bin" "$OK_DIR/example" "$OK_DIR/tool"
cat > "$OK_DIR/lib/good.dart" <<'DART'
import 'package:terra_town_core/terra_town_core.dart';
import "dart:convert";
DART
cat > "$OK_DIR/test/good_test.dart" <<'DART'
import 'package:test/test.dart';
DART
cat > "$OK_DIR/bin/good.dart" <<'DART'
import 'package:terra_town_core/terra_town_core.dart';
DART
cat > "$OK_DIR/example/good.dart" <<'DART'
import "package:terra_town_core/terra_town_core.dart";
DART
cat > "$OK_DIR/tool/good.dart" <<'DART'
import 'package:terra_town_core/terra_town_core.dart';
DART
bash "$CHECK_SCRIPT" "$OK_DIR" >/dev/null 2>&1
assert_exit "許可された import (package:terra_town_core 等) は通過する" 0 "$?"

# --- ケース5: bin/example/tool への検査対象拡大の確認（lib/test 以外での検出） ---
NG_TOOL="$WORKDIR/ng_tool"
mkdir -p "$NG_TOOL/lib" "$NG_TOOL/tool"
cat > "$NG_TOOL/tool/bad.dart" <<'DART'
import "package:flutter/material.dart";
DART
bash "$CHECK_SCRIPT" "$NG_TOOL" >/dev/null 2>&1
assert_exit "tool/ 配下の禁止 import も検出される（検査対象拡大の確認）" 1 "$?"

# --- ケース6: 対象ディレクトリが丸ごと存在しない場合は従来どおり SKIP して exit 0 ---
bash "$CHECK_SCRIPT" "$WORKDIR/does_not_exist" >/dev/null 2>&1
assert_exit "core ディレクトリ不在時は SKIP して exit 0" 0 "$?"

echo
if [ "$fail" -ne 0 ]; then
  echo "=== FAILED: tools/check_import_direction.sh の自己テストが失敗しました ==="
  echo "  (このテストは Issue #50 の再発防止用: シングルクォートしか検出できない"
  echo "   正規表現の穴のような、ガード自身の検出漏れを CI で検出するためのもの)"
  exit 1
fi
echo "=== PASSED: tools/check_import_direction.sh の自己テストは全て成功しました ==="
