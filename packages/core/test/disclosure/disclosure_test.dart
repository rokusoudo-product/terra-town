import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

/// 開示判定ロジック（[DisclosureService]・T054・Issue #101）のテスト（T052）。
///
/// `docs/terrain.md` §4 の折衷方式をどう実装したかは `disclosure_service.dart`・
/// `hex_locator.dart` のクラスdocコメントに詳細を記載している。本テストが確認するのは:
///   - グリッドセル通過→ヘクス開示（同一ヘクス内の複数グリッドセル通過は開示1回だけ。
///     `docs/terrain.md` §4.1「開示判定もヘクス単位で集約する」の実装。集約関数が
///     多数決ではなく論理和である理由は `disclosure_service.dart` 参照）
///   - `RegionPack.terrainOf` は新規開示の瞬間に**1回だけ**呼ばれる（Issue #96）
///   - パック範囲外・既知ヘクスでは開示が起きない
///   - 開示された [DisclosedHex] に地形分類とパックバージョンが正しくスナップショットされる

/// テスト専用の緯度経度→ヘクスID変換フェイク。
///
/// 実際の H3 変換ロジック（`location/` の責務・`docs/terrain.md` §4.3）は一切持ち込まず、
/// 「緯度経度を細分グリッドセルへ量子化 → 複数のグリッドセルをまとめて1つのヘクスへ
/// 集約する」という §4.1 の構造だけを単純な整数演算で模したもの。[cellDegrees] が
/// 1グリッドセルの一辺（度）、[cellsPerHexEdge] が1ヘクスの一辺を構成するグリッドセル数
/// に相当する。
class _GridHexLocator implements HexLocator {
  const _GridHexLocator();

  static const double cellDegrees = 0.0001;
  static const int cellsPerHexEdge = 5;

  @override
  HexId locate(GeoPosition position) {
    final cellX = (position.longitude / cellDegrees).floor();
    final cellY = (position.latitude / cellDegrees).floor();
    final hexX = (cellX / cellsPerHexEdge).floor();
    final hexY = (cellY / cellsPerHexEdge).floor();
    return HexId(_pair(hexX, hexY));
  }

  /// 符号付き整数のペアを非負整数へ決定論的に折り畳む（zigzag符号化 + Cantor対関数）。
  /// H3 とは無関係の、テスト専用の単純な合成関数。
  static int _pair(int a, int b) {
    final za = a >= 0 ? a * 2 : -a * 2 - 1;
    final zb = b >= 0 ? b * 2 : -b * 2 - 1;
    return ((za + zb) * (za + zb + 1)) ~/ 2 + zb;
  }
}

/// 呼び出し回数を記録できる [RegionPack] フェイク（`region_pack_test.dart` の
/// `FakeRegionPack` と同じ手法に、[terrainOf] の呼び出し回数カウントを追加したもの）。
class _CountingFakeRegionPack implements RegionPack {
  _CountingFakeRegionPack({required this.version, this.terrainByHex = const {}});

  @override
  final PackVersion version;

  final Map<HexId, TerrainType> terrainByHex;

  final Map<HexId, int> terrainOfCallCounts = {};

  @override
  TerrainType? terrainOf(HexId hexId) {
    terrainOfCallCounts.update(hexId, (count) => count + 1, ifAbsent: () => 1);
    return terrainByHex[hexId];
  }

  @override
  DistrictId? districtOf(HexId hexId) => null;

  @override
  List<District> get districts => const [];

  @override
  List<PointOfInterest> get pointsOfInterest => const [];
}

/// [Repository]<[DisclosedHex], [HexId]> のオンメモリフェイク
/// （`repository_test.dart` の `InMemoryRepository` と同じ手法）。
class _InMemoryDisclosedHexRepository implements Repository<DisclosedHex, HexId> {
  final Map<HexId, DisclosedHex> _store = {};
  final List<DisclosedHex> saveCalls = [];

  @override
  Future<DisclosedHex?> findById(HexId id) async => _store[id];

  @override
  Future<List<DisclosedHex>> findAll() async => _store.values.toList();

  @override
  Future<void> save(DisclosedHex entity) async {
    saveCalls.add(entity);
    _store[entity.hexId] = entity;
  }

  @override
  Future<void> delete(HexId id) async => _store.remove(id);
}

GeoPosition _pos(double lat, double lon) => GeoPosition(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.utc(2026, 9, 10, 9, 0),
    );

