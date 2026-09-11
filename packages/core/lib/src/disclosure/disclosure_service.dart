import '../antispoof/reward_policy.dart';
import '../geo/hex_id.dart';
import '../pack/disclosed_hex.dart';
import '../pack/disclosed_hex_set.dart';
import '../pack/region_pack.dart';
import '../position/geo_position.dart';
import '../repository/repository.dart';
import 'hex_locator.dart';

/// 「歩いた場所の霧が晴れる」の判定ロジック（T054・Issue #101）。
///
/// `spec.md` §4 のコアループの入口にあたる US1 のコア機能。**GPS/地図SDKに一切
/// 依存しない純粋ロジック**として実装する（GPS_ARCHITECTURE 準拠）。
///
/// ## 入力（すべて抽象経由）
/// - 位置情報の列: `PositionProvider.positionUpdates`（`Stream<GeoPosition>`）を
///   そのまま渡せるよう [disclose] は `Stream<GeoPosition>` を受け取る。
/// - 緯度経度→ヘクスIDの変換: [HexLocator]（本 Issue で新規定義。ドキュメント参照）。
///   `core` は変換ロジックを自前で持たない。
/// - 地形分類: [RegionPack.terrainOf]。**新規開示の瞬間にのみ**呼ぶ（下記参照）。
///
/// ## 開示判定のアルゴリズム（`docs/terrain.md` §4 の折衷方式に従う）
/// 0. [RewardPolicy.allowsDisclosure] で偽装（モック位置）の疑いを確認する
///    （Issue #126・T099）。疑いがあれば以降の処理は一切行わず `null` を返す
///    （開拓の無効化。Issue #9 代表回答 9-1 の最も強いペナルティ段階）。
///    速度超過・歩数不一致はここでは判定しない（開拓を止めるのはモックのみ）。
/// 1. 位置ごとに [HexLocator.locate] でヘクスIDへ変換する
///    （細分グリッドセル→ヘクスへの写像は [HexLocator] 実装側の責務。
///    `hex_locator.dart` のドキュメント参照）。
/// 2. そのヘクスが既に開示済み（[known] に含まれる）なら何もしない（冪等）。
///    **同一ヘクス内の複数グリッドセルを何度通過しても、開示は最初の1回だけ**
///    ——これが `docs/terrain.md` §4.1「開示判定もヘクス単位で集約する」の実装であり、
///    集約関数は地形タイプ確定のような多数決ではなく論理和（1回でも訪れれば開示）
///    である（`hex_locator.dart` 参照）。
/// 3. 未開示なら [RegionPack.terrainOf] でそのヘクスの地形タイプを引く。
///    パック範囲外（`null`）なら開示扱いにしない（何も起きない）。
/// 4. 現行パックの地形タイプを [DisclosedHex.terrainType] としてスナップショットし、
///    [RegionPack.version] を [DisclosedHex.discoveredAtVersion] として記録した
///    [DisclosedHex] を組み立て、[repository] に保存する。
///    **[RegionPack.terrainOf] を呼んでよいのはこの瞬間だけ**（2026-09-10・Issue #96・
///    代表決定）。既に開示済みのヘクスの地形分類を問い合わせる経路はここには無い
///    （正は `DisclosedHex.terrainType`）。
/// 5. メモリ上の高速判定用インデックスである [known]（[DisclosedHexSet]・PR #95）に
///    ヘクスIDを追加する。**開示状態の正は [repository]（`disclosed_hex` テーブル
///    相当）であり [known] は派生インデックスに過ぎない**ため、[repository.save] の
///    完了後に [known] を更新する順序を守る（`disclosed_hex_set.dart` の
///    「開示状態の正について」参照）。
///
/// ## 決定論
/// [locate]・[terrainOf] が純関数（同じ入力に対し常に同じ出力）であり、
/// [disclose] 自体も位置の列を受け取った順に逐次処理する純粋なロジックであるため、
/// 同じ録画済み歩行ルートからは常に同じヘクス集合・同じ [DisclosedHex] の列が
/// 得られる（`test/disclosure/replay_walk_test.dart` で検証）。
///
/// ## スコープ外（Issue #101 本文の「スコープの厳守」参照）
/// - 永続化の実体（SQLite/Drift・T060・Issue #102）: [repository] は
///   `Repository<DisclosedHex, HexId>`（抽象。`repository.dart` T038）を受け取るのみで、
///   具象実装は持たない。
/// - アプリ起動時に [known] へ既存の開示済みヘクスを読み込む処理（T060）。
/// - 資材付与（T068・US2）・地図描画／fog of war（Issue #99・#100）。
class DisclosureService {
  DisclosureService({
    required this.hexLocator,
    required this.regionPack,
    required this.known,
    required this.repository,
  });

