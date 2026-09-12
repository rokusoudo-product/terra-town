import '../terrain/terrain_type.dart';

/// 開示済みヘクスの地形分類ごとの件数を保持するミュータブルなカウンタ
/// （T068・Issue #138）。
///
/// [computeTerrainYieldAccrual]（`resource_grant_service.dart`）が要求する
/// `Map<TerrainType, int>` を、開示済みヘクスの追加のたびに `O(1)` で更新するために
/// 使う。**開示済みヘクスの実体（`disclosed_hex` テーブル・`DisclosedHexSet`）を
/// 二重管理するものではなく、地形産出の計算にだけ使う派生インデックス**である
/// （`DisclosedHexSet` クラスdoc「開示状態の正について」と同じ考え方: 正は
/// 永続ストレージであり、本クラスはアプリ起動のたびに [initializeFrom] で
/// 作り直す作業表現に過ぎない）。
class TerrainHexCounter {
  final Map<TerrainType, int> _counts = {};

  /// 現在の地形分類ごとの件数（呼び出し側が変更できないコピー）。
  Map<TerrainType, int> get counts => Map.unmodifiable(_counts);

  /// [terrainTypes] から件数を作り直す（既存の件数は破棄する）。
  ///
  /// アプリ起動時に `DisclosedHexRepository.findAll()` で読み出した全ヘクスの
  /// [DisclosedHex.terrainType] の列を渡して初期化する想定
  /// （`app/lib/map/economy/terrain_yield_pipeline.dart` 参照）。
  void initializeFrom(Iterable<TerrainType> terrainTypes) {
    _counts.clear();
    for (final terrainType in terrainTypes) {
      _counts.update(terrainType, (value) => value + 1, ifAbsent: () => 1);
    }
  }

  /// 新規に1ヘクスが [terrainType] として開示されたことを反映する。
  void increment(TerrainType terrainType) {
    _counts.update(terrainType, (value) => value + 1, ifAbsent: () => 1);
  }
}
