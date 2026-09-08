#!/usr/bin/env bash
# tools/check_toolchain_versions.sh 自身の検出ロジックが壊れていないかを検証する自己テスト。
#
# 背景（Issue #59）: check_import_direction.sh（Issue #50）・check_design_tokens.sh
#   （Issue #58）と同じく、CI で判定に使うガードには自己テストを必須とする方針の対象。
#   自己テストが無いと、抽出用の正規表現や §2 セクションの切り出しロジックが
#   壊れても CI は常に green のまま "PASSED" と出力し続けてしまう
#   （＝「静かに壊れるガード」。この Issue の受け入れ基準の一つでもある）。
#   この自己テストは NG/OK フィクスチャに対してスクリプトの exit code を検証し、
#   ガード自身の回帰を CI で検出できるようにする。
#
# .github/workflows/ci.yml からツールチェーンバージョンチェック本体の直前に実行する。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_SCRIPT="$REPO_ROOT/tools/check_toolchain_versions.sh"

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

write_ci_yaml() {
  # $1: 出力先パス, $2: flutter-version の値（例: "3.44.8"）, $3: java-version の値（例: "17"）
  cat > "$1" <<CIYAML
name: CI
on: [push]
jobs:
  analyze-and-test:
    steps:
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "$3"
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: "$2"
CIYAML
}

