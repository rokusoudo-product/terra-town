#!/usr/bin/env python3
"""Dart 側 `H3HexLocator`（`packages/location`・Issue #115）の検証用フィクスチャを生成する。

## 背景

`docs/terrain.md` §4 は「H3 は決定論的アルゴリズムであり、同一の実装世代（v4世代）
であれば言語が異なっても同じ緯度経度・同じ解像度から同じインデックス値が得られる」
としているが、これは仕様上の主張であって、本プロジェクトで Dart 側（`h3_flutter`）と
実際に突き合わせた実測ではなかった（Issue #115・Issue #107 2026-09-10 代表決定）。

本スクリプトは、生成側と同じ `h3-py`（`requirements.txt` で固定した 4.5.0）を使って
(緯度, 経度) -> hex_id の対応表を出力する。これを正として、Dart 側テスト
（`packages/location/test/position/hex_locator_h3_test.dart`）が `h3_flutter` の
出力と1点ずつ突き合わせる。

## 座標セットの選び方

1. 対象エリア（`config.py` の `BBOX_*`・狭山湖周辺。実際にパックを生成しているエリア）
   内から、固定シードの疑似乱数で `N_BBOX_POINTS` 点を抽出する。
   実際のゲームプレイで使われる範囲での一致を確認するのが目的。
2. 対象エリア外のグローバルな座標も少数含める（`EXTRA_GLOBAL_POINTS`）。
   H3 は全球インデックスであり `core` の `HexLocator` 抽象も特定エリアに限定されない
   ため、bbox 外でも一致することを確認する（極端な緯度・経度・日付変更線をまたぐ
   座標での変換の健全性チェックを兼ねる）。
3. `specs/001-mvp/research.md` §8.5 で実際に目視検証済みの座標（狭山湖の水面）も
   1点含める。既存の実測記録との整合を兼ねた重複確認。

## hex_id を文字列で出力する理由

H3 index は JSON の安全整数の上限（2^53-1 ≒ 9.007×10^15）を超えうる
（`specs/001-mvp/research.md` §8.4・実測最大値 626,833,456,793,083,903）。
本スクリプトの出力を何らかの JSON デコーダが数値としてそのまま読むと精度が
壊れる可能性があるため、`hex_id` は10進の**文字列**として出力する
（Dart 側テストは `BigInt.parse` で読む）。

## 再現手順

    cd tools/pack-builder
    ./.venv/bin/python generate_hex_locator_fixture.py \
        --out ../../packages/location/test/position/fixtures/h3_py_reference.json

出力ファイルは十分に小さい（点数は本スクリプトの `N_BBOX_POINTS` + `EXTRA_GLOBAL_POINTS`
の合計のみ。1点あたり数十バイト）。
"""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

import h3

import config

# tools/pack-builder/config.py の H3_RESOLUTION（=11。docs/terrain.md §3.1・§4.2）と
# 必ず一致させる。パック生成側とテスト対象を分離しないため、ここでは config.py の値を
# そのまま参照する（値を独自に持たない）。
RESOLUTION = config.H3_RESOLUTION

# 再現性のための固定シード（Issue番号+起票日から採った定数。値自体に意味はない）。
SEED = 20260911
N_BBOX_POINTS = 30

# 対象エリア（config.py の BBOX_*）外のグローバルな座標。
# (緯度, 経度) の順。
EXTRA_GLOBAL_POINTS: list[tuple[float, float]] = [
    (0.0, 0.0),  # 赤道・本初子午線
    (35.681236, 139.767125),  # 東京駅（実在の地名。デバッグ時に分かりやすくするため）
    (-33.868820, 151.209290),  # シドニー（南半球での確認）
    (64.135480, -21.895410),  # レイキャビク（高緯度での確認）
    # research.md §8.5 で実際にOSM実地図と突き合わせ済みの座標（狭山湖の水面）。
    # 既存の実測記録との重複確認を兼ねる。
    (35.777175, 139.407368),
    (79.9, 179.999),  # 日付変更線付近・高緯度
    (79.9, -179.999),  # 日付変更線をまたいだ反対側
]


def generate_points() -> list[tuple[float, float]]:
    rng = random.Random(SEED)
    points = [
        (
            rng.uniform(config.BBOX_LAT_MIN, config.BBOX_LAT_MAX),
            rng.uniform(config.BBOX_LON_MIN, config.BBOX_LON_MAX),
        )
        for _ in range(N_BBOX_POINTS)
    ]
    points.extend(EXTRA_GLOBAL_POINTS)
    return points


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        required=True,
        help="出力先JSONパス（例: ../../packages/location/test/position/fixtures/h3_py_reference.json）",
    )
    args = parser.parse_args()

    rows = []
    for lat, lon in generate_points():
        hex_str = h3.latlng_to_cell(lat, lon, RESOLUTION)
        hex_int = h3.str_to_int(hex_str)
        rows.append({"lat": lat, "lon": lon, "hex_id": str(hex_int)})

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    print(
        f"[generate_hex_locator_fixture] {len(rows)} 点を {out_path} に書き出しました"
    )
    print(
        f"[generate_hex_locator_fixture] h3=={h3.__version__} "
        f"resolution={RESOLUTION} seed={SEED} bbox_points={N_BBOX_POINTS} "
        f"global_points={len(EXTRA_GLOBAL_POINTS)}"
    )


if __name__ == "__main__":
    main()
