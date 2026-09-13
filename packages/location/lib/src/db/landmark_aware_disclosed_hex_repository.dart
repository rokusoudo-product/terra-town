// ignore_for_file: prefer_initializing_formals
// 公開の名前付き引数（regionPack・now）をプライベートフィールド（_regionPack・
// _now）へそのまま代入する箇所があり、initializing formal（this._regionPack 等）
// にすると外部呼び出し側の引数名がプライベート名になってしまうため使えない
// （`region_pack_repository.dart` と同じ判断）。

import 'package:terra_town_core/terra_town_core.dart';

import 'collection_repository.dart';
import 'disclosed_hex_repository.dart';
import 'game_database.dart';
import 'landmark_collection_support.dart';

/// 徒歩による開示（`DisclosureService.recordPosition` → `repository.save`）で、
/// `disclosed_hex` への保存と名所の収集記録（`collection`）を**同一
/// トランザクション**で行う `Repository<DisclosedHex, HexId>` の実装
/// （Issue #159・T070）。
///
/// ## なぜ `core` の `DisclosureService` を変更しないか
/// `DisclosureService.recordPosition`（`packages/core`）は
/// `repository.save(disclosed)` を呼ぶだけで、`Repository<DisclosedHex, HexId>`
/// という抽象越しにしか永続化層を知らない。名所の収集記録は `location` 側の
/// 関心事（`RegionPack.pointsOfInterestIn`・`collection` テーブルへの実書き込み）
/// であるため、`core` 側のインターフェースは変えず、本デコレータで
/// `save` の中身だけを差し替える（Issue #159 提案内容「徒歩経路用のリポジトリ
/// 実装で disclosed_hex と collection を1トランザクションで保存する」の実装）。
///
/// ## 同一トランザクション（受け入れ基準）
/// [save] は [GameDatabase.transaction] を1つ開き、その中で
/// [disclosedHexRepository.save]（`insertOrIgnore`）→ 名所の収集判定・保存
/// （[collectLandmarksForDisclosedHex]）の順に行う。どちらか一方だけが
/// コミットされる状態は起こらない（`HexOpeningSpendService` クラスdoc
/// 「消費と開示は同一トランザクション」と同じ方針）。
///
/// ## 既存開示済みヘクスへの遡及収集をしない（構造的な保証・advisor指摘）
/// トランザクション内で [disclosedHexRepository.findById] により**既に
/// 開示済みかどうかを明示的に再確認**し、既に開示済みであれば収集判定を
/// 一切行わずに終える。`DisclosedHexRepository.save` 自体は `insertOrIgnore`
/// のため二重呼び出しをしても例外にはならないが、その「無視されたかどうか」は
/// 戻り値から分からない。`known`（`DisclosedHexSet`）の復元漏れ・タイミングの
/// バグで万一同じヘクスに対して2回目の [save] が呼ばれても、本チェックにより
/// 「本Issue以前から開示済みだったヘクスの名所を今さら収集する」（Issue #159
/// 「対象外」に明記）ことが構造的に起こらない。
///
/// ## 新規収集の通知（[onCollected]）
/// 新規に収集された名所があれば、トランザクションがコミットされた**後**に
/// [onCollected] を呼ぶ（DBトランザクションの最中にUI更新の副作用を持ち込まない
/// ため）。`app` 側はこれを使って SnackBar 等の簡易表示を行う（Issue #159
/// 「新規収集をValueListenable等で公開し、地図画面で簡易表示する」）。
/// 本パッケージ（`location`）は Flutter の状態管理型（`ValueNotifier`等）を
/// 直接持たず、単純な callback に留めることで、DB層にUI層の関心事を
/// 持ち込まない（advisor指摘）。
class LandmarkAwareDisclosedHexRepository implements Repository<DisclosedHex, HexId> {
  LandmarkAwareDisclosedHexRepository(
    this._database, {
    required RegionPack regionPack,
    DisclosedHexRepository? disclosedHexRepository,
    CollectionRepository? collectionRepository,
    this.onCollected,
    DateTime Function() now = DateTime.now,
  })  : _regionPack = regionPack,
        _disclosedHexRepository =
            disclosedHexRepository ?? DisclosedHexRepository(_database),
        _collectionRepository =
            collectionRepository ?? CollectionRepository(_database),
        _now = now;

  final GameDatabase _database;
  final RegionPack _regionPack;
  final DisclosedHexRepository _disclosedHexRepository;
  final CollectionRepository _collectionRepository;
  final DateTime Function() _now;

  /// 新規に収集された名所がある場合に、トランザクションのコミット後に呼ばれる。
  final void Function(List<LandmarkCollectionRecord> records)? onCollected;

  @override
  Future<DisclosedHex?> findById(HexId id) => _disclosedHexRepository.findById(id);

  @override
  Future<List<DisclosedHex>> findAll() => _disclosedHexRepository.findAll();

  @override
  Future<void> delete(HexId id) => _disclosedHexRepository.delete(id);

  @override
  Future<void> save(DisclosedHex entity) async {
    var collected = const <LandmarkCollectionRecord>[];

    await _database.transaction(() async {
      // クラスdoc「既存開示済みヘクスへの遡及収集をしない」参照。
      final alreadyDisclosed = await _disclosedHexRepository.findById(entity.hexId);
      if (alreadyDisclosed != null) return;

      await _disclosedHexRepository.save(entity);

      collected = await collectLandmarksForDisclosedHex(
        disclosedHex: entity,
        regionPack: _regionPack,
        collectionRepository: _collectionRepository,
        collectMethod: CollectMethod.walk,
        now: _now,
      );
    });

    if (collected.isNotEmpty) {
      onCollected?.call(collected);
    }
  }
}
