#!/usr/bin/env python3
"""tools/pack-builder/export_hex_geojson.py — T043 の受け入れ基準
（「各ヘクス Feature の直下に整数 `id` を持つ」）と、Issue #105 で追加した
`hex_terrain.boundary_geojson`（事前計算済みヘクス境界）の整合性を検証・可視化する
ためのリファレンス実装（Issue #85・#105）。

## 位置づけ（重要・Issue #105 で更新）

**本スクリプトの出力（GeoJSON ファイル）はパック本体の一部ではない**
（同梱するのは `hex_terrain` を含む SQLite 本体。`bundle_region_pack.sh` 参照）。

**旧記述（誤り・Issue #105 で訂正）**: 当初本コメントは「fog of war 用の GeoJSON
FeatureCollection は `location/`（tasks.md T056）が実行時に `hex_terrain` から
組み立てる（＝ Dart 側が H3 index から境界を計算する）」としていた。しかし
`packages/*/pubspec.yaml` に H3 の依存が実際には存在せず、この設計は絵に描いた餅
だったと Issue #105 で判明した。

**採用方式（2026-09-10 代表決定・Issue #105・案A）**: ヘクス境界の計算は
`tools/pack-builder/`（`hex_geometry.py`・本ファイルが依存する共通モジュール）が
パック生成時に1回だけ行い、`hex_terrain.boundary_geojson` 列に格納する。
`location/`（`packages/location/lib/src/map/`）は**格納済みの値を読むだけ**で
GeoJSON FeatureCollection を組み立てる（H3 ライブラリでの再計算はしない）。

本スクリプトはこの格納済みデータをもとに GeoJSON ファイルへ書き出す開発補助ツール
であり、あわせて「格納された境界」と「今この場で `hex_geometry.py` を使って
再計算した境界」が一致することを検証する（決定論の再確認。`verify_determinism.py`
は2回の生成物どうしを比較するのに対し、本スクリプトは「同じ関数を今呼び直しても
同じ結果になるか」という別角度の確認になる）。

## 何を検証しているか

- 各 Feature の **直下（`properties` の中ではない）** に整数 `id` を持つこと
  （`promoteId` は Android で機能しないため、これが必須 — plan.md §8・research.md §6.3）。
- `id` が `hex_terrain.feature_id` 列と一致すること。
- `id` に重複がないこと（`classify_terrain.py` の UNIQUE INDEX と整合）。
- `hex_id`（H3 index）は 2^53-1 を超えうるため、`properties` に含める場合は
  **文字列として**格納すること（JSON safe integer の範囲外。docs/terrain.md §4.4）。
  本スクリプトはその指針をそのまま実装している。
- **`hex_terrain.boundary_geojson` に格納された境界が、`hex_geometry.hex_boundary_lonlat`
  で今この場で再計算した境界と完全一致すること**（Issue #105 で追加）。

使い方:
    ./.venv/bin/python export_hex_geojson.py [--input out/pack.sqlite] [--out out/hex_features.geojson] [--limit N]
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

from hex_geometry import hex_boundary_lonlat

HERE = Path(__file__).resolve().parent


def log(msg: str) -> None:
    print(f"[export_hex_geojson] {msg}", file=sys.stderr, flush=True)


def build_feature_collection(
    rows: list[tuple[int, str, int, int, str]],
) -> dict:
    features = []
    seen_ids: set[int] = set()
    mismatches: list[int] = []

    for hex_id, terrain_type, feature_id, cell_count, boundary_geojson in rows:
        if not isinstance(feature_id, int):
            raise TypeError(f"feature_id は int である必要があります: {feature_id!r}")
        if feature_id in seen_ids:
            raise ValueError(f"feature_id の重複を検出しました: {feature_id}")
        seen_ids.add(feature_id)

        stored_ring = json.loads(boundary_geojson)
        recomputed_ring = hex_boundary_lonlat(hex_id)
        if stored_ring != recomputed_ring:
            mismatches.append(hex_id)

        features.append(
            {
                "type": "Feature",
                # ⚠️ ここが T043 の核心: Feature 直下（properties の外）に整数 id を持たせる。
                # promoteId（properties からの昇格）は Web 専用で Android では機能しない。
                "id": feature_id,
                # 事前計算済み（`classify_terrain.py` が書き込み済み）の境界を
                # そのまま使う。ここで境界を再計算しないのが Issue #105 の要点。
                "geometry": {"type": "Polygon", "coordinates": [stored_ring]},
                "properties": {
                    "terrain_type": terrain_type,
                    "cell_count": cell_count,
                    # hex_id（H3 index）は最大 2^63 未満で JSON safe integer(2^53-1)の
                    # 範囲を超えうるため、properties に含める場合は文字列で持たせる
                    # （docs/terrain.md §4.4）。feature_id への復元は
                    # hex_bridge.feature_id_to_h3() を使う（本スクリプトでは検証しない）。
                    "hex_id_str": str(hex_id),
                },
            }
        )

    if mismatches:
        raise ValueError(
            f"格納済み boundary_geojson と再計算結果が一致しないヘクスがあります "
            f"（{len(mismatches)}件、例: {mismatches[:5]}）。hex_geometry.py の実装、"
            f"または classify_terrain.py 実行時と h3-py のバージョンが変わっていないか確認してください。"
        )

    return {"type": "FeatureCollection", "features": features}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default=str(HERE / "out" / "pack.sqlite"))
    parser.add_argument("--out", default=str(HERE / "out" / "hex_features.geojson"))
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="出力するFeature数の上限（0=全件。動作確認用に少数だけ出したい場合に指定）",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    out_path = Path(args.out)

    if not input_path.exists():
        log(f"input not found: {input_path}. 先に classify_terrain.py を実行してください。")
        sys.exit(1)

    conn = sqlite3.connect(str(input_path))
    try:
        query = (
            "SELECT hex_id, terrain_type, feature_id, cell_count, boundary_geojson "
            "FROM hex_terrain ORDER BY hex_id"
        )
        if args.limit > 0:
            query += f" LIMIT {int(args.limit)}"
        rows = conn.execute(query).fetchall()
    finally:
        conn.close()

    if not rows:
        log("hex_terrain に行がありません。")
        sys.exit(1)

    log(f"{len(rows)} 件のヘクスを GeoJSON Feature に変換します ...")
    fc = build_feature_collection(rows)

    ids = [f["id"] for f in fc["features"]]
    assert all(isinstance(i, int) for i in ids), "すべての id は int であること（検証済みのはず）"
    assert len(ids) == len(set(ids)), "id に重複がないこと（検証済みのはず）"
    log(f"検証OK: 全{len(ids)}件で Feature 直下に整数 id（重複なし）を確認しました。")
    log(f"id の最大値: {max(ids)}（2^53-1 = 9007199254740991 未満であること: {max(ids) < 2**53 - 1}）")
    log(
        f"検証OK: 全{len(ids)}件で格納済み boundary_geojson が再計算結果と一致することを確認しました"
        "（Issue #105）。"
    )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(fc, f, ensure_ascii=False)

    log(f"書き出し完了: {out_path} ({out_path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
