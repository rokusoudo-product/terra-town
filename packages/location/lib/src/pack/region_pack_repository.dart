// ignore_for_file: prefer_initializing_formals
// RegionPackRepository._ はあえて説明的な引数名（version・terrainByHexId 等）を
// 使っており、フィールド名（アンダースコア付き）をそのまま外部引数ラベルにする
// initializing formal は採用しない（呼び出し側 `load` ファクトリの可読性のため）。

import 'dart:convert';

import 'package:terra_town_core/terra_town_core.dart';

import '../db/region_pack_connection.dart';

/// [RegionPackConnection]（読み取り専用の地域パックDB）から `core` の
/// [RegionPack] 抽象を実装する（tasks.md T069・Issue #137）。
///
/// ## 【最重要】[terrainOf] を呼んでよいのは新規開示の瞬間だけ（Issue #96）
/// [RegionPack] の抽象自体のドキュメント（`packages/core/lib/src/pack/region_pack.dart`）
/// のとおり、本実装の [terrainOf] は `DisclosureService` が**新規にヘクスを開示する
/// 瞬間**に `DisclosedHex.terrainType` のスナップショットを作るためだけに呼ぶこと。
/// 既に開示済みのヘクスの地形分類を問い合わせる経路としては使わない（正は
/// `disclosed_hex.terrain_type`）。本クラス自体はその制約を強制しない
/// （呼び出し側の規律に依存する。`DisclosureService.recordPosition` の実装が
/// この規律を守っている）。
///
/// ## 責務の境界（Issue #105・tasks.md T069 の追記）
/// fog of war 用のヘクス境界ジオメトリ（GeoJSON FeatureCollection の組み立て）は
/// 本クラスの責務**ではない**。`core` の [RegionPack] は GPS_ARCHITECTURE 準拠で
/// 地図SDK・幾何表現に依存できないため、そもそも幾何を返すメソッドを持てない
/// （[terrainOf]/[districtOf]/[districts]/[pointsOfInterest] はいずれも座標に
/// 依存しない値・識別子のみを返す）。ヘクス境界の組み立ては T056 側
/// （`fog_hex_source.dart`・`buildFogHexFeatureCollectionFromRegionPack`）が担う。
///
/// ## 区画・POI・隣接テーブルが同梱パックに存在しない場合への対応（forward-compat）
/// `RegionPack` は Dart の `abstract interface class` であり
/// `districtOf`/`districts`/`pointsOfInterest`/`neighborsOf` を実装せずに済ませる
/// ことはできない。そのため本クラスは、読み込み時に `sqlite_master` でテーブルの
/// 存在を確認し、**存在しなければ「該当なし」（null・空リスト・空イテラブル）として
/// 振る舞う**（古いテストフィクスチャや、生成し直していない同梱パックに対しても
/// 壊れずに動くようにするため）。
///
/// 2026-09-13 時点（Issue #94・#152）で `tools/pack-builder/slim_pack_for_bundle.py`
/// が生成する `region_pack.sqlite` には次の6テーブルが揃っている:
/// `hex_terrain(hex_id, terrain_type, feature_id, cell_count, boundary_geojson)`・
/// `district(district_id, name, prefecture_name, county_name, geometry_geojson)`・
/// `hex_district(hex_id, district_id)`・`poi(id, lat, lon, kind, name)`・
/// `hex_neighbor(hex_id, neighbor_count, neighbor_hex_ids)`・`pack_meta(key, value)`。
///
/// ## `terrain_type` の文字列表現（snake_case → enum）
/// `tools/pack-builder/terrain_rules.py` は `core` の [TerrainType] enum値
/// （`vacantLot, forest, mountain, waterside, sea`）と1:1対応する snake_case
/// （`vacant_lot, forest, mountain, waterside, sea`）で `hex_terrain.terrain_type`
/// に保存する（同モジュールの docstring 参照）。本クラスはこれをキャメルケースへ
/// 機械的に変換したうえで `TerrainType.values.byName` する。**変換後にどの enum 値
/// にも一致しない場合は [StateError] を投げる**（`terrainOf` は「パック範囲外」を
/// 表す null をハンドリング済みの意味として既に使っているため、null で握りつぶすと
/// 「パック範囲外」と「パックと `core` の enum 定義がずれている」という異なる異常を
/// 区別できなくなる。後者は fail-loud にすべき配線バグである）。
///
/// ## メモリ上に読み込み済みであること（`RegionPack` 抽象の前提）
/// [RegionPack] の抽象メソッドはすべて同期（非 `Future`）で定義されており、
/// 「ロード（非同期・I/O）は呼び出し側があらかじめ完了させ、`RegionPack` が表す
/// 時点ではメモリ上に読み込み済み」という前提を置いている（`region_pack.dart`
/// ドキュメント参照）。本クラスはこの前提どおり、[load] の時点で `hex_terrain`・
/// （存在すれば）`district`/`hex_district`/`poi` を Map/List にすべて読み込み、
/// 以後の [terrainOf] 等は純粋なメモリ参照になる。
class RegionPackRepository implements RegionPack {
  RegionPackRepository._({
    required PackVersion version,
    required Map<int, TerrainType> terrainByHexId,
    required Map<int, DistrictId> districtByHexId,
    required List<District> districts,
    required List<PointOfInterest> pointsOfInterest,
    required Map<int, List<HexId>> neighborHexIdsByHexId,
  })  : _version = version,
        _terrainByHexId = terrainByHexId,
        _districtByHexId = districtByHexId,
        _districts = List.unmodifiable(districts),
        _pointsOfInterest = List.unmodifiable(pointsOfInterest),
        _neighborHexIdsByHexId = neighborHexIdsByHexId;

