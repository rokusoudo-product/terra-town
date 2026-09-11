import '../geo/hex_id.dart';
import '../position/geo_position.dart';

/// 緯度経度（[GeoPosition]）から、その位置が属する [HexId] を求めるための抽象（T054）。
///
/// ## なぜ `core` がこの変換を自前で行わないか（Issue #101・最重要）
/// `docs/terrain.md` §4.3 のとおり、緯度経度→ヘクスIDの変換は
/// 「細分グリッドセルへの投影 → 固定解像度11でのH3セルインデックス変換」という
/// 手順で行われるが、これは `location/`（生成側は `tools/pack-builder/`）の責務であり、
/// `core` に H3 等の実装を持ち込まないことが `hex_id.dart`・`plan.md` §5
/// （「`core` は事前計算済みの `HexId`…を受け取る」）で確定している。
///
/// したがって [HexLocator] は変換の**結果だけを返す窓口**として `core` に定義し、
/// 実際の変換（細分グリッドセルへの投影・H3変換）は `location/` 側の実装
/// （本 Issue のスコープ外。`packages/location/lib/src/position/` 等に置かれる想定）に
/// 委ねる。`core` 側のテスト（`test/disclosure/`）ではフェイク実装
/// （`FakeHexLocator`）を注入し、実際の座標変換なしに開示判定ロジックを検証する
/// （GPS_ARCHITECTURE 準拠・plan.md §10）。
///
/// ## 「細分グリッドセル通過→ヘクスへの集約」との対応関係（設計判断の明記）
/// `docs/terrain.md` §4.1 は「内部の開示判定はグリッドセル単位で行い、ヘクス単位で
/// 集約する」としているが、同じ §4.1 の文中で「セル群の地形タグの**多数決**で
/// ヘクス全体の地形タイプを1つに確定する」という多数決が明示的にかかっているのは
/// **地形タイプの確定**（パック生成時・`RegionPack.terrainOf` の元データ）に対してのみで
/// あり、続く「開示判定（霧が晴れているか）もヘクス単位で集約する」という一文には
/// 「多数決」という語がかかっていない（§4.1・§4.3 を参照。`多数決` という語が
/// 現れる箇所はすべて地形タイプの確定に関するものであることを
/// `docs/terrain.md`・`specs/001-mvp/plan.md`・`specs/001-mvp/research.md` 全体で確認済み）。
///
/// 1つの細分グリッドセルは（パック生成時の定義上）必ずちょうど1つのヘクスに属するため、
/// 「あるグリッドセルを通過した」という事実は「そのセルを包含するヘクスを訪れた」という
/// 事実へ一意に写像できる（複数候補から多数決で選ぶ必要がない）。このため本抽象は
/// 「緯度経度→細分グリッドセル」「細分グリッドセル→ヘクス」の2段階を `core` 側の型
/// （例: `GridCellId`）として分けて持たず、`location/` が両方をまとめて実装した結果
/// （＝ちょうど plan.md §5 の言う「事前計算済みの `HexId`」）だけを [locate] で
/// 受け取る1段階の抽象にしている。開示判定（[DisclosureService]）側の
/// 「複数グリッドセル通過→ヘクスへの集約」は、[locate] が同じヘクス内の異なる位置に
/// 対して同じ [HexId] を返すこと自体によって表現される（＝ヘクス単位への集約は
/// [HexLocator] の実装が担い、開示が真偽値である以上、集約関数は「多数決」ではなく
/// 「1回でも訪れたセルがあれば開示（論理和）」になる。詳細は
/// `disclosure_service.dart` のクラスdocコメント参照）。
abstract interface class HexLocator {
  /// [position] が属するヘクスの [HexId] を返す。
  ///
  /// 実装（`location/`）は、同一のヘクスに属する異なる緯度経度からは常に
  /// 同一の [HexId] を返すことを保証すること（決定論。`docs/terrain.md` §4.3）。
  /// パック範囲外の位置に対する挙動は実装依存（`RegionPack.terrainOf` 側で
  /// 範囲外を `null` として扱う設計と対応させ、[DisclosureService] 側では
  /// 「[HexId] は返るが `RegionPack.terrainOf` が `null`」を範囲外として扱う）。
  ///
  /// 【Issue #108 追記】本番実装は `packages/location` の `RecordedHexLocator`。
  /// 緯度経度→H3変換そのものは記録時点（Kotlin 側 `H3HexIndexer`）で既に確定して
  /// おり、[GeoPosition.hexId] に格納済みの値をそのまま返すだけになった（以前の
  /// `H3HexLocator`〔Dart側 `h3_flutter`〕は撤去済み）。この変更後も本抽象・
  /// クラスdocの設計判断（`core` に変換ロジックを持ち込まない）自体は変わらない。
  HexId locate(GeoPosition position);
}
