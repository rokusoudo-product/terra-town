import 'package:terra_town_core/terra_town_core.dart';

import 'collection_repository.dart';

/// [disclosedHex] にある未収集の名所を判定・保存する共通処理（Issue #159）。
///
/// [HexOpeningSpendService]（ポイント開放経路）・
/// [LandmarkAwareDisclosedHexRepository]（徒歩経路）の両方から呼ばれる。
/// 呼び出し側は自身の DB トランザクションの**内側**で本関数を呼ぶこと
/// （本関数自体はトランザクション境界を持たない。`collectionRepository` が
/// 呼び出し側と同じ [GameDatabase] インスタンスに紐づいていれば、Drift の
/// Zone スコープにより自動的に同じトランザクションに含まれる。
/// `InventoryRepository.add` のドキュメント「呼び出し側が
/// `_database.transaction` の中でこのメソッドを呼ぶと…」と同じ仕組み）。
///
/// 1ヘクスに名所が無い（最も多いケース）場合は [CollectionRepository] への
/// クエリを一切発行しない。
Future<List<LandmarkCollectionRecord>> collectLandmarksForDisclosedHex({
  required DisclosedHex disclosedHex,
  required RegionPack regionPack,
  required CollectionRepository collectionRepository,
  required CollectMethod collectMethod,
  required DateTime Function() now,
}) async {
  final pois = regionPack.pointsOfInterestIn(disclosedHex.hexId);
  if (pois.isEmpty) return const [];

  final poiIds = pois.map((poi) => poi.id).toList(growable: false);
  final alreadyCollected = await collectionRepository.findCollectedIds(poiIds);

  final records = evaluateLandmarkCollection(
    disclosedHex: disclosedHex,
    regionPack: regionPack,
    collectMethod: collectMethod,
    collectedAt: now(),
    alreadyCollected: alreadyCollected,
  );

  for (final record in records) {
    await collectionRepository.save(record);
  }

  return records;
}
