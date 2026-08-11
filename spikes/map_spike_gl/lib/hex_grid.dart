// 使い捨て検証ハーネス用の合成ヘクスグリッド生成。
//
// terra-town 本体（app/ packages/core）とは無関係。fog of war 性能計測（Issue #24 R2）用に
// 「歩いて開示していく」状況を模した穴あきポリゴンGeoJSONを作るための最小限のジオメトリ計算のみ。
//
// ヘクスサイズは docs/terrain.md §3「1ヘクスの対辺（辺と向かい合う辺の距離）は約50m」に準拠。
// 地域パック（実データ）はまだ存在しないため、緯度経度は合成（プログラム生成）。
// 実際のOSM地形データとの整合は取っていない。

import 'dart:math' as math;

/// 対辺50m相当のフラットトップ・ヘクス（circumradius に変換）。
/// flat-to-flat width = sqrt(3) * circumradius なので、逆算する。
const double kHexFlatToFlatMeters = 50.0;
final double kHexCircumradiusMeters =
    kHexFlatToFlatMeters / math.sqrt(3); // ≈ 28.87m

/// 合成データの中心地点（東京駅付近・実データとは無関係の仮の緯度経度）。
const double kOriginLat = 35.681236;
const double kOriginLng = 139.767125;

const double _metersPerDegLat = 111320.0;

class HexCenter {
  final int q;
  final int r;
  final double lat;
  final double lng;

  const HexCenter({
    required this.q,
    required this.r,
    required this.lat,
    required this.lng,
  });
}

/// axial 座標 (q, r) のヘクス中心を、原点からのメートルオフセットに変換し、
/// 緯度経度に変換する（フラットトップ配置）。
HexCenter _hexCenterAt(int q, int r) {
  final double x = kHexCircumradiusMeters * 1.5 * q;
  final double y = kHexCircumradiusMeters * math.sqrt(3) * (r + q / 2.0);
  final double metersPerDegLng =
      _metersPerDegLat * math.cos(kOriginLat * math.pi / 180.0);
  final double lat = kOriginLat + (y / _metersPerDegLat);
  final double lng = kOriginLng + (x / metersPerDegLng);
  return HexCenter(q: q, r: r, lat: lat, lng: lng);
}

/// 概ね count 個のヘクス中心を、原点近傍の矩形状（axial q/r 格子）に生成する。
/// 形状の見た目は重要でない（性能計測が目的）ため、単純な矩形グリッドでよい。
List<HexCenter> generateHexGrid(int count) {
  final int side = math.sqrt(count).ceil() + 1;
  final List<HexCenter> centers = [];
  outer:
  for (int r = -side ~/ 2; r <= side ~/ 2; r++) {
    for (int q = -side ~/ 2; q <= side ~/ 2; q++) {
      centers.add(_hexCenterAt(q, r));
      if (centers.length >= count) break outer;
    }
  }
  return centers;
}

/// フラットトップ・ヘクスの頂点リング（GeoJSON Polygon の1リング分・閉環）を
/// [lng, lat] のペア配列で返す。
List<List<double>> hexRing(HexCenter center) {
  final double metersPerDegLng =
      _metersPerDegLat * math.cos(kOriginLat * math.pi / 180.0);
  final List<List<double>> ring = [];
  for (int i = 0; i < 6; i++) {
    final double angleDeg = 60.0 * i;
    final double angleRad = angleDeg * math.pi / 180.0;
    final double dx = kHexCircumradiusMeters * math.cos(angleRad);
    final double dy = kHexCircumradiusMeters * math.sin(angleRad);
    final double lat = center.lat + (dy / _metersPerDegLat);
    final double lng = center.lng + (dx / metersPerDegLng);
    ring.add([lng, lat]);
  }
  ring.add(ring.first); // 閉環
  return ring;
}

/// 全ヘクスを覆う外周ボックス（フォグ全体の外枠）を、余白付きで返す。
List<List<double>> boundingBoxRing(List<HexCenter> centers, {double marginMeters = 100}) {
  final double metersPerDegLng =
      _metersPerDegLat * math.cos(kOriginLat * math.pi / 180.0);
  double minLat = double.infinity, maxLat = -double.infinity;
  double minLng = double.infinity, maxLng = -double.infinity;
  for (final c in centers) {
    minLat = math.min(minLat, c.lat);
    maxLat = math.max(maxLat, c.lat);
    minLng = math.min(minLng, c.lng);
    maxLng = math.max(maxLng, c.lng);
  }
  final double marginLat = marginMeters / _metersPerDegLat;
  final double marginLng = marginMeters / metersPerDegLng;
  minLat -= marginLat;
  maxLat += marginLat;
  minLng -= marginLng;
  maxLng += marginLng;
  return [
    [minLng, minLat],
    [maxLng, minLat],
    [maxLng, maxLat],
    [minLng, maxLat],
    [minLng, minLat],
  ];
}
