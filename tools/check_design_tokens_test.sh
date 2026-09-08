#!/usr/bin/env bash
# tools/check_design_tokens.sh 自身の検出ロジックが壊れていないかを検証する自己テスト。
#
# 背景（Issue #58）: check_design_tokens.sh は検査対象ディレクトリ（TARGET_DIRS）と
#   allowlist（ALLOWLIST_DIR）がハードコードされており、フィクスチャを差し込んで
#   自己テストすることができなかった。しかも現在の main では NG ケースを一度も
#   踏んでいない（app/lib は main.dart と design/ のみ、packages/location/lib は
#   疎通確認用の1ファイルのみ）ため、PATTERN を丸ごと壊しても CI は常に green の
#   まま "PASSED" と出力し続けていた。Issue #50（check_import_direction.sh の
#   自己テスト欠如）とまったく同じ「静かに壊れるガード」の構造である。
#   この自己テストは NG/OK フィクスチャに対してスクリプトの exit code を検証し、
#   ガード自身の回帰を CI で検出できるようにする。
#
# .github/workflows/ci.yml からデザイントークンチェック本体の直前に実行する。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_SCRIPT="$REPO_ROOT/tools/check_design_tokens.sh"

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

# --- ケース1: Color(0xFF141610) は検出されるべき ---
NG_HEX="$WORKDIR/ng_hex/lib"
mkdir -p "$NG_HEX"
cat > "$NG_HEX/bad.dart" <<'DART'
const backgroundColor = Color(0xFF141610);
DART
bash "$CHECK_SCRIPT" "$NG_HEX" >/dev/null 2>&1
assert_exit "Color(0xFF141610) は検出される" 1 "$?"

# --- ケース2: Colors.red は検出されるべき ---
NG_COLORS="$WORKDIR/ng_colors/lib"
mkdir -p "$NG_COLORS"
cat > "$NG_COLORS/bad.dart" <<'DART'
const warningColor = Colors.red;
DART
bash "$CHECK_SCRIPT" "$NG_COLORS" >/dev/null 2>&1
assert_exit "Colors.red は検出される" 1 "$?"

# --- ケース3: Color.fromARGB(...) は検出されるべき ---
NG_ARGB="$WORKDIR/ng_argb/lib"
mkdir -p "$NG_ARGB"
cat > "$NG_ARGB/bad.dart" <<'DART'
const accentColor = Color.fromARGB(255, 20, 22, 16);
DART
bash "$CHECK_SCRIPT" "$NG_ARGB" >/dev/null 2>&1
assert_exit "Color.fromARGB(...) は検出される" 1 "$?"

# --- ケース4: Color.fromRGBO(...) は検出されるべき ---
NG_RGBO="$WORKDIR/ng_rgbo/lib"
mkdir -p "$NG_RGBO"
cat > "$NG_RGBO/bad.dart" <<'DART'
const accentColor = Color.fromRGBO(20, 22, 16, 1.0);
DART
bash "$CHECK_SCRIPT" "$NG_RGBO" >/dev/null 2>&1
assert_exit "Color.fromRGBO(...) は検出される" 1 "$?"

# --- ケース5: 同じリテラルでも design/ 配下（allowlist）なら通過するべき ---
# allowlist は渡されたルート基準で再解決される（"<root>/design"）ことの確認（Issue #58）。
OK_ALLOWLIST="$WORKDIR/ok_allowlist/lib"
mkdir -p "$OK_ALLOWLIST/design"
cat > "$OK_ALLOWLIST/design/color_tokens.dart" <<'DART'
const backgroundColor = Color(0xFF141610);
const warningColor = Colors.red;
const accentColor = Color.fromARGB(255, 20, 22, 16);
DART
bash "$CHECK_SCRIPT" "$OK_ALLOWLIST" >/dev/null 2>&1
assert_exit "design/ 配下の色リテラルは allowlist で通過する（ルート基準で再解決）" 0 "$?"

# --- ケース6: Theme.of(context).colorScheme.primary のみなら誤検出しない ---
OK_THEME="$WORKDIR/ok_theme/lib"
mkdir -p "$OK_THEME"
cat > "$OK_THEME/good.dart" <<'DART'
final color = Theme.of(context).colorScheme.primary;
DART
bash "$CHECK_SCRIPT" "$OK_THEME" >/dev/null 2>&1
assert_exit "Theme.of(context).colorScheme.primary のみは通過する" 0 "$?"

# --- ケース7: 文字列リテラルの色（"#141610" 等）はスコープ外として通過する ---
# MapLibre スタイル JSON 等に渡す文字列色はスコープ外であることを意図的に固定する。
OK_STRING="$WORKDIR/ok_string/lib"
mkdir -p "$OK_STRING"
cat > "$OK_STRING/good.dart" <<'DART'
const backgroundHex = "#141610";
DART
bash "$CHECK_SCRIPT" "$OK_STRING" >/dev/null 2>&1
assert_exit "文字列リテラルの色（\"#141610\"）はスコープ外として通過する" 0 "$?"

# --- ケース8: 検査対象ディレクトリが丸ごと存在しない場合は SKIP して exit 0 ---
bash "$CHECK_SCRIPT" "$WORKDIR/does_not_exist" >/dev/null 2>&1
assert_exit "対象ディレクトリ不在時は SKIP して exit 0" 0 "$?"

# --- ケース9: 複数ディレクトリを引数で渡せる（現行デフォルトの2ディレクトリ走査を検証） ---
# 単一引数だと「複数ディレクトリを走査する」挙動そのものを自己テストできないため、
# 可変長引数で複数ルートを受け取れることを固定する（Issue #58 代表回答）。
MULTI_CLEAN_A="$WORKDIR/multi_clean_a/lib"
MULTI_CLEAN_B="$WORKDIR/multi_clean_b/lib"
mkdir -p "$MULTI_CLEAN_A" "$MULTI_CLEAN_B"
cat > "$MULTI_CLEAN_A/good.dart" <<'DART'
final color = Theme.of(context).colorScheme.primary;
DART
cat > "$MULTI_CLEAN_B/good.dart" <<'DART'
final color = Theme.of(context).colorScheme.secondary;
DART
bash "$CHECK_SCRIPT" "$MULTI_CLEAN_A" "$MULTI_CLEAN_B" >/dev/null 2>&1
assert_exit "複数ディレクトリを引数で渡せる（両方クリーンなら exit 0）" 0 "$?"

# --- ケース10: 複数ディレクトリのうち2つ目に違反があっても検出される ---
MULTI_NG_A="$WORKDIR/multi_ng_a/lib"
MULTI_NG_B="$WORKDIR/multi_ng_b/lib"
mkdir -p "$MULTI_NG_A" "$MULTI_NG_B"
cat > "$MULTI_NG_A/good.dart" <<'DART'
final color = Theme.of(context).colorScheme.primary;
DART
cat > "$MULTI_NG_B/bad.dart" <<'DART'
const warningColor = Colors.red;
DART
bash "$CHECK_SCRIPT" "$MULTI_NG_A" "$MULTI_NG_B" >/dev/null 2>&1
assert_exit "複数ディレクトリの2つ目の違反も検出される" 1 "$?"

echo
if [ "$fail" -ne 0 ]; then
  echo "=== FAILED: tools/check_design_tokens.sh の自己テストが失敗しました ==="
  echo "  (このテストは Issue #58 の再発防止用: PATTERN が壊れても CI が green の"
  echo "   まま気づけない、というガード自身の検出漏れを CI で検出するためのもの)"
  exit 1
fi
echo "=== PASSED: tools/check_design_tokens.sh の自己テストは全て成功しました ==="
