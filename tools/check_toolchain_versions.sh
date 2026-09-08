#!/usr/bin/env bash
# .github/workflows/ci.yml と docs/dev-setup.md §2 の Flutter/JDK バージョンが
# 乖離していないかを検査する。
#
# 背景（Issue #59）: Flutter/JDK のバージョンが ci.yml と docs/dev-setup.md §2 の
#   二重管理になっており、同期が「人間の注意力」だけに委ねられていた。
#   両ファイルとも「相手も一緒に直してくれ」とコメントでお願いしているだけで、
#   守られなくても何も落ちない状態だった。本リポジトリが
#   tools/check_import_direction.sh（Issue #50）・tools/check_design_tokens.sh（Issue #58）
#   で確立した「規約ではなく仕組みで守る」という原則をここにも適用する。
#
# 正本（2026-09-07 代表決定。Issue #59 コメント参照）:
#   **`ci.yml` を正本（enforced value）とする。** docs/dev-setup.md §2 は
#   「実測値の記録」という位置づけだが、実際にビルドを縛っているのは ci.yml の
#   固定値であり、乖離時に直すべきは docs/dev-setup.md 側である。
#
# スコープ（2026-09-07 代表決定）: Flutter と JDK の2項目のみ。
#   Dart SDK 制約（各 pubspec.yaml の `sdk: ^3.12.2`）は検査対象に含めない。
#   Dart のバージョンは Flutter SDK に従属して決まるため、Flutter を固定すれば
#   実質的に縛られており、3つの pubspec を比較対象に足すとチェック自体の
#   保守コストが利得を上回ると判断された。
#
# 判定粒度:
#   - Flutter: 完全一致（例: 3.44.8）
#   - JDK    : メジャーバージョンの一致（ci.yml は "17"、dev-setup.md は
#              「OpenJDK 17.0.11（sdkman 管理）」と粒度が違うため）
#
# 抽出に失敗した場合（表の書式変更などでバージョンが取れない場合）は、
# 黙って PASS せず exit 1 にする（Issue #59 受け入れ基準）。
#
# 引数: 検査対象の ci.yml パス・dev-setup.md パス（この順）。
#   省略時はそれぞれ .github/workflows/ci.yml, docs/dev-setup.md。
#   tools/check_toolchain_versions_test.sh がフィクスチャファイルを渡して
#   自己テストするために差し替え可能にしてある
#   （tools/check_design_tokens.sh が Issue #58 で確立した設計に揃えた）。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CI_YAML="${1:-$REPO_ROOT/.github/workflows/ci.yml}"
DEV_SETUP="${2:-$REPO_ROOT/docs/dev-setup.md}"

fail=0

echo "== ツールチェーンバージョン整合性チェック（正本: ci.yml） =="

if [ ! -f "$CI_YAML" ]; then
  echo "NG: $CI_YAML が見つかりません"
  echo
  echo "=== FAILED: 抽出対象ファイルが見つかりません（黙って PASS しない） ==="
  exit 1
fi
if [ ! -f "$DEV_SETUP" ]; then
  echo "NG: $DEV_SETUP が見つかりません"
  echo
  echo "=== FAILED: 抽出対象ファイルが見つかりません（黙って PASS しない） ==="
  exit 1
fi

# --- ci.yml から抽出 ---
# 行頭からの空白の直後に key: "値" が続く行だけにマッチさせる。コメント行
# （例: "# flutter-version: ..." のように key 名にだけ言及する説明文）は
# 行頭が "#" になり `^[[:space:]]*flutter-version:` に一致しないため誤検出しない。
ci_flutter_line="$(grep -E '^[[:space:]]*flutter-version:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$CI_YAML" | head -n1 || true)"
ci_flutter="$(printf '%s\n' "$ci_flutter_line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"

ci_java_line="$(grep -E '^[[:space:]]*java-version:[[:space:]]*"[0-9]+"' "$CI_YAML" | head -n1 || true)"
ci_java_major="$(printf '%s\n' "$ci_java_line" | grep -oE '[0-9]+' | head -n1 || true)"

if [ -z "$ci_flutter" ]; then
  echo "NG: $CI_YAML から flutter-version の値を抽出できませんでした（書式変更の可能性）"
  fail=1
fi
if [ -z "$ci_java_major" ]; then
  echo "NG: $CI_YAML から java-version の値を抽出できませんでした（書式変更の可能性）"
  fail=1
fi

# --- docs/dev-setup.md §2 から抽出 ---
# §2 セクション（次の "## " 見出しの直前まで）に限定して抽出する。
section2="$(awk '/^## 2\./{flag=1; next} /^## /{flag=0} flag' "$DEV_SETUP")"

if [ -z "$section2" ]; then
  echo "NG: $DEV_SETUP から §2 セクションを抽出できませんでした（見出しの書式変更の可能性）"
  fail=1
fi

dev_flutter_line="$(printf '%s\n' "$section2" | grep -E '^\|[[:space:]]*Flutter[[:space:]]*\|' | head -n1 || true)"
dev_flutter="$(printf '%s\n' "$dev_flutter_line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"

dev_jdk_line="$(printf '%s\n' "$section2" | grep -E '^\|[[:space:]]*JDK[[:space:]]*\|' | head -n1 || true)"
dev_java_major="$(printf '%s\n' "$dev_jdk_line" | grep -oE 'OpenJDK[[:space:]]+[0-9]+' | grep -oE '[0-9]+' | head -n1 || true)"

if [ -z "$dev_flutter" ]; then
  echo "NG: $DEV_SETUP §2 の表から Flutter バージョンを抽出できませんでした（表の書式変更の可能性）"
  fail=1
fi
if [ -z "$dev_java_major" ]; then
  echo "NG: $DEV_SETUP §2 の表から JDK バージョンを抽出できませんでした（表の書式変更の可能性）"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo
  echo "=== FAILED: バージョン抽出に失敗しました（黙って PASS しない） ==="
  exit 1
fi

echo "$CI_YAML          : flutter-version=\"$ci_flutter\" / java-version=\"$ci_java_major\""
echo "$DEV_SETUP §2 : Flutter=$dev_flutter / JDK メジャーバージョン=$dev_java_major"
echo

# --- Flutter: 完全一致 ---
if [ "$ci_flutter" != "$dev_flutter" ]; then
  echo "NG: Flutter バージョンが一致しません"
  echo "  $CI_YAML          : $ci_flutter"
  echo "  $DEV_SETUP §2 : $dev_flutter"
  fail=1
else
  echo "OK: Flutter バージョン一致 ($ci_flutter)"
fi

# --- JDK: メジャーバージョンの一致 ---
if [ "$ci_java_major" != "$dev_java_major" ]; then
  echo "NG: JDK メジャーバージョンが一致しません"
  echo "  $CI_YAML          : $ci_java_major"
  echo "  $DEV_SETUP §2 : $dev_java_major"
  fail=1
else
  echo "OK: JDK メジャーバージョン一致 ($ci_java_major)"
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "=== FAILED: ci.yml と docs/dev-setup.md §2 のツールチェーンバージョンが乖離しています ==="
  echo "対処: 正本は ci.yml（enforced value）。docs/dev-setup.md §2 は実測値の記録であり、"
  echo "      乖離時は docs/dev-setup.md 側を ci.yml の値に合わせて修正してください。"
  exit 1
fi
echo "=== PASSED: ci.yml（正本）と docs/dev-setup.md §2 のツールチェーンバージョンは一致しています ==="
