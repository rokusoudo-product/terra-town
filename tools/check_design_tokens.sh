#!/usr/bin/env bash
# app/lib・packages/location/lib で、カラートークンを経由しない色リテラルの
# 直書きが無いことを検査する。
#
# 根拠: CLAUDE.md「UIは DESIGN.md に準拠する（カラーコード・サイズの直書き禁止、トークン経由）」
#       DESIGN.md「実装は本書のトークン・ルールに従い、カラーコード・サイズの直書きをしない」
#       app/lib/design/color_tokens.dart 冒頭コメント
#       app/lib/design/app_theme.dart 冒頭コメント
# 目的: tools/check_import_direction.sh と同じく「規約ではなく仕組みで守る」原則を
#       デザイントークンにも適用する（Issue #47）。
#
# スコープ: Dart の Color(0x...) / Colors.* / Color.fromARGB(...) / Color.fromRGBO(...)
#   リテラルのみを検出する。MapLibre のスタイル JSON 等に渡す "#141610" のような
#   文字列リテラルの色、およびサイズ・余白の数値リテラルは grep による機械判定が
#   困難なため対象外（将来必要になれば別Issueで拡張する）。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 検査対象ディレクトリ（存在しなければ SKIP）
TARGET_DIRS=(
  "$REPO_ROOT/app/lib"
  "$REPO_ROOT/packages/location/lib"
)

# トークン層のみリテラル定義を許可する allowlist。ここだけ検査対象から除外する。
ALLOWLIST_DIR="$REPO_ROOT/app/lib/design"

# Color(0x...) / Colors.xxx / Color.fromARGB(...) / Color.fromRGBO(...)
PATTERN='Color\(0x|Colors\.[A-Za-z]|Color\.fromARGB|Color\.fromRGBO'

fail=0
any_target_found=0

echo "== デザイントークン直書きチェック (Color(0x..) / Colors.* / Color.fromARGB / Color.fromRGBO) =="

for dir in "${TARGET_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then
    echo "SKIP: $dir がまだ存在しません"
    continue
  fi
  any_target_found=1

  hits=$(grep -rnE --include='*.dart' "$PATTERN" "$dir" \
          | grep -v -F "$ALLOWLIST_DIR/" || true)

  if [ -n "$hits" ]; then
    echo "NG: $dir に色リテラルの直書きがあります"
    echo "$hits"
    fail=1
  else
    echo "OK: $dir に直書きなし（$ALLOWLIST_DIR/ を除く）"
  fi
done

if [ "$any_target_found" -eq 0 ]; then
  echo "SKIP: 検査対象ディレクトリが1つも存在しません"
  exit 0
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "=== FAILED: デザイントークン直書きの違反あり ==="
  echo "対処: 色は app/lib/design/color_tokens.dart の ColorTokens を経由するか、"
  echo "      Theme.of(context)（colorScheme / semanticColors）経由で参照してください。"
  echo "      必要なトークンが未定義の場合は、DESIGN.md の更新とセットで"
  echo "      color_tokens.dart にトークンを新設してください。"
  exit 1
fi
echo "=== PASSED: 色リテラルの直書きはありません（$ALLOWLIST_DIR/ のトークン層を除く） ==="
