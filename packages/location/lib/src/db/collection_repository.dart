import 'package:drift/drift.dart';
import 'package:terra_town_core/terra_town_core.dart';

import 'game_database.dart';

/// `collection` テーブル（[GameDatabase.collections]・T034・T067・T070・
/// schemaVersion 3・Issue #159）の読み書き。
///
/// ## [save] が「新規追加のみ」である理由（`DisclosedHexRepository` と同じ方針）
/// `collection.poi_id` は主キーであり、[LandmarkCollectionRecord] のクラスdoc・
/// `docs/landmark_objects.md` §5 の「最初の収集記録を上書きしない」（Issue #159
/// 受け入れ基準「収集済みの名所は再収集されず、最初の記録が保持される」）を
/// 満たすため、`InsertMode.insertOrIgnore` で既存行を保護する。呼び出し側
/// （`evaluateLandmarkCollection`）が既に「未収集のPOIのみ」を返す設計だが、
/// [DisclosedHexRepository.save] と同じ理由で、万一の重複呼び出しに対する
/// 多重の安全策として本クラス側でも `insertOrIgnore` にする。
///
/// ## `final` にしていない理由（Issue #159・advisor指摘）
/// トランザクションの原子性テスト（収集の書き込みが失敗したら開示もロール
/// バックされること）のため、テストコードが本クラスを継承して [save] を
/// 意図的に失敗させるフェイクを作れるようにする
/// （`hex_opening_spend_service_test.dart` の `_ThrowingDisclosedHexRepository`
/// と同じ手法）。
class CollectionRepository {
  CollectionRepository(this._database);

  final GameDatabase _database;

  /// [ids] のうち、既に `collection` に記録済みのPOI IDの集合を返す
  /// （`evaluateLandmarkCollection` の `alreadyCollected` に渡すため）。
  ///
  /// [ids] が空の場合はクエリを発行せず空集合を返す（1ヘクスに名所が無い、
  /// 最も多いケースでの無駄なDBアクセスを避ける）。
  Future<Set<PointOfInterestId>> findCollectedIds(
    Iterable<PointOfInterestId> ids,
  ) async {
    final values = ids.map((id) => id.value).toList(growable: false);
    if (values.isEmpty) return const {};

    final rows = await (_database.select(_database.collections)
          ..where((t) => t.poiId.isIn(values)))
        .get();
    return rows.map((row) => PointOfInterestId(row.poiId)).toSet();
  }

  /// [record] を保存する（新規追加のみ。クラスdoc参照）。
  Future<void> save(LandmarkCollectionRecord record) async {
    await _database.into(_database.collections).insert(
          CollectionsCompanion.insert(
            poiId: record.poiId.value,
            kind: Value(record.kind),
            name: Value(record.name),
            isBonus: Value(record.isBonus),
            collectMethod: Value(record.collectMethod),
            bonusGranted: Value(record.bonusGranted),
            discoveredAt: Value(record.collectedAt),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// 保存済みの収集記録をすべて読み出す（Issue #159「収集済み件数を後続の
  /// 図鑑画面・ピン表示が参照できるよう、読み出し口を用意する」）。
  ///
  /// 図鑑画面（Issue #12・T075）自体は本Issueのスコープ外のため、生の
  /// [CollectionRow] をそのまま返す（`kind`/`name`/`collectMethod` が
  /// null のことがある——v2以前の既存行の場合。[Collections] クラスdoc参照）。
  Future<List<CollectionRow>> findAll() =>
      _database.select(_database.collections).get();

  /// 保存済みの収集記録の件数（図鑑画面のサマリ表示等に使う想定）。
  Future<int> count() async {
    final countExpression = _database.collections.poiId.count();
    final query = _database.selectOnly(_database.collections)
      ..addColumns([countExpression]);
    final row = await query.getSingle();
    return row.read(countExpression) ?? 0;
  }
}
