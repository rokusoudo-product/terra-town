import 'dart:math' as math;

/// [findNearestPackHex] が返す、地域パック内の1ヘクスの識別子と中心座標
/// （デバッグ専用・Issue #137）。
class PackHexCenter {
  const PackHexCenter({
    required this.hexId,
    required this.featureId,
    required this.latitude,
    required this.longitude,
  });

  /// `core` の `HexId.value`（H3 index）と対応する値。
  final int hexId;

  /// 地図 Feature の整数 `id`（`hex_terrain.feature_id`・docs/terrain.md §4.4）。
  final int featureId;

  final double latitude;
  final double longitude;
}

/// [fogHexFeatureCollection]（`buildFogHexFeatureCollectionFromRegionPack` が
/// 返す GeoJSON FeatureCollection）から、指定した緯度経度に最も近いヘクスを選ぶ
/// （デバッグパネル「地図の中心のヘクスを開示」専用・Issue #137）。
///
/// ## 幾何をその場で再計算しない（既に読み込み済みの FeatureCollection を使う）
/// ヘクス境界（`boundary_geojson`）は地域パック生成時に事前計算済みであり
/// （Issue #105）、地図表示のために既にメモリ上へ読み込み済みの
/// [fogHexFeatureCollection] をそのまま走査する（DBへの再アクセスをしない）。
/// H3 等のライブラリで境界を計算し直すこともしない（Dart 側に H3 実装を
/// 持ち込まない方針・Issue #108）。
///
/// 各 Feature の中心は、境界リングの頂点（先頭=末尾の閉環重複点を除く）の
/// 単純平均で近似する（ヘクスは凸多角形のため頂点平均は重心の妥当な近似になる。
/// デバッグ用途のため厳密な測地線重心までは不要と判断した）。
///
/// ## 緯度経度をそのまま比較しない理由（経度のスケール補正）
/// 対象エリア（狭山湖周辺・緯度35.79°付近）では経度1度あたりの実距離が
/// 緯度1度あたりの実距離の約81%（`cos(35.79°) ≈ 0.812`）しかない。単純な
/// ユークリッド距離（Δlat・Δlonをそのまま比較）だと東西方向の近さを過大評価し、
/// 「地図中心に最も近いヘクス」の判定がずれる。Δlon に `cos(latitude)` を掛けて
/// から比較することでこれを補正する（デバッグ用途のための近似であり、
/// 高精度な測地線距離計算〔Haversine等〕までは不要と判断した）。
///
/// パックにヘクスが1件も無い場合は null を返す。
PackHexCenter? findNearestPackHex(
  Map<String, dynamic> fogHexFeatureCollection, {
  required double latitude,
  required double longitude,
}) {
  final features = fogHexFeatureCollection['features'] as List?;
  if (features == null || features.isEmpty) return null;

  final lonScale = math.cos(latitude * math.pi / 180.0);

  PackHexCenter? nearest;
  double? nearestDistanceSquared;

  for (final rawFeature in features) {
    final feature = rawFeature as Map<String, dynamic>;
    final featureId = feature['id'] as int;
    final geometry = feature['geometry'] as Map<String, dynamic>;
    final coordinates = (geometry['coordinates'] as List).first as List;
    // 閉環の終点（=始点の重複）を除いて平均する（fog_hex_source.dart が
    // 組み立てるリングは GeoJSON Polygon の規約どおり始点=終点で閉じている）。
    final ringLength = coordinates.length > 1
        ? coordinates.length - 1
        : coordinates.length;

    var sumLat = 0.0;
    var sumLon = 0.0;
    for (var i = 0; i < ringLength; i++) {
      final point = coordinates[i] as List;
      sumLon += (point[0] as num).toDouble();
      sumLat += (point[1] as num).toDouble();
    }
    final centerLon = sumLon / ringLength;
    final centerLat = sumLat / ringLength;

    final dLat = centerLat - latitude;
    final dLon = (centerLon - longitude) * lonScale;
    final distanceSquared = dLat * dLat + dLon * dLon;

    if (nearestDistanceSquared == null || distanceSquared < nearestDistanceSquared) {
      nearestDistanceSquared = distanceSquared;
      final properties = feature['properties'] as Map<String, dynamic>;
      final hexIdStr = properties['hex_id_str'] as String;
      nearest = PackHexCenter(
        hexId: int.parse(hexIdStr),
        featureId: featureId,
        latitude: centerLat,
        longitude: centerLon,
      );
    }
  }

  return nearest;
}
