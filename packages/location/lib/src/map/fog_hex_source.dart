import 'dart:convert';

import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../db/region_pack_connection.dart';

/// [buildFogHexFeatureCollectionFromRegionPack] が、地域パック（[RegionPackConnection]）の
/// `hex_terrain` テーブルにヘクス境界（`boundary_geojson` 列）が無い場合に送出する例外。
///
/// 【想定される原因】Issue #105 より前に生成された古い `region_pack.sqlite`
/// （`tools/pack-builder/bundle_region_pack.sh` を再実行していない環境）を読み込んだ場合。
/// `hex_terrain.boundary_geojson` 列自体が存在しないため SQLite が例外を投げる、
/// または値が NULL のまま読めてしまうケースの両方をここで判別可能なメッセージに変換する。
class RegionPackMissingHexGeometryException implements Exception {
  const RegionPackMissingHexGeometryException(this.detail);

  final String detail;

  @override
  String toString() =>
      'RegionPackMissingHexGeometryException: 地域パックに fog of war 用のヘクス境界'
      '（hex_terrain.boundary_geojson）が見つかりません（$detail）。'
      'tools/pack-builder/bundle_region_pack.sh を最新のコードで再実行してください'
      '（Issue #105 以降のバージョンが必要です）。';
}

/// 地域パック（[connection]）の `hex_terrain` テーブルから、fog of war 用の
/// GeoJSON FeatureCollection を組み立てる（tasks.md T056・Issue #105）。
///
/// ## 位置づけ（Issue #105・2026-09-10 代表決定・案A）
/// ヘクスの六角形境界（緯度経度の座標列）は `tools/pack-builder/`（`hex_geometry.py`・
/// `classify_terrain.py`）が地域パック生成時に**事前計算**し、`hex_terrain.boundary_geojson`
/// 列（GeoJSON Polygon 座標配列の閉環・小数点以下7桁丸め・JSONテキスト）に格納済みである。
/// 本関数は**その値をそのまま読むだけ**であり、H3 等のライブラリで境界を計算し直すことは
/// しない（決定論・実行時コストの両面で計算をパック生成側に寄せる設計判断。詳細は
/// `tools/pack-builder/README.md`「ヘクス境界」節・Issue #105 の代表決定コメント参照）。
///
/// ## `FogOfWarController.install` との関係
/// 戻り値は [FogOfWarController.install]（`fog_of_war_layer.dart`）にそのまま渡せる
/// 形（各 Feature が直下に整数 `id` を持つ）で組み立てる。`id` には
/// `hex_terrain.feature_id`（H3 index の下位52bitマスク。`promoteId` を使わない理由は
/// `hex_bridge.py`・`docs/terrain.md` §4.4 参照）をそのまま使う。
///
/// ## T056 と T069 の責務分担（tasks.md 参照）
/// 本関数は **T056（fog of war 描画）の責務**として実装した。地域パックへの
/// 読み取り専用アクセス自体（[RegionPackConnection]）は T030（Issue #83）で
/// 既に用意されている接続をそのまま使う。`core` の `RegionPack` 抽象を実装する
/// `RegionPackRepository`（T069・Issue #96 の要件を含む地形/区画/POI の統合読み取り口）
/// とは**別物**であり、本関数は T069 を代替しない。`RegionPack`（`core`）は
/// GPS_ARCHITECTURE 準拠で地図SDK・幾何表現に一切依存できないため、そもそも
/// 「GeoJSON FeatureCollection を返す」ような幾何メソッドを持てない
/// （`core` は `HexId`/`TerrainType` のような座標に依存しない値だけを扱う）。
/// したがって「ヘクス境界の組み立て」は構造的に T069 の責務になり得ず、
/// T056 に属すると判断した。
///
/// [limit] を指定すると、`hex_id` 昇順で先頭 N 件だけを含む FeatureCollection を返す
/// （デモ・計測用に少数だけ試したい場合に使う。既定は全件）。
Map<String, dynamic> buildFogHexFeatureCollectionFromRegionPack(
  RegionPackConnection connection, {
  int? limit,
}) {
  final query = StringBuffer(
    'SELECT hex_id, feature_id, terrain_type, cell_count, boundary_geojson '
    'FROM hex_terrain ORDER BY hex_id',
  );
  if (limit != null) {
    query.write(' LIMIT $limit');
  }

  final sqlite3.ResultSet rows;
  try {
    rows = connection.rawSelect(query.toString());
  } on sqlite3.SqliteException catch (e) {
    // 列自体が存在しない場合（Issue #105 より前に生成された古いパック）に
    // 発生する。NULL値のケース（下記ループ内）とあわせて、呼び出し側からは
    // 同じ例外型で判別できるようにする。
    throw RegionPackMissingHexGeometryException('SQLite: $e');
  }

  final features = <Map<String, dynamic>>[];
  for (final row in rows) {
    final hexId = row['hex_id'] as int;
    final featureId = row['feature_id'] as int;
    final terrainType = row['terrain_type'] as String;
    final cellCount = row['cell_count'] as int;
    final boundaryGeojson = row['boundary_geojson'];

    if (boundaryGeojson is! String) {
      throw RegionPackMissingHexGeometryException(
        'hex_id=$hexId の boundary_geojson が String ではありません '
        '(${boundaryGeojson.runtimeType})',
      );
    }

    final ring = jsonDecode(boundaryGeojson);
    if (ring is! List) {
      throw RegionPackMissingHexGeometryException(
        'hex_id=$hexId の boundary_geojson が座標配列としてデコードできません',
      );
    }

    features.add({
      'type': 'Feature',
      // ⚠️ properties の外（直下）に整数 id を持たせる（promoteId は Android 非対応。
      // FogOfWarController.install が実行時にこれを検証する）。
      'id': featureId,
      'geometry': {
        'type': 'Polygon',
        'coordinates': [ring],
      },
      'properties': {
        'terrain_type': terrainType,
        'cell_count': cellCount,
        // hex_id（H3 index）は 2^53-1 を超えうるため、properties に含める場合は
        // 文字列で持たせる（docs/terrain.md §4.4・JSON safe integer の範囲外）。
        'hex_id_str': hexId.toString(),
      },
    });
  }

  if (features.isEmpty) {
    throw const RegionPackMissingHexGeometryException(
      'hex_terrain に行がありません',
    );
  }

  return {'type': 'FeatureCollection', 'features': features};
}
