import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

import '../position/fake_position_provider.dart';

/// 録画済み歩行ルートのリプレイテスト（T053・Issue #101）。
///
/// plan.md §10「`PositionProvider` のフェイク実装＋録画済み歩行ルートのリプレイテスト」を
/// [DisclosureService] に対して行い、**同じ歩行ルートからは常に同じヘクス集合が出る**
/// （決定論・受け入れ基準）ことを検証する。位置情報の供給には T051 で抽出した
/// [FakePositionProvider] を使い、`PositionProvider.positionUpdates` を
/// [DisclosureService.disclose] にそのまま渡せることも同時に実証する。

/// `test/disclosure/disclosure_test.dart` の `_GridHexLocator` と同じ手法（テスト専用の
/// 単純な緯度経度→ヘクスID量子化。実際のH3変換は持ち込まない）。
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

  static int _pair(int a, int b) {
    final za = a >= 0 ? a * 2 : -a * 2 - 1;
    final zb = b >= 0 ? b * 2 : -b * 2 - 1;
    return ((za + zb) * (za + zb + 1)) ~/ 2 + zb;
  }
}

class _FakeRegionPack implements RegionPack {
  _FakeRegionPack({required this.version, this.terrainByHex = const {}});

  @override
  final PackVersion version;

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

class _InMemoryDisclosedHexRepository implements Repository<DisclosedHex, HexId> {
  final Map<HexId, DisclosedHex> _store = {};

  @override
  Future<DisclosedHex?> findById(HexId id) async => _store[id];

  @override
  Future<List<DisclosedHex>> findAll() async => _store.values.toList();

  @override
  Future<void> save(DisclosedHex entity) async => _store[entity.hexId] = entity;

  @override
  Future<void> delete(HexId id) async => _store.remove(id);
}

GeoPosition _pos(int minuteOffset, double lat, double lon) => GeoPosition(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.utc(2026, 9, 10, 9, 0).add(Duration(minutes: minuteOffset)),
    );

/// 「録画済み歩行ルート」フィクスチャ。空き地スポーン地点から森・山・海のヘクスを経由し、
/// 森ヘクス内を細かく往復してから水辺ヘクスへ戻る、という歩行パターンを模す。
/// 同じヘクス内での往復（森ヘクスの2〜4番目）が「グリッドセル通過→ヘクスへの集約で
/// 開示は1回だけ」であることの検証を兼ねる。
List<GeoPosition> _recordedWalkingRoute() => [
      _pos(0, 35.0000, 135.0000), // 空き地ヘクスA
      _pos(1, 35.0010, 135.0000), // 森ヘクスBへ移動
      _pos(2, 35.0011, 135.0001), // 森ヘクスB内の別グリッドセル（開示は増えない）
      _pos(3, 35.0012, 135.0002), // 森ヘクスB内のさらに別グリッドセル（開示は増えない）
      _pos(4, 35.0020, 135.0000), // 山ヘクスCへ移動
      _pos(5, 35.0030, 135.0000), // 海ヘクスDへ移動
      _pos(6, 35.0010, 135.0000), // 森ヘクスBへ戻る（既知なので開示は増えない）
    ];

/// フィクスチャの歩行ルートに対応する地形パック。ヘクスIDは [_GridHexLocator] の
/// 量子化結果に依存するため、テスト内で `locator.locate` を使って解決する。
_FakeRegionPack _packFor(_GridHexLocator locator) {
  final route = _recordedWalkingRoute();
  final terrainByHex = <HexId, TerrainType>{
    locator.locate(route[0]): TerrainType.vacantLot, // ヘクスA
    locator.locate(route[1]): TerrainType.forest, // ヘクスB
    locator.locate(route[4]): TerrainType.mountain, // ヘクスC
    locator.locate(route[5]): TerrainType.sea, // ヘクスD
  };
  return _FakeRegionPack(version: const PackVersion('sayamako-v1-replay-test'), terrainByHex: terrainByHex);
}

/// 録画ルートを [DisclosureService] でリプレイし、新規開示された [DisclosedHex] の列を返す。
/// 呼び出しのたびに独立した `known`/`repository`/`pack` を新規に組み立てるため、
/// 複数回呼んでも副作用は共有されない（決定論テストで使う）。
Future<List<DisclosedHex>> _replay() async {
  const locator = _GridHexLocator();
  final pack = _packFor(locator);
  final positionProvider = FakePositionProvider(_recordedWalkingRoute());
  final service = DisclosureService(
    hexLocator: locator,
    regionPack: pack,
    known: DisclosedHexSet(),
    repository: _InMemoryDisclosedHexRepository(),
  );

  return service.disclose(positionProvider.positionUpdates).toList();
}

void main() {
  group('録画済み歩行ルートのリプレイ（DisclosureService）', () {
    test('録画ルートをリプレイすると、通過した4つのヘクス（空き地・森・山・海）がそれぞれ1回ずつ開示される', () async {
      final disclosed = await _replay();

      const locator = _GridHexLocator();
      final route = _recordedWalkingRoute();
      final hexA = locator.locate(route[0]);
      final hexB = locator.locate(route[1]);
      final hexC = locator.locate(route[4]);
      final hexD = locator.locate(route[5]);

      // 開示は歩行順（森ヘクスB内の往復・再訪問では増えない）。
      expect(disclosed.map((d) => d.hexId).toList(), [hexA, hexB, hexC, hexD]);
      expect(
        disclosed.map((d) => d.terrainType).toList(),
        [TerrainType.vacantLot, TerrainType.forest, TerrainType.mountain, TerrainType.sea],
      );
      for (final d in disclosed) {
        expect(d.discoveredAtVersion, const PackVersion('sayamako-v1-replay-test'));
      }
    });

    test('同じ録画ルートを2回リプレイしても、常に同じヘクス集合・同じ開示内容になる（決定論）', () async {
      final firstRun = await _replay();
      final secondRun = await _replay();

      // hexId・terrainType・discoveredAtVersion まで含めた完全一致を確認する
      // （DisclosedHex の == が全フィールドを比較することを利用）。
      expect(secondRun, firstRun);
      expect(firstRun, isNotEmpty);
    });
  });
}