void main() {
  group('DisclosureService.recordPosition', () {
    test('未開示ヘクスへの通過で開示され、地形分類とパックバージョンがスナップショットされる', () async {
      const locator = _GridHexLocator();
      final position = _pos(35.0, 135.0);
      final hexId = locator.locate(position);
      final pack = _CountingFakeRegionPack(
        version: const PackVersion('sayamako-v1-test'),
        terrainByHex: {hexId: TerrainType.forest},
      );
      final repository = _InMemoryDisclosedHexRepository();
      final service = DisclosureService(
        hexLocator: locator,
        regionPack: pack,
        known: DisclosedHexSet(),
        repository: repository,
      );

      final disclosed = await service.recordPosition(position);

      expect(disclosed, isNotNull);
      expect(disclosed!.hexId, hexId);
      expect(disclosed.terrainType, TerrainType.forest);
      expect(disclosed.discoveredAtVersion, const PackVersion('sayamako-v1-test'));
      expect(repository.saveCalls, [disclosed]);
    });

    test(
        '同一ヘクス内の複数グリッドセルを通過しても開示は最初の1回だけ'
        '（多数決ではなく論理和での集約・terrainOfも1回だけ呼ばれる）', () async {
      const locator = _GridHexLocator();
      // 同一の粗いヘクスバケットに属するが、細分グリッドセルとしては異なる2点。
      final p1 = _pos(35.0000, 135.0000);
      final p2 = _pos(35.0001, 135.0001);
      final hex1 = locator.locate(p1);
      final hex2 = locator.locate(p2);
      expect(hex1, hex2, reason: 'テスト前提: p1・p2 は同じヘクスに属する異なるグリッドセル');

      final pack = _CountingFakeRegionPack(
        version: const PackVersion('v1'),
        terrainByHex: {hex1: TerrainType.mountain},
      );
      final repository = _InMemoryDisclosedHexRepository();
      final service = DisclosureService(
        hexLocator: locator,
        regionPack: pack,
        known: DisclosedHexSet(),
        repository: repository,
      );

      final first = await service.recordPosition(p1);
      final second = await service.recordPosition(p2);

      expect(first, isNotNull);
      expect(second, isNull, reason: '既に開示済みのヘクスへの再訪問は新規開示にならない');
      expect(pack.terrainOfCallCounts[hex1], 1, reason: 'terrainOfは新規開示の瞬間に1回だけ');
      expect(repository.saveCalls, hasLength(1));
    });

    test('ヘクスの境界をまたぐ通過は2件開示される', () async {
      const locator = _GridHexLocator();
      final p1 = _pos(35.0000, 135.0000);
      final p2 = _pos(35.0010, 135.0000); // 別のヘクスバケットに属する
      final hex1 = locator.locate(p1);
      final hex2 = locator.locate(p2);
      expect(hex1, isNot(hex2), reason: 'テスト前提: p1・p2 は異なるヘクスに属する');

      final pack = _CountingFakeRegionPack(
        version: const PackVersion('v1'),
        terrainByHex: {hex1: TerrainType.forest, hex2: TerrainType.waterside},
      );
      final repository = _InMemoryDisclosedHexRepository();
      final service = DisclosureService(
        hexLocator: locator,
        regionPack: pack,
        known: DisclosedHexSet(),
        repository: repository,
      );

      final first = await service.recordPosition(p1);
      final second = await service.recordPosition(p2);

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect({first!.hexId, second!.hexId}, {hex1, hex2});
      expect(repository.saveCalls, hasLength(2));
    });

    test('地域パック範囲外（terrainOfがnull）の位置は開示されず、保存もされない', () async {
      const locator = _GridHexLocator();
      final position = _pos(35.0, 135.0);
      final pack = _CountingFakeRegionPack(
        version: const PackVersion('v1'),
        terrainByHex: const {}, // このヘクスは未収録
      );
      final repository = _InMemoryDisclosedHexRepository();
      final known = DisclosedHexSet();
      final service = DisclosureService(
        hexLocator: locator,
        regionPack: pack,
        known: known,
        repository: repository,
      );

      final disclosed = await service.recordPosition(position);

      expect(disclosed, isNull);
      expect(repository.saveCalls, isEmpty);
      expect(known.isEmpty, isTrue);
    });

    test('起動時に既に開示済み（knownへ事前登録済み）のヘクスは、何度訪れてもterrainOfが呼ばれない', () async {
      const locator = _GridHexLocator();
      final position = _pos(35.0, 135.0);
      final hexId = locator.locate(position);
      final pack = _CountingFakeRegionPack(
        version: const PackVersion('v1'),
        terrainByHex: {hexId: TerrainType.sea},
      );
      final repository = _InMemoryDisclosedHexRepository();
      // T060（本Issueのスコープ外）を模して、永続化層から復元済みの状態を再現する。
      final known = DisclosedHexSet.from([hexId]);
      final service = DisclosureService(
        hexLocator: locator,
        regionPack: pack,
        known: known,
        repository: repository,
      );

      final first = await service.recordPosition(position);
      final second = await service.recordPosition(position);

      expect(first, isNull);
      expect(second, isNull);
      expect(pack.terrainOfCallCounts[hexId], isNull, reason: '既知ヘクスではterrainOfを一度も呼ばない');
      expect(repository.saveCalls, isEmpty);
    });

    test('新規開示のたびに DisclosedHexSet(known) が更新され、以後の高速判定に反映される', () async {
      const locator = _GridHexLocator();
      final position = _pos(35.0, 135.0);
      final hexId = locator.locate(position);
      final pack = _CountingFakeRegionPack(
        version: const PackVersion('v1'),
        terrainByHex: {hexId: TerrainType.vacantLot},
      );
      final known = DisclosedHexSet();
      final service = DisclosureService(
        hexLocator: locator,
        regionPack: pack,
        known: known,
        repository: _InMemoryDisclosedHexRepository(),
      );

      expect(known.contains(hexId), isFalse);
      await service.recordPosition(position);
      expect(known.contains(hexId), isTrue);
    });
  });

  group('DisclosureService.disclose (Stream)', () {
    test('位置情報のStreamを順に処理し、新規開示分だけをその順序で流す', () async {
      const locator = _GridHexLocator();
      final p1 = _pos(35.0000, 135.0000);
      final p2 = _pos(35.0001, 135.0001); // p1 と同じヘクス(再訪問・開示なし)
      final p3 = _pos(35.0010, 135.0000); // 別のヘクス(新規開示)
      final hex1 = locator.locate(p1);
      final hex3 = locator.locate(p3);

      final pack = _CountingFakeRegionPack(
        version: const PackVersion('v1'),
        terrainByHex: {hex1: TerrainType.forest, hex3: TerrainType.mountain},
      );
      final service = DisclosureService(
        hexLocator: locator,
        regionPack: pack,
        known: DisclosedHexSet(),
        repository: _InMemoryDisclosedHexRepository(),
      );

      final disclosedList = await service.disclose(Stream.fromIterable([p1, p2, p3])).toList();

      expect(disclosedList.map((d) => d.hexId), [hex1, hex3]);
    });
  });
}
