#!/usr/bin/env python3
"""H3の各解像度の平均対辺・実測対辺を算出し、docs/terrain.md §3の「対辺 約50m」に
最も近い解像度を選ぶための実測スクリプト（Issue #38・2026-09-08）。

推測ではなく実際に計算・実測して比較する（代表指示）。
結果は docs/terrain.md §3.1・specs/001-mvp/research.md §8.2 に転記済み。

使い方:
    ./.venv/bin/python h3_resolution_survey.py
"""

from __future__ import annotations

import math

import h3

# 対象エリア（config.py の bbox）の中心座標そのもの。
CENTER_LAT = (35.7675 + 35.8125) / 2  # config.BBOX_LAT_MIN/MAX の中点
CENTER_LON = (139.352 + 139.408) / 2  # config.BBOX_LON_MIN/MAX の中点


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """WGS84の平均半径に基づく測地距離（メートル）。H3のドキュメントもこの半径を使用。"""
    R = 6371008.8
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlambda / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


def measured_opposite_side_m(cell: str) -> float | None:
    """指定セルの境界（6頂点）から、対辺（向かい合う辺）の中点間距離の平均を求める。

    五角形セル（H3全体で12個だけ存在する特殊セル）の場合は対辺の概念が単純ではないため
    None を返す（本調査では代表点が五角形セルに当たった解像度が1件あった。下記表の
    res=1 の nan がそれ）。
    """
    boundary = h3.cell_to_boundary(cell)
    n = len(boundary)
    if n != 6:
        return None
    dists = []
    for i in range(3):
        lat_a1, lon_a1 = boundary[i]
        lat_a2, lon_a2 = boundary[(i + 1) % n]
        lat_b1, lon_b1 = boundary[(i + 3) % n]
        lat_b2, lon_b2 = boundary[(i + 4) % n]
        mid_a = ((lat_a1 + lat_a2) / 2, (lon_a1 + lon_a2) / 2)
        mid_b = ((lat_b1 + lat_b2) / 2, (lon_b1 + lon_b2) / 2)
        dists.append(haversine_m(mid_a[0], mid_a[1], mid_b[0], mid_b[1]))
    return sum(dists) / len(dists)


def main() -> None:
    print(f"{'res':>3} {'avg_edge_m':>12} {'avg_opposite_m':>16} {'measured_opposite_m':>20} {'|diff_from_50m|':>16}")
    results = []
    for res in range(16):
        avg_edge = h3.average_hexagon_edge_length(res, unit="m")
        avg_opposite = avg_edge * math.sqrt(3)
        cell = h3.latlng_to_cell(CENTER_LAT, CENTER_LON, res)
        measured = measured_opposite_side_m(cell)
        diff = abs(measured - 50.0) if measured is not None else float("nan")
        results.append((res, avg_edge, avg_opposite, measured, diff))
        measured_str = f"{measured:20.4f}" if measured is not None else f"{'(pentagon cell: N/A)':>20}"
        diff_str = f"{diff:16.4f}" if measured is not None else f"{'n/a':>16}"
        print(f"{res:>3} {avg_edge:12.4f} {avg_opposite:16.4f} {measured_str} {diff_str}")

    valid = [r for r in results if r[3] is not None]
    best = min(valid, key=lambda r: r[4])
    print()
    print(
        f"50mに最も近い解像度: res={best[0]}  実測対辺={best[3]:.4f}m  "
        f"平均理論対辺={best[2]:.4f}m  差={best[4]:.4f}m"
    )


if __name__ == "__main__":
    main()
