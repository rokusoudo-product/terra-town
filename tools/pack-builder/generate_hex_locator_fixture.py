#!/usr/bin/env python3
"""Kotlin 側 `H3HexIndexer`（`app/android/`・Issue #108）の検証用フィクスチャを生成する。

## 背景

`docs/terrain.md` §4 は「H3 は決定論的アルゴリズムであり、同一の実装世代（v4世代）
であれば言語が異なっても同じ緯度経度・同じ解像度から同じインデックス値が得られる」
としているが、これは仕様上の主張であって、本プロジェクトで実際に突き合わせた実測では
なかった（Issue #115・Issue #107 2026-09-10 代表決定）。

本スクリプトは、生成側と同じ `h3-py`（`requirements.txt` で固定した 4.5.0）を使って
(緯度, 経度) -> hex_id の対応表を出力する。これを正として、Kotlin 側テスト
（`app/android/app/src/test/kotlin/jp/rokusoudo/terra_town/location/H3HexIndexerTest.kt`）
が `com.uber:h3:4.5.0`（h3-java）の出力と1点ずつ突き合わせる。

【Issue #108・2026-09-11 追記】以前（Issue #115）は本フィクスチャは
`packages/location/test/position/fixtures/h3_py_reference.json` に置き、Dart側
`hex_locator_h3_test.dart`（`h3_flutter`）と突き合わせていた。緯度経度→H3の変換が
Kotlin側（`H3HexIndexer`）に移行したことに伴い、出力先を
`app/android/app/src/test/resources/h3_py_reference.json`（Kotlin の JVM 単体テストの
クラスパスリソース）に変更した。旧Dart側テスト・フィクスチャは撤去済み。

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
4. **（Issue #158）`--poi-sqlite`（既定 `out/poi.sqlite`。`extract_poi.py` の出力）が
   存在すれば、実際の名所POIの座標を全件追加する。** Issue #158の受け入れ基準
   「同じPOIについてPythonとKotlinで同じヘクスIDになることをテストで確認している」は、
   POIのヘクスID計算（`extract_poi.py`の`_hex_id_of`）が本フィクスチャの生成に使う
   `h3.latlng_to_cell(..., config.H3_RESOLUTION)`と全く同じ呼び出しであることを根拠に、
   新規のフィクスチャ機構を別途作らず本フィクスチャへ実POI座標を合流させる形で満たす
   （汎用の座標での一致を確認済みの機構に、対象を「実際のPOI座標」へ広げるだけでよい
   という判断。advisor 2026-09-13指摘）。既定パスが無い場合は0件として無視するが
   （フィクスチャ単体の再現手順の独立性を保つため）、明示的に`--poi-sqlite`を指定した
   場合はファイルが無ければエラーで停止する（黙って0件にすると気付かないため）。

## hex_id を文字列で出力する理由

H3 index は JSON の安全整数の上限（2^53-1 ≒ 9.007×10^15）を超えうる
（`specs/001-mvp/research.md` §8.4・実測最大値 626,833,456,793,083,903）。
本スクリプトの出力を何らかの JSON デコーダが数値としてそのまま読むと精度が
壊れる可能性があるため、`hex_id` は10進の**文字列**として出力する
（Kotlin 側テストは手書きの最小パーサで文字列のまま読み `Long.parseLong` する。
`org.json` は Android フレームワーク側にしかなく JVM 単体テストでは動かないため、
小さな依存を追加するより手書きの読み取りを選んだ。詳細は
`H3HexIndexerTest.kt`・PR #108 本文参照）。

## 再現手順

    cd tools/pack-builder
    ./.venv/bin/python generate_hex_locator_fixture.py \
        --out ../../app/android/app/src/test/resources/h3_py_reference.json

`--out` を省略した場合もこのパスが既定値として使われる。実POI座標も含めて
再現する場合は、先に `extract_poi.py` を実行して `out/poi.sqlite` を作ってから
本スクリプトを実行すること（`--poi-sqlite` も既定で `out/poi.sqlite` を見るため
追加のオプション指定は不要）。

出力ファイルは十分に小さい（点数は本スクリプトの `N_BBOX_POINTS` + `EXTRA_GLOBAL_POINTS`
の合計のみ。1点あたり数十バイト）。
"""

from __future__ import annotations

import argparse
import json
import random
import sqlite3
import sys
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


def load_poi_points(poi_sqlite_path: Path, explicitly_requested: bool) -> list[tuple[float, float]]:
    """`extract_poi.py`の出力（`out/poi.sqlite`）から実際のPOI座標を読み込む（Issue #158）。

    既定パスが存在しない場合は0件（本フィクスチャ単体の再現手順が`out/poi.sqlite`の
    存在に依存しないようにするため）。`--poi-sqlite`を明示的に指定したのに存在しない
    場合は、黙って0件にすると気付かないためエラーで停止する（本ファイルdocstring
    「座標セットの選び方」4項参照）。
    """
    if not poi_sqlite_path.exists():
        if explicitly_requested:
            print(
                f"[generate_hex_locator_fixture] --poi-sqlite に指定された "
                f"{poi_sqlite_path} が見つかりません。先に extract_poi.py を実行してください。",
                file=sys.stderr,
            )
            sys.exit(1)
        return []

    conn = sqlite3.connect(str(poi_sqlite_path))
    try:
        return [
            (float(lat), float(lon))
            for (lat, lon) in conn.execute("SELECT lat, lon FROM poi ORDER BY id")
        ]
    finally:
        conn.close()


DEFAULT_OUT = "../../app/android/app/src/test/resources/h3_py_reference.json"
DEFAULT_POI_SQLITE = "out/poi.sqlite"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        default=DEFAULT_OUT,
        help=f"出力先JSONパス（既定: {DEFAULT_OUT}）",
    )
    parser.add_argument(
        "--poi-sqlite",
        default=DEFAULT_POI_SQLITE,
        help=(
            f"実POI座標を追加で取り込む extract_poi.py の出力（既定: {DEFAULT_POI_SQLITE}。"
            "無指定で既定パスが無い場合は0件として無視。明示指定して無い場合はエラー）"
        ),
    )
    args = parser.parse_args()

    poi_sqlite_path = Path(args.poi_sqlite)
    explicitly_requested = args.poi_sqlite != DEFAULT_POI_SQLITE
    poi_points = load_poi_points(poi_sqlite_path, explicitly_requested)

    points = generate_points() + poi_points

    rows = []
    for lat, lon in points:
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
        f"global_points={len(EXTRA_GLOBAL_POINTS)} poi_points={len(poi_points)}"
        f"（{poi_sqlite_path if poi_points else '未使用'}）"
    )


if __name__ == "__main__":
    main()
