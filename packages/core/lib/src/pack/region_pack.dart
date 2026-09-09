import '../geo/hex_id.dart';
import '../terrain/terrain_type.dart';
import 'district.dart';
import 'pack_version.dart';
import 'point_of_interest.dart';

/// 地域パック（配布物）1件に対する読み取り専用のアクセス口（T024）。
///
/// 出典: `specs/001-mvp/plan.md` §3.2 の地域パック内容物（ベクタタイル・
/// ヘクス地形属性・行政区画ポリゴン・名所POI・パックメタ）のうち、
/// `core` のゲームロジックが必要とする**地形属性・区画・POIの読み取り**だけを
/// 抽象として定義する。ベクタタイル（表示専用の描画データ）は地図描画
/// （`location/`）の責務であり、本抽象には含めない。
///
/// **地域パックは配布物であり読み取り専用**（plan.md §3・§6）。
/// 地域パックを書き換える・更新するためのメソッドは持たせないこと。
///
/// 実装（SQLite からの読み出し等）は `location/`（`RegionPackRepository`・
/// tasks.md T069）に置く（GPS_ARCHITECTURE 準拠：`core` は SQLite 等の
/// 永続化手段に依存しない）。本抽象のメソッドは同期（非 `Future`）で定義しており、
/// これは §3.5「1ソース＝1エリア=1パックにつき暫定上限 30,000 ヘクス」を根拠に、
/// 実装側がパックの読み込み（非同期・I/O）をあらかじめ完了させ、[RegionPack] が
/// 表す時点ではメモリ上に読み込み済みであることを前提としているためである。
/// 「ロード（非同期）は `location/` の `RegionPackRepository` の責務、
/// ロード済みデータへの読み取り口（同期）が本 [RegionPack]」という分担になる。
abstract interface class RegionPack {
  /// このパックのバージョン（plan.md §3.3）。
  ///
  /// 一度開示したヘクスの資材分類は、パック更新後も過去分は不変とする
  /// （獲得履歴は当時の [PackVersion] で確定）。この不変性ルール自体の実装は
  /// 別 Issue（#84・T035〜T037）が担当し、本抽象はその前提となる
  /// バージョン値を提供するだけである。
  PackVersion get version;

  /// [hexId] の地形タイプ。このパックに収録されていないヘクスは null。
  TerrainType? terrainOf(HexId hexId);

  /// [hexId] が属する行政区画の識別子。未帰属（パック範囲外・水域等）は null。
  ///
  /// ヘクスと区画の帰属判定（ヘクス重心が区画内かの判定）は事前計算済みであり
  /// （plan.md §8）、`core` 側では判定ロジックを持たず結果を参照するのみ。
  DistrictId? districtOf(HexId hexId);

  /// パックに収録されている行政区画の一覧（読み取り専用）。
  Iterable<District> get districts;

  /// パックに収録されている名所POIの一覧（読み取り専用）。
  Iterable<PointOfInterest> get pointsOfInterest;
}