  final PackVersion _version;
  final Map<int, TerrainType> _terrainByHexId;
  final Map<int, DistrictId> _districtByHexId;
  final List<District> _districts;
  final List<PointOfInterest> _pointsOfInterest;

  /// ヘクスごとの隣接ヘクス一覧（Issue #152）。[load] の時点で
  /// `List.unmodifiable` 済みの値を格納する（`_loadHexNeighbors` 参照）。
  final Map<int, List<HexId>> _neighborHexIdsByHexId;

  /// [connection] から地域パックを読み込み、[RegionPackRepository] を組み立てる。
  ///
  /// 同期メソッドである（`RegionPackConnection.rawSelect` 自体が同期 API のため）。
  /// 呼び出し側は、必要であれば重い読み込み（ヘクス数が多いパック）を
  /// 別 isolate で行うことを検討してよいが、本クラス自体はその方針を強制しない。
  factory RegionPackRepository.load(RegionPackConnection connection) {
    final version = _loadVersion(connection);
    final terrainByHexId = _loadTerrain(connection);
    final tableNames = _existingTableNames(connection);

    final districtByHexId = tableNames.contains('hex_district')
        ? _loadHexDistrict(connection)
        : const <int, DistrictId>{};
    final districts = tableNames.contains('district')
        ? _loadDistricts(connection)
        : const <District>[];
    final pointsOfInterest = tableNames.contains('poi')
        ? _loadPointsOfInterest(connection)
        : const <PointOfInterest>[];
    final neighborHexIdsByHexId = tableNames.contains('hex_neighbor')
        ? _loadHexNeighbors(connection)
        : const <int, List<HexId>>{};

    return RegionPackRepository._(
      version: version,
      terrainByHexId: terrainByHexId,
      districtByHexId: districtByHexId,
      districts: districts,
      pointsOfInterest: pointsOfInterest,
      neighborHexIdsByHexId: neighborHexIdsByHexId,
    );
  }

  @override
  PackVersion get version => _version;

  @override
  TerrainType? terrainOf(HexId hexId) => _terrainByHexId[hexId.value];

  @override
  DistrictId? districtOf(HexId hexId) => _districtByHexId[hexId.value];

  @override
  Iterable<District> get districts => _districts;

  @override
  Iterable<PointOfInterest> get pointsOfInterest => _pointsOfInterest;

  @override
  Iterable<HexId> neighborsOf(HexId hexId) =>
      _neighborHexIdsByHexId[hexId.value] ?? const <HexId>[];

  static Set<String> _existingTableNames(RegionPackConnection connection) {
    final rows = connection.rawSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    return rows.map((row) => row['name'] as String).toSet();
  }

  static PackVersion _loadVersion(RegionPackConnection connection) {
    final rows = connection.rawSelect(
      "SELECT value FROM pack_meta WHERE key = 'pack_version'",
    );
    if (rows.isEmpty) {
      throw StateError(
        'pack_meta に pack_version がありません。地域パックの生成が壊れている'
        '可能性があります（tools/pack-builder/bundle_region_pack.sh を確認してください）。',
      );
    }
    return PackVersion(rows.first['value'] as String);
  }

