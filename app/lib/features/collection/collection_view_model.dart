import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'collection_category.dart';

/// カテゴリ1件分の集計（T075 受け入れ基準「カテゴリごとに『収集数/総数』が
/// 表示され、合計がパックの名所件数と一致する」）。
class CategorySummary {
  const CategorySummary({
    required this.category,
    required this.collectedCount,
    required this.totalCount,
  });

  final LandmarkCategory category;

  /// このカテゴリで収集済みの件数。
  ///
  /// 【`totalCount` を超えうる理由（判断の記録・PR本文にも記載）】パックから
  /// 消えた名所（[buildCollectionViewData] クラスdoc「パックに存在しない収集記録」
  /// 参照）も収集数には含めるが、[totalCount] は**現在のパック**基準のままにする。
  /// 現行パック（51件）にはまだ発生しないが、将来パック更新でPOIが除外された
  /// 場合に構造的に起こりうる差である。
  final int collectedCount;

  /// このカテゴリの、現在のパックに収録されている名所の総数。
  final int totalCount;
}

/// 個別POI一覧の1行分。
class CollectionEntry {
  const CollectionEntry({
    required this.poiId,
    required this.category,
    required this.isCollected,
    this.name,
    this.collectedAt,
    this.collectMethod,
    this.isOrphaned = false,
  });

  final PointOfInterestId poiId;
  final LandmarkCategory category;

  /// 収集済みか（false の場合、[name] は伏せて表示すること。
  /// Issue #161 代表決定「未収集はMaterialアイコン＋『？』」）。
  final bool isCollected;

  /// 名称。[isCollected] が false のときは常に null
  /// （呼び出し側〔UI〕は名称を表示せず「？」に置き換えること）。
  final String? name;

  final DateTime? collectedAt;
  final CollectMethod? collectMethod;

  /// 収集済みだが、現在のパックにはもう存在しない名所（クラスdoc参照）。
  final bool isOrphaned;
}

/// [buildCollectionViewData] の結果一式。
class CollectionViewData {
  const CollectionViewData({required this.categorySummaries, required this.entries});

  /// [categoryDisplayOrder] の順（総数・収集数がともに0のカテゴリは含めない）。
  final List<CategorySummary> categorySummaries;

  /// 表示順（カテゴリ順→収集済み〔新しい順〕→未収集）に並べ済みの一覧。
  final List<CollectionEntry> entries;
}

/// パックのPOI一覧と `collection` テーブルの読み出し結果から、図鑑画面が
/// 表示するデータ（カテゴリ集計＋個別一覧）を組み立てる純粋関数（T075）。
///
/// UIから分離してあるのは、Flutter widget を介さずに集計ロジック単体を
/// テストできるようにするため（`test/features/collection/collection_view_model_test.dart`）。
///
/// ## 収集済みの行は `collection` のスナップショットを優先する（Issue #161 設計）
/// `docs/landmark-collection-impl.md` §4/§5 の設計どおり、`collection.kind`・
/// `collection.name` は収集した瞬間のスナップショットであり、パック側
/// （[pack]）の現在値より正確（POIが将来 OSM から消えても記録は残る）。
/// そのため [CollectionRow.kind]/[CollectionRow.name] が非nullならそれを使い、
/// null（v2以前の行。`docs/landmark-collection-impl.md` §4参照）の場合のみ
/// パック側の値にフォールバックする。
///
/// ## パックに存在しない収集記録（判断の記録・PR本文にも記載）
/// `collection` にはあるが [pack] の [RegionPack.pointsOfInterest] には無いPOI
/// （パック更新でPOIが削除された場合。現行パック51件では発生しない）も、
/// [CollectionEntry.isOrphaned] = true として一覧に含める（Issue #161 提案内容
/// 「パックから消えた名所も一覧に出す」）。この場合カテゴリ集計の分母
/// （[CategorySummary.totalCount]）には含めない（分母は「現在のパックに実在する
/// 名所数」の意味を保つため）が、分子（[CategorySummary.collectedCount]）には
/// 含める。結果として `collectedCount > totalCount` になりうる
/// （[CategorySummary.collectedCount] のドキュメント参照）。
CollectionViewData buildCollectionViewData({
  required RegionPack pack,
  required List<CollectionRow> collected,
}) {
  final packPois = pack.pointsOfInterest.toList(growable: false);
  final packPoiById = {for (final poi in packPois) poi.id.value: poi};

  // --- カテゴリ集計: 総数（現在のパック基準） ---
  final totalByCategory = <LandmarkCategory, int>{};
  for (final poi in packPois) {
    final category = categoryOf(poi.kind);
    totalByCategory[category] = (totalByCategory[category] ?? 0) + 1;
  }

  // --- カテゴリ集計: 収集数（collection のスナップショット優先） ---
  final collectedByCategory = <LandmarkCategory, int>{};
  final collectedPoiIds = <String>{};
  for (final row in collected) {
    collectedPoiIds.add(row.poiId);
    final kind = row.kind ?? packPoiById[row.poiId]?.kind;
    final category = categoryOf(kind);
    collectedByCategory[category] = (collectedByCategory[category] ?? 0) + 1;
  }

  final categorySummaries = <CategorySummary>[
    for (final category in categoryDisplayOrder)
      if ((totalByCategory[category] ?? 0) > 0 ||
          (collectedByCategory[category] ?? 0) > 0)
        CategorySummary(
          category: category,
          collectedCount: collectedByCategory[category] ?? 0,
          totalCount: totalByCategory[category] ?? 0,
        ),
  ];

  // --- 個別一覧 ---
  final collectedEntries = <CollectionEntry>[
    for (final row in collected)
      CollectionEntry(
        poiId: PointOfInterestId(row.poiId),
        category: categoryOf(row.kind ?? packPoiById[row.poiId]?.kind),
        isCollected: true,
        name: row.name ?? packPoiById[row.poiId]?.name ?? '（名称不明）',
        collectedAt: row.discoveredAt,
        collectMethod: row.collectMethod,
        isOrphaned: !packPoiById.containsKey(row.poiId),
      ),
  ]..sort((a, b) {
      // 新しく収集したものを上に（受け入れ基準の直接要求ではないが、
      // インベントリ画面と異なり「最近の成果」が見えると発見の動機づけになる）。
      final byDate = (b.collectedAt ?? DateTime(0)).compareTo(
        a.collectedAt ?? DateTime(0),
      );
      if (byDate != 0) return byDate;
      return a.poiId.value.compareTo(b.poiId.value);
    });

  final uncollectedEntries = <CollectionEntry>[
    for (final poi in packPois)
      if (!collectedPoiIds.contains(poi.id.value))
        CollectionEntry(
          poiId: poi.id,
          category: categoryOf(poi.kind),
          isCollected: false,
        ),
  ]..sort((a, b) => a.poiId.value.compareTo(b.poiId.value));

  final entriesByCategory = <LandmarkCategory, List<CollectionEntry>>{};
  for (final entry in [...collectedEntries, ...uncollectedEntries]) {
    entriesByCategory.putIfAbsent(entry.category, () => []).add(entry);
  }

  final entries = <CollectionEntry>[
    for (final category in categoryDisplayOrder)
      ...?entriesByCategory[category],
  ];

  return CollectionViewData(categorySummaries: categorySummaries, entries: entries);
}
