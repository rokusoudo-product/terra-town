#!/usr/bin/env python3
"""
assets/*.svg を PNG にラスタライズするスクリプト（Issue #28）。

## 背景
`<use>` / `<defs>` / `clipPath` を正しく解釈できる変換器が必要（本リポジトリのSVGは
`<use>` を多用している）。2026-08-01 の検討で以下を確認・決定した:

- WSL(Ubuntu 24.04) には cairosvg / rsvg-convert / Inkscape / ImageMagick のいずれも未導入
- `sudo apt install libcairo2 libcairo-gobject2` は代表が導入済み
- system python3 は pip 非導入 + PEP 668 により直接 pip install できない
- → 本リポジトリ専用の venv（`tools/.venv`）に cairosvg を導入する（A案採用）

## venv セットアップ（再現手順。詳細は docs/dev-setup.md も参照）
    cd /home/zakis/terra-town   # リポジトリルート（WSLネイティブパス。/mnt/c/... にしない）
    python3 -m venv tools/.venv
    tools/.venv/bin/pip install --upgrade pip
    tools/.venv/bin/pip install cairosvg

## 使い方
    # デフォルト: assets/*.svg すべてを mipmap 5段階 + Play用512pxで生成
    tools/.venv/bin/python tools/rasterize_assets.py

    # 対象を絞る
    tools/.venv/bin/python tools/rasterize_assets.py --asset app-icon

    # 出力先を変える（デフォルトは build/rasterized/）
    tools/.venv/bin/python tools/rasterize_assets.py --out-dir /tmp/out
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import cairosvg
except ImportError:  # pragma: no cover
    sys.exit(
        "cairosvg が見つかりません。tools/.venv を作成し、\n"
        "  tools/.venv/bin/pip install cairosvg\n"
        "を実行してから、tools/.venv/bin/python 経由で本スクリプトを実行してください。\n"
        "（詳細: docs/dev-setup.md)"
    )

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS_DIR = REPO_ROOT / "assets"
DEFAULT_OUT_DIR = REPO_ROOT / "build" / "rasterized"

# Android mipmap 5段階（ic_launcher 用の一般的な密度別サイズ、48dp基準）+ Play掲載用 512px。
# 参照: https://developer.android.com/google-play/resources/icon-design-specifications
DENSITY_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
PLAY_STORE_SIZE = 512


def rasterize(svg_path: Path, out_path: Path, size: int) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    cairosvg.svg2png(
        url=str(svg_path),
        write_to=str(out_path),
        output_width=size,
        output_height=size,
    )
    print(f"  -> {out_path.relative_to(REPO_ROOT)} ({size}x{size})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("## 使い方")[0])
    parser.add_argument(
        "--asset",
        action="append",
        dest="assets",
        help="対象アセット名（拡張子なし。例: app-icon）。複数指定可。省略時は assets/*.svg 全て",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=DEFAULT_OUT_DIR,
        help=f"出力先ディレクトリ（デフォルト: {DEFAULT_OUT_DIR.relative_to(REPO_ROOT)}）",
    )
    parser.add_argument(
        "--play-store-only",
        action="store_true",
        help="Play掲載用 512px のみ生成し、mipmap 5段階は生成しない",
    )
    args = parser.parse_args()

    if args.assets:
        svg_paths = [ASSETS_DIR / f"{name}.svg" for name in args.assets]
        missing = [p for p in svg_paths if not p.exists()]
        if missing:
            for p in missing:
                print(f"エラー: {p} が見つかりません", file=sys.stderr)
            return 1
    else:
        svg_paths = sorted(ASSETS_DIR.glob("*.svg"))
        if not svg_paths:
            print(f"エラー: {ASSETS_DIR} に SVG が見つかりません", file=sys.stderr)
            return 1

    for svg_path in svg_paths:
        name = svg_path.stem
        print(f"{svg_path.relative_to(REPO_ROOT)}:")

        # Play ストア掲載用 512px
        rasterize(svg_path, args.out_dir / "play-store" / f"{name}.png", PLAY_STORE_SIZE)

        # mipmap 5段階
        if not args.play_store_only:
            for density, size in DENSITY_SIZES.items():
                rasterize(svg_path, args.out_dir / density / f"{name}.png", size)

    print("完了。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
