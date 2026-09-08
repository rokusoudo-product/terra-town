import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  // 【役割分担・Issue #57】色の正しさ（DESIGN.md の fog トークンと一致すること）は
  // composition root である app 側のテスト
  // （app/test/map/fog_of_war_layer_factory_test.dart）が担保する。
  // location 側のこのテストはフェイク値を渡し、「コンストラクタで受け取った値を
  // そのまま保持するだけ」であることのみを検証する（location は配色を知らない）。
  test('FogOfWarLayer はコンストラクタで受け取った色・不透明度をそのまま保持する', () {
    const layer = FogOfWarLayer(fillColorHex: '#ABCDEF', fillOpacity: 0.5);

    expect(layer.fillColorHex, '#ABCDEF');
    expect(layer.fillOpacity, 0.5);
  });
}