write_dev_setup() {
  # $1: 出力先パス, $2: Flutter 行の表記, $3: JDK 行の表記
  cat > "$1" <<DEVSETUP
# terra-town — 開発環境セットアップ

## 1. インストール先の決定

本文省略。

## 2. 導入済みのバージョン（2026-07-30 時点の実測）

| 項目 | バージョン / パス |
|------|------------------|
| Flutter | $2 |
| Dart | 3.12.2 |
| JDK | $3 |

CI（\`.github/workflows/ci.yml\`）はこの表の Flutter / JDK バージョンを固定値として参照している。

## 3. セットアップ手順

本文省略。
DEVSETUP
}

# --- ケース1: Flutter 完全一致・JDK メジャーバージョン一致なら exit 0 ---
OK_CI="$WORKDIR/ok_ci.yml"
OK_DEV="$WORKDIR/ok_dev-setup.md"
write_ci_yaml "$OK_CI" "3.44.8" "17"
write_dev_setup "$OK_DEV" "3.44.8（channel stable）" "OpenJDK 17.0.11（sdkman 管理）"
bash "$CHECK_SCRIPT" "$OK_CI" "$OK_DEV" >/dev/null 2>&1
assert_exit "Flutter完全一致・JDKメジャー一致なら exit 0" 0 "$?"

# --- ケース2: Flutter が一致しない場合は exit 1 で、両ファイルの値が出力に含まれる ---
NG_FLUTTER_CI="$WORKDIR/ng_flutter_ci.yml"
NG_FLUTTER_DEV="$WORKDIR/ng_flutter_dev-setup.md"
write_ci_yaml "$NG_FLUTTER_CI" "3.44.8" "17"
write_dev_setup "$NG_FLUTTER_DEV" "3.44.9（channel stable）" "OpenJDK 17.0.11（sdkman 管理）"
out="$(bash "$CHECK_SCRIPT" "$NG_FLUTTER_CI" "$NG_FLUTTER_DEV" 2>&1)"
actual=$?
assert_exit "Flutter バージョン不一致は exit 1" 1 "$actual"
if printf '%s' "$out" | grep -q "3.44.8" && printf '%s' "$out" | grep -q "3.44.9"; then
  echo "OK: 出力に両ファイルの Flutter バージョン (3.44.8 / 3.44.9) が含まれる"
else
  echo "NG: 出力に両ファイルの Flutter バージョンが含まれていない"
  echo "$out"
  fail=1
fi

# --- ケース3: JDK メジャーバージョンが一致しない場合は exit 1 で、両ファイルの値が出力に含まれる ---
NG_JDK_CI="$WORKDIR/ng_jdk_ci.yml"
NG_JDK_DEV="$WORKDIR/ng_jdk_dev-setup.md"
write_ci_yaml "$NG_JDK_CI" "3.44.8" "17"
write_dev_setup "$NG_JDK_DEV" "3.44.8（channel stable）" "OpenJDK 21.0.1（sdkman 管理）"
out="$(bash "$CHECK_SCRIPT" "$NG_JDK_CI" "$NG_JDK_DEV" 2>&1)"
actual=$?
assert_exit "JDK メジャーバージョン不一致は exit 1" 1 "$actual"
if printf '%s' "$out" | grep -q "17" && printf '%s' "$out" | grep -q "21"; then
  echo "OK: 出力に両ファイルの JDK メジャーバージョン (17 / 21) が含まれる"
else
  echo "NG: 出力に両ファイルの JDK メジャーバージョンが含まれていない"
  echo "$out"
  fail=1
fi

# --- ケース4: JDK はマイナーバージョンの粒度差があっても一致とみなす ---
# ci.yml "17" と dev-setup.md "OpenJDK 17.0.11" は粒度が違うため、
# メジャーバージョンのみで判定することを固定する（Issue #59 本文の要求）。
# ケース1で既に検証済みだが、意図を明示するため単独ケースとしても残す。
OK_MINOR_CI="$WORKDIR/ok_minor_ci.yml"
OK_MINOR_DEV="$WORKDIR/ok_minor_dev-setup.md"
write_ci_yaml "$OK_MINOR_CI" "3.44.8" "17"
write_dev_setup "$OK_MINOR_DEV" "3.44.8（channel stable）" "OpenJDK 17.0.99（sdkman 管理）"
bash "$CHECK_SCRIPT" "$OK_MINOR_CI" "$OK_MINOR_DEV" >/dev/null 2>&1
assert_exit "JDK はマイナーバージョンが違ってもメジャー一致なら exit 0" 0 "$?"

# --- ケース4.5: key 名にだけ言及するコメント行があっても誤検出しない ---
# 実際に ci.yml へ「flutter-version: この値が正本（enforced value）...」という
# 説明コメントを追記した際、コメント行が先にマッチして本来の YAML キー
# （flutter-version: "3.44.8"）を読み損ね、抽出失敗になった実例の再発防止。
NG_COMMENT_CI="$WORKDIR/comment_ci.yml"
cat > "$NG_COMMENT_CI" <<'CIYAML'
name: CI
on: [push]
jobs:
  analyze-and-test:
    steps:
      # JDK: この値が正本（enforced value）。java-version: の説明文コメント。
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"
      # flutter-version: この値が正本（enforced value）。実際のキーより先に出てくる説明文。
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: "3.44.8"
CIYAML
OK_DEV_COMMENT="$WORKDIR/comment_dev-setup.md"
write_dev_setup "$OK_DEV_COMMENT" "3.44.8（channel stable）" "OpenJDK 17.0.11（sdkman 管理）"
bash "$CHECK_SCRIPT" "$NG_COMMENT_CI" "$OK_DEV_COMMENT" >/dev/null 2>&1
assert_exit "key 名に言及するだけのコメント行があっても実際の値を正しく抽出できる" 0 "$?"

# --- ケース5: ci.yml に flutter-version が無い（抽出失敗）は exit 1 ---
NG_EXTRACT_CI="$WORKDIR/ng_extract_ci.yml"
cat > "$NG_EXTRACT_CI" <<'CIYAML'
name: CI
on: [push]
jobs:
  analyze-and-test:
    steps:
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"
CIYAML
OK_DEV2="$WORKDIR/ok_dev2.md"
write_dev_setup "$OK_DEV2" "3.44.8（channel stable）" "OpenJDK 17.0.11（sdkman 管理）"
bash "$CHECK_SCRIPT" "$NG_EXTRACT_CI" "$OK_DEV2" >/dev/null 2>&1
assert_exit "ci.yml に flutter-version が無い（抽出失敗）は exit 1" 1 "$?"

# --- ケース6: dev-setup.md の §2 見出しが無い（抽出失敗）は exit 1 ---
NG_SECTION_DEV="$WORKDIR/ng_section_dev-setup.md"
cat > "$NG_SECTION_DEV" <<'DEVSETUP'
# terra-town — 開発環境セットアップ

## 1. インストール先の決定

本文省略。

## 導入済みのバージョン

| 項目 | バージョン / パス |
|------|------------------|
| Flutter | 3.44.8（channel stable） |
| JDK | OpenJDK 17.0.11（sdkman 管理） |
DEVSETUP
OK_CI2="$WORKDIR/ok_ci2.yml"
write_ci_yaml "$OK_CI2" "3.44.8" "17"
bash "$CHECK_SCRIPT" "$OK_CI2" "$NG_SECTION_DEV" >/dev/null 2>&1
assert_exit "dev-setup.md の §2 見出しが無い（抽出失敗）は exit 1" 1 "$?"

# --- ケース7: dev-setup.md §2 の表に Flutter/JDK 行が無い（表の書式変更・抽出失敗）は exit 1 ---
NG_TABLE_DEV="$WORKDIR/ng_table_dev-setup.md"
cat > "$NG_TABLE_DEV" <<'DEVSETUP'
# terra-town — 開発環境セットアップ

## 2. 導入済みのバージョン（2026-07-30 時点の実測）

Flutter は 3.44.8 を使っている（表形式をやめた場合の想定）。

## 3. セットアップ手順
DEVSETUP
bash "$CHECK_SCRIPT" "$OK_CI2" "$NG_TABLE_DEV" >/dev/null 2>&1
assert_exit "dev-setup.md §2 の表が書式変更されている（抽出失敗）は exit 1" 1 "$?"

# --- ケース8: 検査対象ファイルが存在しない場合は exit 1（SKIP して exit 0 にはしない） ---
bash "$CHECK_SCRIPT" "$WORKDIR/does_not_exist_ci.yml" "$OK_DEV2" >/dev/null 2>&1
assert_exit "ci.yml が存在しない場合は exit 1" 1 "$?"
bash "$CHECK_SCRIPT" "$OK_CI2" "$WORKDIR/does_not_exist_dev-setup.md" >/dev/null 2>&1
assert_exit "dev-setup.md が存在しない場合は exit 1" 1 "$?"

echo
if [ "$fail" -ne 0 ]; then
  echo "=== FAILED: tools/check_toolchain_versions.sh の自己テストが失敗しました ==="
  echo "  (このテストは Issue #59 の受け入れ基準用: 抽出ロジックが壊れても CI が"
  echo "   green のまま気づけない、というガード自身の検出漏れを CI で検出するためのもの)"
  exit 1
fi
echo "=== PASSED: tools/check_toolchain_versions.sh の自己テストは全て成功しました ==="
