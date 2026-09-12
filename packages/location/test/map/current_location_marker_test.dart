import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  // 【役割分担・Issue #57】色の正しさ(DESIGN.mdのトークンと一致すること)は
  // composition rootであるapp側のテスト（app/test/map/
  // current_location_marker_factory_test.dart）が担保する。location側の
  // このテストはフェイク値を渡し、「コンストラクタで受け取った値をそのまま
  // 保持するだけ」であることのみを検証する（location は配色を知らない）。
  test(
    'CurrentLocationMarkerStyle はコンストラクタで受け取った値をそのまま保持する',
    () {
      const style = CurrentLocationMarkerStyle(
        fillColorHex: '#ABCDEF',
        strokeColorHex: '#112233',
        radius: 10,
        strokeWidth: 4,
      );

      expect(style.fillColorHex, '#ABCDEF');
      expect(style.strokeColorHex, '#112233');
      expect(style.radius, 10);
      expect(style.strokeWidth, 4);
    },
  );

  group('buildCurrentLocationFeatureCollection', () {
    // Issue #141 受け入れ基準「位置が未取得の場合の表示が決まっており、
    // テストがある」に対応する。決定: 未取得 = マーカーを出さない
    // （features が空の FeatureCollection を返す）。
    test('位置がnullの場合はfeaturesが空のFeatureCollectionを返す（マーカーを出さない）', () {
      final featureCollection = buildCurrentLocationFeatureCollection(null);

      expect(featureCollection['type'], 'FeatureCollection');
      expect(featureCollection['features'], isEmpty);
    });

    test('位置が渡された場合はその緯度経度を持つ1件のPoint Featureを返す', () {
      final position = GeoPosition(
        latitude: 35.79,
        longitude: 139.38,
        timestamp: DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
      );

      final featureCollection = buildCurrentLocationFeatureCollection(position);

      expect(featureCollection['type'], 'FeatureCollection');
      final features = featureCollection['features'] as List;
      expect(features, hasLength(1));
      final feature = features.single as Map<String, dynamic>;
      expect(feature['type'], 'Feature');
      final geometry = feature['geometry'] as Map<String, dynamic>;
      expect(geometry['type'], 'Point');
      // GeoJSON の座標順は [経度, 緯度]。
      expect(geometry['coordinates'], [139.38, 35.79]);
    });
  });

  group('CameraFollowTracker', () {
    // Issue #141 提案2「追従カメラのオン/オフ。利用者が地図を動かしたら
    // 追従を自動で解除する」の中核ロジック。
    test('markProgrammaticMove の直後の onCameraIdle は消費され、追従を解除しない', () {
      final tracker = CameraFollowTracker();

      tracker.markProgrammaticMove();

      expect(tracker.handleCameraIdle(followEnabled: true), isFalse);
    });

    test('markProgrammaticMove を呼んでいない onCameraIdle（利用者操作）は、追従オンなら解除を返す', () {
      final tracker = CameraFollowTracker();

      expect(tracker.handleCameraIdle(followEnabled: true), isTrue);
    });

    test('markProgrammaticMove を呼んでいない onCameraIdle でも、追従がオフなら解除を返さない', () {
      final tracker = CameraFollowTracker();

      expect(tracker.handleCameraIdle(followEnabled: false), isFalse);
    });

    test('markProgrammaticMove で消費されるのは次の1回だけ（その後は利用者操作として扱う）', () {
      final tracker = CameraFollowTracker();

      tracker.markProgrammaticMove();
      expect(tracker.handleCameraIdle(followEnabled: true), isFalse); // 自分の移動として消費

      // 2回目の onCameraIdle（markProgrammaticMove を呼んでいない）は利用者操作扱い。
      expect(tracker.handleCameraIdle(followEnabled: true), isTrue);
    });
  });
}
