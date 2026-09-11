import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'package:terra_town/map/disclosure/disclosure_restore.dart';

class _InMemoryDisclosedHexRepository implements Repository<DisclosedHex, HexId> {
  final Map<HexId, DisclosedHex> _store = {};

  void seed(DisclosedHex entity) => _store[entity.hexId] = entity;

  @override
  Future<DisclosedHex?> findById(HexId id) async => _store[id];

  @override
  Future<List<DisclosedHex>> findAll() async => _store.values.toList();

  @override
  Future<void> save(DisclosedHex entity) async => _store[entity.hexId] = entity;

  @override
  Future<void> delete(HexId id) async => _store.remove(id);
}

DisclosedHex _disclosed(int hexId, {TerrainType terrainType = TerrainType.forest}) =>
    DisclosedHex(
      hexId: HexId(hexId),
      terrainType: terrainType,
      discoveredAtVersion: const PackVersion('v1'),
    );

void main() {
  group('restoreDisclosedHexes', () {
    test('保存済みの全ヘクスをknownへ追加し、featureIdでrevealを呼ぶ', () async {
      final repository = _InMemoryDisclosedHexRepository()
        ..seed(_disclosed(1))
        ..seed(_disclosed(2))
        ..seed(_disclosed(3));
      final known = DisclosedHexSet();
      final revealed = <int>[];

      final stats = await restoreDisclosedHexes(
        repository: repository,
        known: known,
        reveal: (featureId) async => revealed.add(featureId),
      );

      expect(stats.hexCount, 3);
      expect(known.contains(const HexId(1)), isTrue);
      expect(known.contains(const HexId(2)), isTrue);
      expect(known.contains(const HexId(3)), isTrue);
      expect(
        revealed.toSet(),
        {1, 2, 3}.map(hexIdToFeatureId).toSet(),
      );
    });

    test('保存済みヘクスが無い場合はhexCount=0で例外を投げない', () async {
      final stats = await restoreDisclosedHexes(
        repository: _InMemoryDisclosedHexRepository(),
        known: DisclosedHexSet(),
        reveal: (featureId) async {},
      );

      expect(stats.hexCount, 0);
    });

    test('chunkSizeを超える件数でも全件revealされる（分割ディスパッチの正しさ）', () async {
      final repository = _InMemoryDisclosedHexRepository();
      for (var i = 1; i <= 1200; i++) {
        repository.seed(_disclosed(i));
      }
      final revealed = <int>[];

      final stats = await restoreDisclosedHexes(
        repository: repository,
        known: DisclosedHexSet(),
        reveal: (featureId) async => revealed.add(featureId),
        chunkSize: 500,
      );

      expect(stats.hexCount, 1200);
      expect(revealed, hasLength(1200));
      expect(revealed.toSet(), hasLength(1200), reason: '重複や取りこぼしが無いこと');
    });

    test('knownへの追加はrevealの完了を待たずに全件終える（呼び出し順序の検証）', () async {
      final repository = _InMemoryDisclosedHexRepository()
        ..seed(_disclosed(1))
        ..seed(_disclosed(2));
      final known = DisclosedHexSet();
      final revealStarted = <int>[];

      await restoreDisclosedHexes(
        repository: repository,
        known: known,
        reveal: (featureId) async {
          revealStarted.add(featureId);
          // known へのすべての追加が完了した後であることを、reveal 呼び出しの
          // 時点で確認する（advisor 指摘の順序保証の回帰テスト）。
          expect(known.contains(const HexId(1)), isTrue);
          expect(known.contains(const HexId(2)), isTrue);
        },
      );

      expect(revealStarted, hasLength(2));
    });
  });
}
