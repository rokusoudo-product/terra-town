import 'dart:convert';

import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../db/region_pack_connection.dart';

/// [hexIds] に対応するヘクス中心（経度・緯度の順で `[lon, lat]`）を、地域パック
/// （[connection]）の `hex_terrain.boundary_geojson`（ヘクスの六角形境界。
/// `fog_hex_source.dart` クラスdoc参照）から算出する（Issue #193・T090）。
///
/// ## H3 を実行時に呼ばない（GPS_ARCHITECTURE 準拠・`fog_hex_source.dart` と同じ理由）
/// ヘクス中心も H3 ライブラリで算出し直せば求まるが、H3（ヘクスの計算）は
/// Issue #108 で Kotlin 側に寄せたため、Dart 側（`core`・`location`）は実行時に
/// H3 を呼ばない方針である。本関数は `hex_terrain.boundary_geojson`
/// （パック生成時に事前計算済みの六角形境界。`tools/pack-builder/hex_geometry.py`）を
/// そのまま読み、境界の頂点（閉環の末尾の重複点を除く）を単純平均するだけで
/// 中心を求める。正六角形に近い形状であれば頂点平均は幾何的重心と実用上一致し、
/// シンボルアイコン1個分の配置精度としては十分である（メルカトル図法の歪みに
/// よる誤差も、ヘクス1個分のスケール〔約50m。`docs/terrain.md` §3〕では
/// 無視できる）。
///
/// ## 見つからない hexId は結果に含めない（forward-compat・fogとは異なる方針）
/// [RegionPackMissingHexGeometryException]（`fog_hex_source.dart`）と異なり、
/// 本関数は該当行が見つからない・`boundary_geojson` が読めない hexId があっても
/// 例外を投げず、結果の Map に含めないだけにとどめる。fog of war は全ヘクスの
/// 表示が前提のため1件でも欠けると重大な不具合になるが、建物レイヤーは
/// 「たまたま1棟だけ表示できない」程度に留めるほうが実害が小さい
/// （`core` の `RegionPack.neighborsOf`・`RegionPack.pointsOfInterestIn` の
/// 「収録されていない場合は空を返す」forward-compat 方針と同じ考え方）。
///
/// 呼び出し元（`building_layer.dart` の [buildBuildingFeatureCollection] を
/// 呼ぶ側。`map_screen.dart` 参照）は、本関数が対応する `hex_terrain` を1度に
/// まとめて引けるよう、必要な hexId をあらかじめ集めてから1回だけ呼ぶこと
/// （建物の件数だけ都度クエリを発行しない）。
Map<int, List<double>> hexCentersFromRegionPack(
  RegionPackConnection connection,
  Iterable<int> hexIds,
) {
  final ids = hexIds.toSet().toList();
  if (ids.isEmpty) return const {};

  final placeholders = List.filled(ids.length, '?').join(',');
  final sqlite3.ResultSet rows = connection.rawSelect(
    'SELECT hex_id, boundary_geojson FROM hex_terrain '
    'WHERE hex_id IN ($placeholders)',
    ids,
  );

  final result = <int, List<double>>{};
  for (final row in rows) {
    final hexId = row['hex_id'] as int;
    final boundaryGeojson = row['boundary_geojson'];
    if (boundaryGeojson is! String) continue;

    Object? decoded;
    try {
      decoded = jsonDecode(boundaryGeojson);
    } on FormatException {
      continue;
    }
    if (decoded is! List || decoded.isEmpty) continue;

    // 閉環（GeoJSON Polygonの慣例。先頭=末尾）の最後の頂点を除いて平均する
    // （`tools/pack-builder/hex_geometry.py` が生成する ring は常に閉環。
    // クラスdoc参照）。
    final vertices = decoded.length > 1
        ? decoded.sublist(0, decoded.length - 1)
        : decoded;
    if (vertices.isEmpty) continue;

    var sumLon = 0.0;
    var sumLat = 0.0;
    var validCount = 0;
    for (final vertex in vertices) {
      if (vertex is! List || vertex.length < 2) continue;
      sumLon += (vertex[0] as num).toDouble();
      sumLat += (vertex[1] as num).toDouble();
      validCount++;
    }
    if (validCount == 0) continue;

    result[hexId] = [sumLon / validCount, sumLat / validCount];
  }
  return result;
}
