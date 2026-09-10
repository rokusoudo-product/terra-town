import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  // research.md §6.2 で実機成立を確認した構文（`mbtiles://` + 絶対パス）を
  // そのまま組み立てられることだけを検証する純粋関数のテスト。
  test('mbtilesSourceUrl はローカルパスの前に mbtiles:// を付与する', () {
    expect(
      mbtilesSourceUrl('/data/user/0/com.example.app/tiles.mbtiles'),
      'mbtiles:///data/user/0/com.example.app/tiles.mbtiles',
    );
  });

  test('相対パスであってもそのまま連結する（絶対パスの保証は呼び出し側の責務）', () {
    expect(mbtilesSourceUrl('tiles.mbtiles'), 'mbtiles://tiles.mbtiles');
  });
}
