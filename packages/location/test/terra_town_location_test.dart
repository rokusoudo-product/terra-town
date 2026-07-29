import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  // location から core を参照できること（許可された依存方向）の疎通テスト。
  test('location は core を参照できる', () {
    expect(locationScaffoldMarker(), 'terra_town_location -> terra_town_core');
  });
}
