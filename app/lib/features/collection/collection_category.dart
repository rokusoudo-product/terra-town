/// 名所図鑑（T075・Issue #161）のカテゴリ対応表。
///
/// `docs/landmark_objects.md` §2 の POI 種別（OSM の `kind`＝`key=value` 文字列。
/// 例: `tourism=museum`）を、図鑑UIの表示用カテゴリへまとめる。**対応表はこの
/// ファイルに一箇所へ集約する**（Issue #161 提案内容「対応表はコード上で一箇所に
/// まとめる」）。UI側（`collection_screen.dart`）・集計ロジック（`collection_view_model.dart`）
/// はいずれも本ファイルの [categoryOf] のみを介して `kind` を解釈し、文字列比較を
/// 個別に持たない。
///
/// ## 対応表の根拠（2026-09-14時点の同梱パック・51件の内訳）
/// Issue #161 本文に記載の現行パック内訳と対応させてある:
/// `amenity=place_of_worship` 34・`historic=memorial` 5・`tourism=museum` 4・
/// `tourism=viewpoint` 2・`tourism=artwork` 2・`leisure=park` 2・
/// `tourism=information` 1・`tourism=attraction` 1（合計51）。
///
/// ## 未知の `kind` の扱い（forward-compat）
/// 将来パックが更新され、上表に無い `kind` の POI が追加されても本画面が
/// 落ちないよう、対応表に無い値はすべて [LandmarkCategory.other]（「その他」）に
/// 分類する（[categoryOf] 参照）。`kind` が `null`（v2 以前の `collection` 行。
/// `docs/landmark-collection-impl.md` §4 参照）の場合も同様に「その他」とする。
enum LandmarkCategory {
  shrineTemple('神社・寺'),
  historicMemorial('史跡・記念碑'),
  museum('博物館・美術館'),
  viewpoint('展望・景観'),
  park('公園'),
  artwork('アート'),
  informationCenter('案内所'),
  attraction('観光名所'),
  // 未知の kind の受け皿。表示順は必ず最後に置く（[categoryDisplayOrder] 参照）。
  other('その他');

  const LandmarkCategory(this.label);

  /// 図鑑画面に表示する日本語ラベル。
  final String label;
}

/// `kind`（`key=value` 文字列）→表示カテゴリの対応表。
///
/// 値を変更・追加する場合は本ファイルのクラスdocの内訳コメントも更新すること。
const Map<String, LandmarkCategory> _kindToCategory = {
  'amenity=place_of_worship': LandmarkCategory.shrineTemple,
  'historic=memorial': LandmarkCategory.historicMemorial,
  'tourism=museum': LandmarkCategory.museum,
  'tourism=viewpoint': LandmarkCategory.viewpoint,
  'leisure=park': LandmarkCategory.park,
  'tourism=artwork': LandmarkCategory.artwork,
  'tourism=information': LandmarkCategory.informationCenter,
  'tourism=attraction': LandmarkCategory.attraction,
};

/// 図鑑画面でのカテゴリ表示順（総数0件のカテゴリも欄自体は出さない設計のため、
/// この順はソート用途のみで、UI上の「常に全カテゴリを出す」ことは意味しない）。
const List<LandmarkCategory> categoryDisplayOrder = LandmarkCategory.values;

/// [kind] を表示カテゴリへ変換する。未知の値・`null` は
/// [LandmarkCategory.other] に分類する（クラスdoc「未知の kind の扱い」参照）。
LandmarkCategory categoryOf(String? kind) {
  if (kind == null) return LandmarkCategory.other;
  return _kindToCategory[kind] ?? LandmarkCategory.other;
}