  /// 緯度経度→ヘクスIDの変換口（`location/` が実装する。テストではフェイクを注入）。
  final HexLocator hexLocator;

  /// 地形分類の読み取り口。[terrainOf] を呼ぶのは新規開示の瞬間のみ（クラスdoc参照）。
  final RegionPack regionPack;

  /// 開示済みヘクスの高速判定用インデックス（[DisclosedHexSet]・PR #95）。
  ///
  /// 呼び出し側がアプリ起動時に永続化層（T060）から復元して渡すことを想定する
  /// （本 Issue のスコープ外）。空のまま渡せば「まだ何も開示していない」状態になる。
  final DisclosedHexSet known;

  /// 開示履歴の永続化口（抽象・`repository.dart` T038）。実体は `location/`／`app/` 側。
  final Repository<DisclosedHex, HexId> repository;

  /// 1件の位置観測を処理する。
  ///
  /// 新規にヘクスが開示された場合はその [DisclosedHex] を返す。
  /// 既に開示済み、パック範囲外、または偽装（モック位置）の疑いがあり開拓不可
  /// （[RewardPolicy.allowsDisclosure]・Issue #126）で何も起きなかった場合は
  /// `null` を返す。
  Future<DisclosedHex?> recordPosition(GeoPosition position) async {
    // Issue #126（T099）: モック位置検出時は開拓そのものを無効化する
    // （Issue #9 代表回答 9-1「段階的ペナルティ」の最も強い段階）。
    // 速度超過・歩数不一致（[RewardPolicy] のウィンドウ判定）はここには
    // 持ち込まない（開拓を止めるのはモックのみ・`RewardPolicy` クラスdoc
    // 「開拓を止めるのはモックだけ」参照）。ヘクスへの変換（[hexLocator.locate]）
    // より前に確認し、無駄な計算・[known] への問い合わせを避ける。
    if (!RewardPolicy.allowsDisclosure(position)) {
      return null;
    }

    final hexId = hexLocator.locate(position);

    // ヘクス単位への集約（docs/terrain.md §4.1）: 既知のヘクスなら何もしない。
    if (known.contains(hexId)) {
      return null;
    }

    // 新規開示の瞬間にのみ RegionPack.terrainOf を呼ぶ（Issue #96・代表決定）。
    final terrainType = regionPack.terrainOf(hexId);
    if (terrainType == null) {
      // パック範囲外のヘクス。開示扱いにしない。
      return null;
    }

    final disclosed = DisclosedHex(
      hexId: hexId,
      terrainType: terrainType,
      discoveredAtVersion: regionPack.version,
    );

    // 開示状態の正（永続化）を先に確定してから、派生インデックスを更新する。
    await repository.save(disclosed);
    known.add(hexId);

    return disclosed;
  }

  /// 録画済み・またはリアルタイムの歩行ルート（[GeoPosition] の列）をリプレイし、
  /// 新規に開示されたヘクスを開示順に返す。
  ///
  /// `PositionProvider.positionUpdates` をそのまま渡せる（`Stream<GeoPosition>`）。
  /// 無限に更新が続く実運用のストリームに対しても使えるよう、[Stream] のまま
  /// 逐次処理する（`await for`）。テスト（`test/disclosure/replay_walk_test.dart`）では
  /// 有限の録画ルートを `Stream.fromIterable` で渡し、`.toList()` で結果を待ち受ける。
  Stream<DisclosedHex> disclose(Stream<GeoPosition> positions) async* {
    await for (final position in positions) {
      final disclosed = await recordPosition(position);
      if (disclosed != null) {
        yield disclosed;
      }
    }
  }
}
