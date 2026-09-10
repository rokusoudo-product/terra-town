"""tools/pack-builder/hex_geometry.py — H3セル境界（六角形ポリゴン）の座標算出（Issue #105）。

## 背景（Issue #105・2026-09-10 代表決定・案A）

fog of war 用の GeoJSON FeatureCollection を組み立てるには、各ヘクスの六角形境界
（緯度経度の座標列）が必要である。`export_hex_geojson.py`（Issue #85・T043）は
当初「`location/` が実行時に H3 index から境界を計算する」という設計を前提に、
検証用のリファレンス実装として境界計算ロジックを持っていたが、実際には Dart 側に
その実装が存在せず、fog of war が実データで動かせないことが判明した（Issue #105）。

代表決定（2026-09-10・案A）により、**境界計算は `tools/pack-builder/`（本ファイル）が
パック生成時に1回だけ行い、`hex_terrain.boundary_geojson` 列に格納する**方式を採る。
`location/` は計算せず、格納された値を読むだけにする（決定論の担保・実行時コスト削減。
理由の全文は Issue #105 の代表決定コメント参照）。

本モジュールは `classify_terrain.py`（パック生成本体。境界の書き込み元）と
`export_hex_geojson.py`（格納済みの値との再計算一致を確認する検証ツール）の
**両方から呼ばれる共通実装**にすることで、二重実装によるドリフトを防ぐ。

## 座標の丸め（圧縮ではない）

小数点以下7桁に丸める。これは「圧縮」ではなく、`extract_districts.py`
（`district.geometry_geojson`）が既に採用している精度に合わせただけである
（README「出力（`out/districts.sqlite`）のテーブル構成」参照）。7桁は約1.1cm相当の
精度であり、H3解像度11の対辺実測47.68m（docs/terrain.md §3.1）に対して十分細かい。
"""

from __future__ import annotations

import h3

# 座標の丸め桁数（`extract_districts.py` の `district.geometry_geojson` と揃える）。
COORDINATE_DECIMALS = 7


def hex_boundary_lonlat(h3_index_int: int) -> list[list[float]]:
    """H3 セルの境界を GeoJSON Polygon 用の [lon, lat] 座標配列（閉環）にする。

    始点=終点になるよう最後に先頭座標を複製する（GeoJSON Polygon の要件）。
    座標は [COORDINATE_DECIMALS] 桁に丸める（上記モジュール docstring 参照）。
    """
    h3_str = h3.int_to_str(h3_index_int)
    boundary = h3.cell_to_boundary(h3_str)  # [(lat, lon), ...]
    ring = [
        [round(lon, COORDINATE_DECIMALS), round(lat, COORDINATE_DECIMALS)]
        for lat, lon in boundary
    ]
    ring.append(ring[0])
    return ring
