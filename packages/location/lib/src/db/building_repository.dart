import 'package:drift/drift.dart';
import 'package:terra_town_core/terra_town_core.dart';

import 'game_database.dart';

/// `building` テーブル（[GameDatabase.buildings]・T033）の読み書き（Issue #192・T089）。
///
/// 出典: Issue #192 本文「1. 建設の保存（`packages/location`）」
/// 「`BuildingRepository`（`building` テーブルの読み書き・全件取得・ヘクス指定の取得）」。
///
/// ## 判定ロジックは持たない
/// 「開示済みかつ空き地」「1マス1建物」等の建築可否判定（`core` の
/// `evaluateBuild`）は本クラスの責務ではない。本クラスは `building` テーブルへの
/// 素朴な読み書きのみを行い、可否判定と資材消費の同時実行は
/// [BuildingConstructionService]（`building_construction_service.dart`）が担う
/// （`DisclosedHexRepository`/`HexOpeningSpendService` と同じ役割分担）。
///
/// ## `insert` は「新規追加のみ」（更新ではない）
/// [hexId] には一意制約（[GameDatabase.buildings] の `uniqueKeys`）があるため、
/// 同じヘクスへの2回目の [insert] は制約違反で例外を投げる（1マス1建物の原則。
/// `docs/buildings.md` §3）。呼び出し側（[BuildingConstructionService]）は
/// トランザクション内で [findByHexId] により事前に存在しないことを確認してから
/// [insert] を呼ぶこと。
class BuildingRepository {
  BuildingRepository(this._database);

  final GameDatabase _database;

  /// 建物が建っている全マスを取得する。
  Future<List<BuildingRow>> findAll() async {
    return _database.select(_database.buildings).get();
  }

  /// [hexId] に建っている建物（無ければ null）。
  Future<BuildingRow?> findByHexId(HexId hexId) async {
    return (_database.select(
      _database.buildings,
    )..where((t) => t.hexId.equals(hexId.value))).getSingleOrNull();
  }

  /// [hexId] に [buildingType] を Lv.1・[BuildingConstructionState.built] で
  /// 新規に建てる（Issue #192）。
  ///
  /// [districtId] は `RegionPack.districtOf(hexId)`（Issue #192 本文「`building`
  /// への追加（Lv.1・`districtId` は `RegionPack.districtOf`）」）。パック範囲外・
  /// 未帰属の場合は呼び出し側が null を渡すこと。
  ///
  /// 既に [hexId] に建物がある場合は一意制約違反で例外を投げる（クラスdoc
  /// 「`insert` は「新規追加のみ」」参照）。呼び出し側が事前に [findByHexId] で
  /// 確認していること。
  Future<BuildingRow> insert({
    required HexId hexId,
    required BuildingType buildingType,
    required DistrictId? districtId,
  }) async {
    final id = await _database
        .into(_database.buildings)
        .insert(
          BuildingsCompanion.insert(
            hexId: hexId.value,
            buildingType: buildingType,
            districtId: Value(districtId?.value),
          ),
        );
    return (_database.select(
      _database.buildings,
    )..where((t) => t.id.equals(id))).getSingle();
  }
}
