import '../terrain/terrain_type.dart';
import 'disclosed_hex.dart';
import 'pack_version.dart';
import 'region_pack.dart';

/// パック更新の不変性ルール（T036・Issue #84）を実装する純粋ロジック。
///
/// 出典: `specs/001-mvp/plan.md` §3.3「OSM データは変わる。一度開示したヘクスの
/// 資材分類は、パック更新後も過去分は不変とする（獲得履歴は当時の `pack_version` で
/// 確定）」。これが無いと「昨日まで森だった土地が今日は空き地になり、過去の獲得が
/// 揺らぐ」ことが起きる（Issue #84 本文）。
///
/// ## ルール
/// 開示済みヘクスの資材分類（[TerrainType]）を問い合わせるときは、**現在アクティブな
/// （更新後の）[RegionPack] へ直接問い合わせてはならない**。必ず、そのヘクスが
/// 開示された時点の [PackVersion]（[DisclosedHex.discoveredAtVersion]）に対応する
/// [RegionPack] から取得すること。本クラスはその解決だけを行う。
///
/// 新規のヘクス開示（まだ [DisclosedHex] が存在しない）で「現在アクティブなパックの
/// 地形分類を採用する」判定自体は、実際の開示判定ロジック（US1・T054）の責務であり、
/// 本 Issue のスコープ外。本クラスは「開示済みヘクスの過去分類を確定する」ことだけを
/// 担当する。
///
/// ## パックのバージョン管理について
/// 本クラスは複数バージョンの [RegionPack] をレジストリとして保持する。これは
/// 「パック更新後も過去バージョンの [RegionPack] を（少なくとも不変性ルールの解決に
/// 必要な間は）参照可能にしておく」ことを implementation 側（`location/`）に要求する
/// ものである。具体的な保持戦略（旧パックファイルを保持し続けるか、開示時点で分類を
/// スナップショットして小さく保持するか等）は `location/`（`RegionPackRepository`・
/// tasks.md T069）側の設計判断であり、本 Issue のスコープ外。
///
/// 本クラスは SQLite 等の永続化手段を一切知らない（GPS_ARCHITECTURE 準拠）。
/// `disclosed_hex` テーブルからの読み出し・複数バージョンの [RegionPack] のロードは
/// `location/` 側の責務であり、本クラスはそれらを引数として受け取る純粋ロジックである。
class PackVersionResolver {
  final Map<PackVersion, RegionPack> _packsByVersion;

  /// [packs] に同一 [PackVersion] のパックが複数含まれる場合、後勝ちで上書きされる
  /// （呼び出し側が重複を渡さないことを前提とする）。
  PackVersionResolver(Iterable<RegionPack> packs)
      : _packsByVersion = {
          for (final pack in packs) pack.version: pack,
        };

  /// 現在レゾルバに登録されているパックバージョンの一覧（デバッグ・テスト用）。
  Iterable<PackVersion> get availableVersions => _packsByVersion.keys;

  /// [disclosedHex] が開示された時点の地形分類を返す。
  ///
  /// 開示当時のバージョンに対応する [RegionPack] が本レゾルバに存在しない場合
  /// （パックが更新され旧バージョンが破棄された等）は [PackVersionUnavailable] を
  /// 投げる。**現在アクティブなパックへ黙ってフォールバックしない**——それは
  /// 不変性ルール（plan.md §3.3）そのものへの違反になるため、フォールバックが必要な
  /// 場面（例: 旧パックを保持しない設計にする場合の代替手段）が生じたときは、
  /// このメソッドの契約を変えるのではなく、`location/` 側で開示時点の分類を
  /// スナップショットして保持する設計に倒すこと。
  TerrainType? resolveTerrain(DisclosedHex disclosedHex) {
    final pack = _packsByVersion[disclosedHex.discoveredAtVersion];
    if (pack == null) {
      throw PackVersionUnavailable(disclosedHex.discoveredAtVersion);
    }
    return pack.terrainOf(disclosedHex.hexId);
  }
}

/// [PackVersionResolver] に、開示当時の [PackVersion] に対応する [RegionPack] が
/// 登録されていない場合に投げられる例外。
///
/// この例外は「バグ」ではなく「不変性ルールを守るための積極的な失敗」である。
/// 現在アクティブなパックへ静かにフォールバックすると、資材分類が
/// パック更新のたびに揺らいでしまう（plan.md §3.3 が禁止する事態）ため、
/// 呼び出し側（`location/`）に対応（旧パックの保持・分類のスナップショット等）を
/// 促す目的で明示的に例外を送出する。
class PackVersionUnavailable implements Exception {
  final PackVersion version;

  const PackVersionUnavailable(this.version);

  @override
  String toString() =>
      'PackVersionUnavailable: pack_version=$version に対応する RegionPack が '
      'PackVersionResolver に登録されていません。不変性ルール（plan.md §3.3）により '
      '現在アクティブなパックへの黙示的フォールバックは行いません。'
      '旧パックの保持、または開示時点の分類のスナップショット保持を検討してください。';
}
