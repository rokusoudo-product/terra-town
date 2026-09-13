import 'package:terra_town_core/terra_town_core.dart';

/// [fogHexFeatureCollection]（`buildFogHexFeatureCollectionFromRegionPack` が
/// 返す GeoJSON FeatureCollection）から、地図 Feature の整数 `id`
/// （`feature_id`）→ `core` の [HexId]（H3 index）への対応表を組み立てる
/// （Issue #151・T064「ポイント消費による未踏破ヘクスの開放」）。
///
/// ## なぜ必要か（[MapView.onFogHexTapped] との役割分担）
/// 地図をタップした際に得られるのは fog レイヤーの地物の整数 `id`
/// （`feature_id`。`hex_bridge.py`/`hex_feature_bridge.dart` の下位52bitマスク
/// 方式）だけであり、`core` のゲームロジックが必要とする [HexId]（H3 index。
/// `feature_id` は非可逆な下位ビットマスクのため一般には逆算できない）ではない。
/// composition root（本ファイルの呼び出し元・`map_screen.dart`）は起動時に
/// 地域パックから読み込み済みの [fogHexFeatureCollection] を既に持っている
/// （`_fogHexFeatureCollection`・fog of war 描画そのものに使っている値と同じ
/// インスタンス）ため、これを一度だけ走査して逆引き表を作れば、地域パックへの
/// 追加のDBアクセス（`hex_terrain` の再クエリ）なしにタップのたびの変換が
/// 完結する（`app/lib/map/debug/nearest_pack_hex.dart` が「地図中心に最も近い
/// ヘクス」を求める際に `properties.hex_id_str` を読むのと同じ手法。あちらは
/// `kDebugMode` 限定だが、本関数は製品UI〔T064〕からも使う）。
///
/// 各 Feature の `properties.hex_id_str` は H3 index を文字列化した値
/// （`fog_hex_source.dart`「hex_id（H3 index）は 2^53-1 を超えうるため、
/// properties に含める場合は文字列で持たせる」参照）であり、`int.parse` で
/// 精度を失わずに復元できる（H3 index は Dart の64bit `int` の範囲に収まる）。
///
/// パックにヘクスが1件も無い場合は空のマップを返す。
Map<int, HexId> buildHexIdByFeatureId(Map<String, dynamic> fogHexFeatureCollection) {
  final features = fogHexFeatureCollection['features'] as List?;
  if (features == null) return const {};

  final result = <int, HexId>{};
  for (final rawFeature in features) {
    final feature = rawFeature as Map<String, dynamic>;
    final featureId = feature['id'] as int;
    final properties = feature['properties'] as Map<String, dynamic>;
    final hexIdStr = properties['hex_id_str'] as String;
    result[featureId] = HexId(int.parse(hexIdStr));
  }
  return result;
}
