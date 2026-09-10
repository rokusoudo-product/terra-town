import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

import 'fake_position_provider.dart';

/// plan.md §10「テストでは PositionProvider のフェイク実装＋録画済み歩行ルートの
/// リプレイテストを行う」の実証。[FakePositionProvider]（T051・Issue #101で
/// `fake_position_provider.dart` へ抽出。旧・本ファイル内定義）は固定の [GeoPosition] 列を
/// [PositionProvider.positionUpdates] から流すだけのフェイクであり、実 GPS・地図SDKには
/// 一切依存しない（`tools/check_import_direction.sh` が test/ も走査するため、ここに
/// GPS/地図SDK 由来の import が無いこと自体が「core が GPS 型を露出していない」ことの
/// 裏付けになる）。

void main() {
  group('PositionProvider', () {
    test('core はフェイク実装を注入して位置更新の Stream を購読できる', () async {
      final route = [
        GeoPosition(latitude: 35.0, longitude: 135.0, timestamp: DateTime.utc(2026, 9, 9, 9, 0)),
        GeoPosition(latitude: 35.001, longitude: 135.001, timestamp: DateTime.utc(2026, 9, 9, 9, 1)),
      ];
      final PositionProvider provider = FakePositionProvider(route);

      final received = await provider.positionUpdates.toList();

      expect(received, route);
    });

    test('録画済みルートが空でも例外にならず、更新が来ないだけの Stream になる', () async {
      final PositionProvider provider = FakePositionProvider(const []);

      final received = await provider.positionUpdates.toList();

      expect(received, isEmpty);
    });
  });
}
