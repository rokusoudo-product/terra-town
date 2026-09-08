"""対象エリア中心を原点とする簡易等距円筒図法（ローカル平面近似）。

5km四方程度の狭い範囲では、正確な測地系変換（pyproj 等の追加依存）を持ち込まず、
緯度経度をメートル単位の直交座標に線形変換するだけで十分な精度が出る
（誤差は数km四方内でサブメートル〜数十cmオーダー）。

グリッドセルの敷き詰め・バッファ計算をメートル単位で行うために使う。
H3 index の算出（`h3.latlng_to_cell`）は最終的に本来の緯度経度に戻してから行う
（H3 は WGS84 緯度経度を前提とするライブラリのため、投影座標のまま渡してはならない）。
"""

from __future__ import annotations

import math

import numpy as np
import shapely

# WGS84 の子午線曲率半径に基づく近似定数（5km四方の局所投影としては十分な精度）。
METERS_PER_DEG_LAT = 111_320.0


class LocalProjection:
    def __init__(self, lon0: float, lat0: float):
        self.lon0 = lon0
        self.lat0 = lat0
        self.meters_per_deg_lon = METERS_PER_DEG_LAT * math.cos(math.radians(lat0))

    def to_xy(self, lon, lat):
        x = (np.asarray(lon) - self.lon0) * self.meters_per_deg_lon
        y = (np.asarray(lat) - self.lat0) * METERS_PER_DEG_LAT
        return x, y

    def to_lonlat(self, x, y):
        lon = self.lon0 + np.asarray(x) / self.meters_per_deg_lon
        lat = self.lat0 + np.asarray(y) / METERS_PER_DEG_LAT
        return lon, lat

    def project_geom(self, geom):
        """shapely 図形（lon,lat座標）をローカル平面座標（メートル）に変換する。"""

        def _tf(coords):
            coords = np.asarray(coords)
            x, y = self.to_xy(coords[:, 0], coords[:, 1])
            return np.column_stack([x, y])

        return shapely.transform(geom, _tf)

    def unproject_geom(self, geom):
        def _tf(coords):
            coords = np.asarray(coords)
            lon, lat = self.to_lonlat(coords[:, 0], coords[:, 1])
            return np.column_stack([lon, lat])

        return shapely.transform(geom, _tf)
