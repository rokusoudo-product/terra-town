import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

void main() {
  // core が Flutter/GPS に依存せず `dart test` だけで回ることを確認する疎通テスト。
  // 実ドメインのテストは tasks.md Phase 3 以降で追加する。
  test('core パッケージが Flutter なしでテストできる', () {
    expect(coreScaffoldMarker, 'terra_town_core');
  });
}
