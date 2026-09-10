import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town/map/initial_camera.dart';

void main() {
  // 値の根拠は tools/pack-builder/README.md「実測（2026-09-10・狭山湖周辺エリア）」の
  // tiles.mbtiles metadata 実測値（center = 139.41317,35.82581）。推測していない。
  test('狭山湖周辺エリアの中心座標を指す', () {
    final position = sayamakoInitialCameraPosition();

    expect(position.latitude, 35.82581);
    expect(position.longitude, 139.41317);
  });

  test('建物レイヤー(minzoom 13)が見えるズームを採用する', () {
    final position = sayamakoInitialCameraPosition();

    expect(position.zoom, greaterThanOrEqualTo(13));
  });

  test('カメラに傾き(tilt)を付ける（DESIGN.md アートディレクション技術的含意(1)）', () {
    final position = sayamakoInitialCameraPosition();

    expect(position.tilt, greaterThan(0));
  });
}
