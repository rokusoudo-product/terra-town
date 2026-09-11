import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'package:terra_town/map/disclosure/disclosure_coordinator.dart';

/// フェイクの [RegionPack]（`packages/core/test/pack/region_pack_test.dart` の
/// `FakeRegionPack` と同じ手法）。
class _FakeRegionPack implements RegionPack {
  _FakeRegionPack({required this.terrainByHex});

  @override
  final PackVersion version = const PackVersion('test-v1');

  final Map<HexId, TerrainType> terrainByHex;

  @override
  TerrainType? terrainOf(HexId hexId) => terrainByHex[hexId];

  @override
  DistrictId? districtOf(HexId hexId) => null;

  @override
  List<District> get districts => const [];

  @override
  List<PointOfInterest> get pointsOfInterest => const [];
}

/// `Repository<DisclosedHex, HexId>` のオンメモリフェイク
/// （`packages/core/test/disclosure/disclosure_test.dart` と同じ手法）。
class _InMemoryDisclosedHexRepository implements Repository<DisclosedHex, HexId> {
  final Map<HexId, DisclosedHex> _store = {};

  @override
  Future<DisclosedHex?> findById(HexId id) async => _store[id];

  @override
  Future<List<DisclosedHex>> findAll() async => _store.values.toList();

  @override
  Future<void> save(DisclosedHex entity) async {
    _store.putIfAbsent(entity.hexId, () => entity);
  }

  @override
  Future<void> delete(HexId id) async => _store.remove(id);
}

GeoPosition _positionFor(int hexId, {double lat = 35.0, double lon = 135.0}) =>
    GeoPosition(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.utc(2026, 9, 11),
      hexId: HexId(hexId),
      spoofSuspected: false,
    );

void main() {
  group('DisclosureCoordinator', () {
    test(
      '位置ストリームに新規ヘクスが流れると、開示判定を経て featureId でreveal が呼ばれる',
      () async {
        final revealed = <int>[];
        final controller = StreamController<GeoPosition>();
        final service = DisclosureService(
          hexLocator: const RecordedHexLocator(),
          regionPack: _FakeRegionPack(
            terrainByHex: {const HexId(1): TerrainType.forest},
          ),
          known: DisclosedHexSet(),
          repository: _InMemoryDisclosedHexRepository(),
        );
        final coordinator = DisclosureCoordinator(
          service: service,
          positionUpdates: controller.stream,
          reveal: (featureId) async => revealed.add(featureId),
        );

        coordinator.start();
        controller.add(_positionFor(1));
        // disclose() は Stream ベースの非同期処理のため、マイクロタスクの完了を待つ。
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(revealed, [hexIdToFeatureId(1)]);

        await controller.close();
        await coordinator.stop();
      },
    );

    test('既知（開示済み）のヘクスへの再訪問では reveal が呼ばれない', () async {
      final revealed = <int>[];
      final controller = StreamController<GeoPosition>();
      final known = DisclosedHexSet.from([const HexId(1)]);
      final service = DisclosureService(
        hexLocator: const RecordedHexLocator(),
        regionPack: _FakeRegionPack(
          terrainByHex: {const HexId(1): TerrainType.forest},
        ),
        known: known,
        repository: _InMemoryDisclosedHexRepository(),
      );
      final coordinator = DisclosureCoordinator(
        service: service,
        positionUpdates: controller.stream,
        reveal: (featureId) async => revealed.add(featureId),
      );

      coordinator.start();
      controller.add(_positionFor(1));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(revealed, isEmpty);

      await controller.close();
      await coordinator.stop();
    });

    test('start() を2回呼んでも購読は1つのまま（二重購読しない）', () async {
      final revealed = <int>[];
      final controller = StreamController<GeoPosition>();
      final service = DisclosureService(
        hexLocator: const RecordedHexLocator(),
        regionPack: _FakeRegionPack(
          terrainByHex: {const HexId(1): TerrainType.forest},
        ),
        known: DisclosedHexSet(),
        repository: _InMemoryDisclosedHexRepository(),
      );
      final coordinator = DisclosureCoordinator(
        service: service,
        positionUpdates: controller.stream,
        reveal: (featureId) async => revealed.add(featureId),
      );

      coordinator.start();
      coordinator.start(); // 2回目は無視される（クラスdoc参照）。
      controller.add(_positionFor(1));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // 二重購読していれば2回 reveal されるはずだが、1回だけであることを確認する。
      expect(revealed, [hexIdToFeatureId(1)]);

      await controller.close();
      await coordinator.stop();
    });

    test(
      'recordManualPosition は本番と同じ経路（recordPosition→reveal）を通り、'
      '新規開示ならDisclosedHexを返す',
      () async {
        final revealed = <int>[];
        final service = DisclosureService(
          hexLocator: const RecordedHexLocator(),
          regionPack: _FakeRegionPack(
            terrainByHex: {const HexId(42): TerrainType.mountain},
          ),
          known: DisclosedHexSet(),
          repository: _InMemoryDisclosedHexRepository(),
        );
        final coordinator = DisclosureCoordinator(
          service: service,
          positionUpdates: const Stream<GeoPosition>.empty(),
          reveal: (featureId) async => revealed.add(featureId),
        );

        final disclosed = await coordinator.recordManualPosition(_positionFor(42));

        expect(disclosed, isNotNull);
        expect(disclosed!.terrainType, TerrainType.mountain);
        expect(revealed, [hexIdToFeatureId(42)]);
      },
    );

    test('recordManualPosition はパック範囲外なら null を返し、reveal を呼ばない', () async {
      final revealed = <int>[];
      final service = DisclosureService(
        hexLocator: const RecordedHexLocator(),
        regionPack: _FakeRegionPack(terrainByHex: const {}),
        known: DisclosedHexSet(),
        repository: _InMemoryDisclosedHexRepository(),
      );
      final coordinator = DisclosureCoordinator(
        service: service,
        positionUpdates: const Stream<GeoPosition>.empty(),
        reveal: (featureId) async => revealed.add(featureId),
      );

      final disclosed = await coordinator.recordManualPosition(_positionFor(99));

      expect(disclosed, isNull);
      expect(revealed, isEmpty);
    });

    test('位置ストリームがエラーで終了しても例外は外に漏れない（onErrorでログのみ）', () async {
      final controller = StreamController<GeoPosition>();
      final service = DisclosureService(
        hexLocator: const RecordedHexLocator(),
        regionPack: _FakeRegionPack(terrainByHex: const {}),
        known: DisclosedHexSet(),
        repository: _InMemoryDisclosedHexRepository(),
      );
      final coordinator = DisclosureCoordinator(
        service: service,
        positionUpdates: controller.stream,
        reveal: (featureId) async {},
      );

      coordinator.start();
      controller.addError(StateError('配線バグ相当のエラー'));
      await Future<void>.delayed(Duration.zero);

      // ここまで到達すれば、ストリームのエラーが未処理例外として
      // テストランナーに漏れていないことの確認になる。
      await controller.close();
      await coordinator.stop();
    });
  });
}
