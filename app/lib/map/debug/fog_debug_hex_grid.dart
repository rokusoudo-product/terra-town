/// fog of war のデバッグ・計測用に、合成（プログラム生成）のヘクス風ポリゴンの
/// GeoJSON FeatureCollection を組み立てる。
///
/// 【本ファイルの位置づけ・重要】ここで作る「ヘクス」は**本物のヘクス割り当てではない**。
///
/// 【2026-09-10・Issue #105 で状況が変わった】実際のヘクス境界ジオメトリを組み立てる
/// 手段は、地域パックの `hex_terrain.boundary_geojson`（事前計算済み）を読む
/// `terra_town_location` の `buildFogHexFeatureCollectionFromRegionPack`
/// （`fog_hex_source.dart`）として実装済みである。**「本番相当ヘクス数でのソース構築
/// コスト計測」（`FogOfWarDebugPanel._runProductionScaleBenchmark`）は、以後は本ファイルの
/// 合成データではなく、その実装を使って実データ（13,106件）で計測する**（デバッグパネル側の
/// 変更点は `fog_of_war_debug_panel.dart` 参照）。
///
/// 本ファイルの合成データ生成器は、「1マス開示」「すべて開示」「霧に戻す」という
/// **トグル操作自体の確認**（下記(a)）にのみ引き続き使う。実ヘクスを使わない理由は、
/// この確認は境界の正確さを問わない軽量なデモであり、地域パック（ディスクI/O）を
/// 経由せず即座に動かせる利点を残したいため。
///
/// 本ファイルは、代表が実機で
///   (a) fog of war のトグル（`FogOfWarController.revealHex`）が実際に霧を晴らすこと
/// を確認するための**デバッグ専用**の合成データ生成器である。
/// `app/lib/features/map/map_screen.dart` から `kDebugMode` 配下でのみ使用し、
/// 製品ビルド（release）には一切現れない。
///
/// アルゴリズムは Issue #24 の性能計測ハーネス（`research.md` §6.4 の実測値を
/// 得た旧 `spikes/map_spike_gl/lib/hex_grid.dart`。当該ディレクトリは使い捨て
/// スパイクのため既に失われているが、git 履歴コミット `cf6192e` に残る）と
/// 同じ考え方を踏襲する: [hexFlatToFlatMeters]（`terra_town_core`・
/// docs/terrain.md §3・50m）から circumradius を逆算し、axial 座標系で
/// 格子状に配置したフラットトップ・ヘクス形のポリゴンを生成する。
library;

import 'dart:math' as math;

import 'package:terra_town_core/terra_town_core.dart';

const double _metersPerDegLat = 111320.0;

double get _hexCircumradiusMeters => hexFlatToFlatMeters / math.sqrt(3);

class _HexCenter {
  const _HexCenter(this.lat, this.lon);
  final double lat;
  final double lon;
}

double _metersPerDegLonAt(double lat) =>
    _metersPerDegLat * math.cos(lat * math.pi / 180.0);

_HexCenter _hexCenterAt({
  required double originLat,
  required double originLon,
  required int q,
  required int r,
}) {
  final circumradius = _hexCircumradiusMeters;
  final x = circumradius * 1.5 * q;
  final y = circumradius * math.sqrt(3) * (r + q / 2.0);
  final metersPerDegLon = _metersPerDegLonAt(originLat);
  return _HexCenter(
    originLat + (y / _metersPerDegLat),
    originLon + (x / metersPerDegLon),
  );
}

List<List<double>> _hexRing({
  required double originLat,
  required _HexCenter center,
}) {
  final circumradius = _hexCircumradiusMeters;
  final metersPerDegLon = _metersPerDegLonAt(originLat);
  final ring = <List<double>>[];
  for (var i = 0; i < 6; i++) {
    final angleRad = (60.0 * i) * math.pi / 180.0;
    final dx = circumradius * math.cos(angleRad);
    final dy = circumradius * math.sin(angleRad);
    ring.add([
      center.lon + (dx / metersPerDegLon),
      center.lat + (dy / _metersPerDegLat),
    ]);
  }
  ring.add(ring.first); // GeoJSON Polygon は閉環（始点=終点）である必要がある。
  return ring;
}

/// [count] 個の合成ヘクス風 Feature を持つ FeatureCollection を組み立てる。
///
/// 各 Feature は直下（`properties` の外）に整数 `id` を持つ
/// （`FogOfWarController.install` の受け入れ条件・plan.md §8）。
/// [firstFeatureId] からの連番を割り当てる（他用途の合成グリッドと feature id が
/// 衝突しないよう、呼び出し側で範囲を分けられるようにするため）。
///
/// 形状の見た目・実際の緯度経度の正確さは重要でない（用途はデバッグ表示と
/// ソース構築コストの計測のみのため）。[centerLat]/[centerLon] を中心に、
/// 概ね正方形に近い形へ ヘクスを敷き詰める。
Map<String, dynamic> buildSyntheticFogHexFeatureCollection({
  required double centerLat,
  required double centerLon,
  required int count,
  int firstFeatureId = 0,
}) {
  final side = math.sqrt(count).ceil() + 1;
  final features = <Map<String, dynamic>>[];
  var nextId = firstFeatureId;

  outer:
  for (var r = -side ~/ 2; r <= side ~/ 2; r++) {
    for (var q = -side ~/ 2; q <= side ~/ 2; q++) {
      final center = _hexCenterAt(
        originLat: centerLat,
        originLon: centerLon,
        q: q,
        r: r,
      );
      features.add({
        'type': 'Feature',
        'id': nextId,
        'geometry': {
          'type': 'Polygon',
          'coordinates': [_hexRing(originLat: centerLat, center: center)],
        },
        'properties': const <String, dynamic>{},
      });
      nextId++;
      if (features.length >= count) break outer;
    }
  }

  return {'type': 'FeatureCollection', 'features': features};
}
