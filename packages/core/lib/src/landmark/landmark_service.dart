import '../geo/hex_id.dart';
import '../pack/disclosed_hex.dart';
import '../pack/point_of_interest.dart';
import '../pack/region_pack.dart';

/// 名所を収集した手段（T070・Issue #159）。
///
/// 出典: `docs/landmark_objects.md` §3.2「収集（開放）の2手段」・§5
/// `collection` レコードの `collect_method` フィールド。
enum CollectMethod {
  /// 現地開示（徒歩でヘクスの霧が晴れたことによる収集）。
  walk,

  /// ポイント開放（開放ポイントを消費してヘクスを開いたことによる収集）。
  point,
}

/// 名所（POI）1件の収集記録（T070・Issue #159）。
///
/// 出典: `docs/landmark_objects.md` §5「`collection` レコードの必須項目」。
/// [poiId] を主キーとして `packages/location` の `collection` テーブルへ
/// 永続化することを想定した値オブジェクト（永続化自体は `location` 側の責務・
/// GPS_ARCHITECTURE 準拠で本クラス自体は SQLite 等に依存しない）。
///
/// 【[kind]・[name] をスナップショットとして持つ理由】
/// `RegionPack.pointsOfInterest`（POIメタデータの正）は OSM 由来のデータが
/// 更新・削除されると値が変わりうる。`disclosed_hex.terrainType`
/// （`DisclosedHex` クラスdoc参照）と同じ考え方で、**収集した瞬間の値を
/// この記録自体にコピーして保持する**ことで、POI が将来 OSM から消えても
/// 図鑑の記録は失われない。
///
/// 【本Issue（#159）でのボーナス関連フィールドの扱い】
/// 代表決定（2026-09-13）により、ボーナスオブジェクト判定・効果は
/// `future` Issue #162 に切り出された。本Issueで生成される記録は常に
/// [isBonus] = false・[bonusGranted] = null で固定する
/// （`evaluateLandmarkCollection` 参照）。
class LandmarkCollectionRecord {
  const LandmarkCollectionRecord({
    required this.poiId,
    required this.kind,
    required this.name,
    required this.isBonus,
    required this.collectedAt,
    required this.collectMethod,
    this.bonusGranted,
  });

  /// 収集した名所POIの識別子（`collection.poi_id` の主キーと対応）。
  final PointOfInterestId poiId;

  /// 収集時点のPOI種別のスナップショット（クラスdoc参照）。
  final String kind;

  /// 収集時点のPOI名称のスナップショット（クラスdoc参照）。
  final String name;

  /// ボーナスオブジェクトか否か。本Issueでは常に false（クラスdoc参照）。
  final bool isBonus;

  /// 収集日時（`docs/landmark_objects.md` §5 の `collected_at`）。
  final DateTime collectedAt;

  /// 収集手段（徒歩／ポイント開放）。
  final CollectMethod collectMethod;

  /// 収集時に付与された副次ボーナス値。本Issueでは常に null（クラスdoc参照）。
  final int? bonusGranted;

  @override
  bool operator ==(Object other) =>
      other is LandmarkCollectionRecord &&
      other.poiId == poiId &&
      other.kind == kind &&
      other.name == name &&
      other.isBonus == isBonus &&
      other.collectedAt == collectedAt &&
      other.collectMethod == collectMethod &&
      other.bonusGranted == bonusGranted;

  @override
  int get hashCode => Object.hash(
        poiId,
        kind,
        name,
        isBonus,
        collectedAt,
        collectMethod,
        bonusGranted,
      );

  @override
  String toString() => 'LandmarkCollectionRecord(poiId: $poiId, kind: $kind, '
      'name: $name, isBonus: $isBonus, collectedAt: $collectedAt, '
      'collectMethod: $collectMethod, bonusGranted: $bonusGranted)';
}

/// 新規開示された [disclosedHex] にある名所のうち、未収集のものの収集記録を
/// 返す決定論的な純粋関数（T070・Issue #159）。
///
/// 出典: `docs/landmark_objects.md` §3.2「収集（開放）の2手段」・§5。
/// `evaluateHexOpening`（`opening_point_service.dart`）と同じ設計方針
/// （`RegionPack` を直接受け取り、副作用を持たない同期関数として実装する）。
///
/// ## 呼び出し方（`location` 側の責務との分担）
/// 本関数はDBへの読み書きを一切行わない。呼び出し側（`location`）が:
/// 1. [disclosedHex] を実際に永続化する直前・直後の同一トランザクション内で
///    本関数を呼び、
/// 2. [alreadyCollected] にはそのトランザクション内で読み出し済みの
///    「既に収集済みのPOI ID集合」を渡し、
/// 3. 返ってきた記録を `collection` テーブルへ保存する
///
/// という流れを想定する（`HexOpeningSpendService`・
/// `LandmarkAwareDisclosedHexRepository` 参照）。
///
/// ## 未収集の名所のみを返す（冪等性の一端）
/// [alreadyCollected] に含まれる [PointOfInterestId] を持つPOIは結果に含めない
/// （「収集済みの名所は再収集しない」Issue #159 受け入れ基準）。呼び出し側は
/// さらに `collection.poi_id` 主キー・`InsertMode.insertOrIgnore` で保存することで、
/// 万一 [alreadyCollected] が古い場合の二重挿入も防ぐ（`DisclosedHexRepository.save`
/// と同じ多重の安全策）。
///
/// ## `PointOfInterest.hexId` が null の旧パックは収集しない
/// [RegionPack.pointsOfInterestIn] 自体が `hex_poi` 非同梱の旧パックに対して
/// 空のイテラブルを返す（forward-compat 方針・`region_pack.dart` 参照）ため、
/// 本関数側で追加のnullチェックは不要。
///
/// ## 全件 `is_bonus = false`・`bonus_granted = null`（2026-09-13代表決定）
/// ボーナスオブジェクトの判定・効果計算は `future` Issue #162 のスコープ。
List<LandmarkCollectionRecord> evaluateLandmarkCollection({
  required DisclosedHex disclosedHex,
  required RegionPack regionPack,
  required CollectMethod collectMethod,
  required DateTime collectedAt,
  Set<PointOfInterestId> alreadyCollected = const {},
}) {
  final HexId hexId = disclosedHex.hexId;
  final pois = regionPack.pointsOfInterestIn(hexId);

  return [
    for (final poi in pois)
      if (!alreadyCollected.contains(poi.id))
        LandmarkCollectionRecord(
          poiId: poi.id,
          kind: poi.kind,
          name: poi.name,
          isBonus: false,
          collectedAt: collectedAt,
          collectMethod: collectMethod,
          bonusGranted: null,
        ),
  ];
}
