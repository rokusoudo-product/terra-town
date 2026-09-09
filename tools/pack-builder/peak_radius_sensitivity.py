"""Issue #71: `natural=peak` バッファ半径（`terrain_rules.MOUNTAIN_PEAK_BUFFER_M`）の
感度分析の再現用スクリプト。

`specs/001-mvp/research.md` §8.9.3・`terrain_rules.py` の
「30m据え置き」判断根拠として使った実測値の再現用（`h3_resolution_survey.py` と
同じ位置づけの検証スクリプト。本体パイプラインの一部ではないため
`classify_terrain.py` からは呼ばれない）。

現行30mを含む複数の半径で `MOUNTAIN_PEAK_BUFFER_M` だけを変えて再分類し、
山ヘクス数の増分と、それに伴う森ヘクスの侵食数を比較する
（`MOUNTAIN_SUMMIT_POINT_RULES` に一致するのは今回の検証エリアでは
`natural=peak` の2点のみ。§8.9.1参照）。
"""

from __future__ import annotations

from pathlib import Path

import classify_terrain as ct
import config
import terrain_rules as rules
from local_projection import LocalProjection

HERE = Path(__file__).resolve().parent
INPUT = HERE / config.AREA_PBF_PATH


def main() -> None:
    lat0 = (config.BBOX_LAT_MIN + config.BBOX_LAT_MAX) / 2
    lon0 = (config.BBOX_LON_MIN + config.BBOX_LON_MAX) / 2
    proj = LocalProjection(lon0, lat0)

    grid_x, grid_y, lon, lat = ct.build_grid(proj)

    for radius in (30.0, 50.0, 75.0, 100.0, 150.0, 200.0):
        rules.MOUNTAIN_PEAK_BUFFER_M = radius
        buckets = ct.load_geometries(INPUT, proj)
        unioned = ct.union_buckets(buckets)
        cell_priority = ct.classify_cells(grid_x, grid_y, unioned)
        hex_result, _cell_rows = ct.aggregate_to_hexes(lon, lat, cell_priority)
        counts: dict[str, int] = {}
        for _hid, (ttype, _prio, _counter) in hex_result.items():
            counts[ttype] = counts.get(ttype, 0) + 1
        total = sum(counts.values())
        print(
            f"radius={radius:6.1f}m  mountain={counts.get('mountain', 0):5d} "
            f"forest={counts.get('forest', 0):5d} vacant_lot={counts.get('vacant_lot', 0):5d} "
            f"waterside={counts.get('waterside', 0):5d} total={total}"
        )


if __name__ == "__main__":
    main()
