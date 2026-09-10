import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town/map/initial_camera.dart';

/// バーティカルスライス対象エリア（狭山湖周辺）の **OSM 抽出 bbox**。
///
/// 値の根拠: `tools/pack-builder` が出力する `pack.json`
/// （2026-09-10 実測・`pack_version = sayamako-v1-9a66e066b0d4`）。
///
/// ⚠️ `tiles.mbtiles` の metadata `bounds`/`center` を使ってはならない。
/// あれは **タイル境界にパディングされた範囲** であり、OSM 抽出データが実際に
/// 入っている範囲ではない（2026-09-10 実機で判明。詳細は `initial_camera.dart`）。
const double _lonMin = 139.352;
const double _lonMax = 139.408;
const double _latMin = 35.7675;
const double _latMax = 35.8125;

void main() {
  // このテストは「特定の座標と一致すること」ではなく
  // 「カメラが実データの入っている範囲の内側を向いていること」を検証する。
  // 座標を固定するだけのテストでは、パディング済み範囲の中心（データの外側）を
  // 指してしまった 2026-09-10 の不具合を検出できなかった。
  test('初期カメラが OSM 抽出 bbox の内側を指す', () {
    final position = sayamakoInitialCameraPosition();

    expect(
      position.latitude,
      inInclusiveRange(_latMin, _latMax),
      reason: '初期カメラの緯度が抽出 bbox の外にあると、タイルは存在しても中身が空で画面が空白になる',
    );
    expect(
      position.longitude,
      inInclusiveRange(_lonMin, _lonMax),
      reason: '初期カメラの経度が抽出 bbox の外にあると、タイルは存在しても中身が空で画面が空白になる',
    );
  });

  test('初期カメラが OSM 抽出 bbox の中心を指す', () {
    final position = sayamakoInitialCameraPosition();

    expect(position.latitude, closeTo((_latMin + _latMax) / 2, 1e-9));
    expect(position.longitude, closeTo((_lonMin + _lonMax) / 2, 1e-9));
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