  static Map<int, TerrainType> _loadTerrain(RegionPackConnection connection) {
    final rows = connection.rawSelect(
      'SELECT hex_id, terrain_type FROM hex_terrain',
    );
    final result = <int, TerrainType>{};
    for (final row in rows) {
      final hexId = row['hex_id'] as int;
      final rawTerrainType = row['terrain_type'] as String;
      result[hexId] = _terrainTypeFromSnakeCase(rawTerrainType);
    }
    return result;
  }

  static Map<int, DistrictId> _loadHexDistrict(RegionPackConnection connection) {
    final rows = connection.rawSelect(
      'SELECT hex_id, district_id FROM hex_district',
    );
    final result = <int, DistrictId>{};
    for (final row in rows) {
      final hexId = row['hex_id'] as int;
      final districtId = row['district_id'] as String;
      result[hexId] = DistrictId(districtId);
    }
    return result;
  }

  /// `hex_neighbor` テーブル（Issue #152・`tools/pack-builder/compute_hex_neighbors.py`）
  /// から、ヘクスごとの隣接ヘクス一覧を読み込む。
  ///
  /// `neighbor_hex_ids` 列はJSON整数配列のテキスト（例: `[123, 456]`）。
  /// SQLiteのINTEGERは64bitであり、`sqlite3`パッケージ・`jsonDecode`（Dart VM上）は
  /// いずれもDartの`int`（64bit）で値を返すため、`(row['neighbor_hex_ids'] as String)`
  /// を`jsonDecode`した各要素を`int`へキャストするだけで精度は失われない
  /// （H3 indexは2^63未満・`hex_bridge.py`参照。`num`経由の`toInt()`は使わない —
  /// もし将来何らかの理由で`double`が混入した場合、`toInt()`は黙って丸めてしまうが
  /// `as int`は`TypeError`でfail-loudになる。これは`terrainOf`の未知`terrain_type`と
  /// 同じ「不整合はfail-loudにする」方針）。
  static Map<int, List<HexId>> _loadHexNeighbors(RegionPackConnection connection) {
    final rows = connection.rawSelect(
      'SELECT hex_id, neighbor_hex_ids FROM hex_neighbor',
    );
    final result = <int, List<HexId>>{};
    for (final row in rows) {
      final hexId = row['hex_id'] as int;
      final raw = row['neighbor_hex_ids'] as String;
      final decoded = jsonDecode(raw) as List<dynamic>;
      result[hexId] = List.unmodifiable(decoded.map((e) => HexId(e as int)));
    }
    return result;
  }

  static List<District> _loadDistricts(RegionPackConnection connection) {
    final rows = connection.rawSelect('SELECT district_id, name FROM district');
    return [
      for (final row in rows)
        District(
          id: DistrictId(row['district_id'] as String),
          name: row['name'] as String,
        ),
    ];
  }

  static List<PointOfInterest> _loadPointsOfInterest(
    RegionPackConnection connection,
  ) {
    final rows = connection.rawSelect('SELECT id, lat, lon, kind, name FROM poi');
    return [
      for (final row in rows)
        PointOfInterest(
          id: PointOfInterestId(row['id'] as String),
          name: row['name'] as String,
          kind: row['kind'] as String,
          latitude: (row['lat'] as num).toDouble(),
          longitude: (row['lon'] as num).toDouble(),
        ),
    ];
  }

  /// `tools/pack-builder/terrain_rules.py` が書く snake_case（`vacant_lot` 等）を
  /// `core` の [TerrainType] enum 値（`vacantLot` 等）へ変換する。
  static TerrainType _terrainTypeFromSnakeCase(String raw) {
    final parts = raw.split('_');
    final camelCase = parts.first +
        parts.skip(1).map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1)).join();
    try {
      return TerrainType.values.byName(camelCase);
    } on ArgumentError {
      throw StateError(
        '地域パックの terrain_type "$raw"（変換後 "$camelCase"）が '
        'TerrainType のどの値とも一致しません。地域パック生成コード '
        '（tools/pack-builder/terrain_rules.py）と core の TerrainType '
        '（packages/core/lib/src/terrain/terrain_type.dart）の定義がずれています。',
      );
    }
  }
}
