import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [RecordedHexLocator]（Issue #108）の単体テスト。
///
/// 変換ロジック自体は Kotlin 側（`H3HexIndexer`）に移り、本クラスは
/// [GeoPosition.hexId] を返すだけになったため、テストも「値をそのまま返すこと」
/// 「null の場合は fail-loud で StateError を投げること」の2点に絞られる。
/// h3-py との実測突き合わせは Kotlin 側テスト（`H3HexIndexerTest`）で行う。
void main() {
  const locator = RecordedHexLocator();

  test('GeoPosition.hexId が設定済みならその値をそのまま返す', () {
    // research.md §8.4 の実測最大値（2^53超）でも精度を落とさず扱えることを兼ねて確認する。
    const measuredMaxHexId = 626833456793083903;
    final position = GeoPosition(
      latitude: 35.777175,
      longitude: 139.407368,
      timestamp: DateTime.utc(2026, 9, 11),
      hexId: const HexId(measuredMaxHexId),
    );

    expect(locator.locate(position), const HexId(measuredMaxHexId));
  });

  test('GeoPosition.hexId が null の場合は StateError を投げる（配線バグの検知）', () {
    final position = GeoPosition(
      latitude: 35.777175,
      longitude: 139.407368,
      timestamp: DateTime.utc(2026, 9, 11),
    );

    expect(() => locator.locate(position), throwsStateError);
  });
}
