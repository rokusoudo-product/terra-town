import '../geo/hex_id.dart';
import '../terrain/terrain_type.dart';
import 'disclosed_hex.dart';
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
  /// （獲得履歴は開示時点のスナップショットで確定・[DisclosedHex] 参照）。
  /// このバージョン値は、新規にヘクスを開示する瞬間（T054）に
  /// [DisclosedHex.discoveredAtVersion] へ記録する監査目的の値として使われる
  /// （2026-09-10・Issue #96・代表決定。以前は開示当時のバージョンで本パックを
  /// 引き直す用途だったが、その経路〔`PackVersionResolver`〕は廃止した）。
  PackVersion get version;

  /// [hexId] の地形タイプ。このパックに収録されていないヘクスは null。
  ///
  /// 【呼び出してよいタイミング（重要・Issue #96）】本メソッドは、あるヘクスを
  /// **新規に開示する瞬間**（T054）に、そのヘクスの [DisclosedHex.terrainType]
  /// スナップショットを作るためだけに呼ぶこと。**既に開示済みのヘクスの地形分類を
  /// 再解決するために呼んではならない**——開示済みヘクスの地形分類の正は
  /// 常に [DisclosedHex.terrainType]（`disclosed_hex` テーブルのスナップショット列）
  /// であり、本パックを再度引く経路は存在しない（アプリ同梱の MVP では
  /// パック更新＝アプリ更新であり、旧パックは端末から消えるため、そもそも
  /// 「開示当時のバージョンの本パック」を再取得できない）。
  TerrainType? terrainOf(HexId hexId);

  /// [hexId] が属する行政区画の識別子。未帰属（パック範囲外・水域等）は null。
  ///
  /// ヘクスと区画の帰属判定（ヘクス重心が区画内かの判定）は事前計算済みであり
  /// （plan.md §8）、`core` 側では判定ロジックを持たず結果を参照するのみ。
  ///
  /// 【[terrainOf] と異なりスナップショットしない（Issue #96・代表決定）】
  /// 区画は**常に現行パックから解決する**。制覇率（Issue #7・V-C）は
  /// 「現在の区画定義に対する割合」として意味を持つため、開示時点の区画割り当てを
  /// 凍結すると市町村合併等の行政区域変更後に現在の区画と食い違い、制覇率が
  /// 計算できなくなる。行政区域の変更は年単位で稀であり、OSM の日常更新
  /// （地形分類が揺れる頻度）とは2桁違う。合併時は進捗も合算されるのが自然、
  /// という判断も込みで「常に現行パックを引く」を採用した。
  DistrictId? districtOf(HexId hexId);

  /// パックに収録されている行政区画の一覧（読み取り専用）。
  Iterable<District> get districts;

  /// パックに収録されている名所POIの一覧（読み取り専用）。
  ///
  /// 【スナップショットしない（Issue #96・代表決定）】保全すべきは「プレイヤーが
  /// 何を集めたか」であり、`packages/location` の `collection` テーブル
  /// （T034・PR #90）が発見記録を保持する。POI が OSM から消えても
  /// コレクションは失われない。ヘクスと POI の対応づけを別途凍結すると、
  /// 同じ情報を二重に持つことになるため凍結しない。
  Iterable<PointOfInterest> get pointsOfInterest;

  /// [hexId] に隣接するヘクスの一覧（Issue #151・#152。パック生成時にH3で事前計算済み）。
  ///
  /// 出典: Issue #151（開放ポイントの消費）の隣接制約「開放済みヘクスに隣接する
  /// ヘクスのみ開放できる」（`docs/opening_points.md` §5.2）に必要な「あるヘクスの
  /// 隣は誰か」を提供する。H3（ヘクスの計算）は Issue #108 で Kotlin 側に寄せたため、
  /// `core`・`location` の Dart 側は実行時に H3 を呼ばない。`tools/pack-builder/`
  /// （`compute_hex_neighbors.py`）がパック生成時に `h3.grid_ring(k=1)` で計算し、
  /// `region_pack.sqlite` の `hex_neighbor` テーブルに事前計算済みの結果として格納する。
  /// 本メソッドはその結果を読み取るだけであり、GPS_ARCHITECTURE 準拠で `core` は
  /// H3・地図SDKいずれにも依存しない（[HexId] の値のみを扱う）。
  ///
  /// **パック範囲外へ出る隣接は含まれない**（`tools/pack-builder/hex_neighbors.py`
  /// 参照）。パック範囲の縁のヘクスは6件未満になりうる。このパックに収録されていない
  /// [hexId]、または隣接関係が同梱されていない旧パックに対しては空のイテラブルを返す
  /// （`districtOf`/`pointsOfInterest` と同じ forward-compat 方針。
  /// `RegionPackRepository` 実装のクラスコメント参照）。
  Iterable<HexId> neighborsOf(HexId hexId);

  /// [hexId] に属する名所POIの一覧（Issue #158）。
  ///
  /// 出典: `docs/landmark_objects.md` §3.2「未開示ヘクス上のオブジェクトの見せ方」
  /// 「収集（開放）の2手段」に必要な「あるヘクスにどの名所が属するか」を提供する。
  /// `tools/pack-builder/extract_poi.py` がパック生成時にH3で事前計算し、
  /// `region_pack.sqlite` の `hex_poi` テーブルに格納したものを読み取るだけであり、
  /// `core` は緯度経度→ヘクスの変換ロジックを持たない（GPS_ARCHITECTURE準拠。
  /// [neighborsOf] と同じ設計）。
  ///
  /// **`hex_poi`が同梱されていない旧パック、[hexId]に対応するPOIが無い、または
  /// このパックに収録されていない[hexId]に対しては空のイテラブルを返す**（[neighborsOf]
  /// と同じ forward-compat 方針。`RegionPackRepository` 実装のクラスコメント参照）。
  Iterable<PointOfInterest> pointsOfInterestIn(HexId hexId);
}
