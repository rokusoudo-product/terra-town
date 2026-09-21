import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [BuildableHighlightLayer]・[buildableHighlightFillLayerProperties]・
/// [BuildableHighlightController] を検証する（Issue #192。色の正しさ
/// （DESIGN.md の `success` トークンと一致すること）を担保する責務は `app` 側の
/// テストにあり、本ファイルはフェイク値を渡して式の組み立て・地図登録の挙動のみを
/// 検証する。役割分担は `terrain_tint_layer_test.dart` と同じ）。
void main() {
  const layer = BuildableHighlightLayer(
    fillColorHex: '#112233',
    fillOpacity: 0.35,
  );

  group('buildableHighlightFillLayerProperties', () {
    test('fill-color は指定した色をそのまま使う', () {
      final json = buildableHighlightFillLayerProperties(layer).toJson();
      expect(json['fill-color'], '#112233');
    });

    test(
      'fill-opacity は feature-state buildable が true のときだけ指定不透明度、それ以外は0',
      () {
        final json = buildableHighlightFillLayerProperties(layer).toJson();
        final opacityExpr = json['fill-opacity'] as List;

        expect(opacityExpr[0], 'case');
        expect(opacityExpr[1], const [
          'boolean',
          ['feature-state', 'buildable'],
          false,
        ]);
        expect(opacityExpr[2], 0.35);
        expect(opacityExpr[3], 0.0);
      },
    );
  });

  group('BuildableHighlightController.install', () {
    late _RecordingMapLibrePlatform platform;
    late MapLibreMapController controller;

    setUp(() {
      platform = _RecordingMapLibrePlatform();
      controller = MapLibreMapController(
        maplibrePlatform: platform,
        annotationOrder: const [],
        annotationConsumeTapEvents: const [],
      );
    });

    test('新しいソースを追加せず、fogと同じsourceIdに対して塗りレイヤーを1枚追加する', () async {
      await BuildableHighlightController.install(
        controller,
        layer,
        sourceId: 'terra_town_fog',
        belowLayerId: 'terra_town_fog_layer',
      );

      // addGeoJsonSource をオーバーライドしていないため、万一呼ばれれば
      // noSuchMethod 経由で例外になりテストが失敗する。
      expect(platform.addFillLayerCalls, hasLength(1));
      final call = platform.addFillLayerCalls.single;
      expect(call['sourceId'], 'terra_town_fog');
      expect(call['layerId'], BuildableHighlightController.defaultLayerId);
      expect(call['belowLayerId'], 'terra_town_fog_layer');
    });

    test('enableInteraction: false で追加する（霧のタップを吸わない）', () async {
      await BuildableHighlightController.install(
        controller,
        layer,
        sourceId: 'terra_town_fog',
      );

      expect(platform.addFillLayerCalls.single['enableInteraction'], isFalse);
    });

    test('カスタムのレイヤーIDを指定できる', () async {
      final result = await BuildableHighlightController.install(
        controller,
        layer,
        sourceId: 'terra_town_fog',
        layerId: 'custom_highlight',
      );

      expect(result.layerId, 'custom_highlight');
      expect(platform.addFillLayerCalls.single['layerId'], 'custom_highlight');
    });
  });

  group('BuildableHighlightController.setHighlighted / clear', () {
    late _RecordingMapLibrePlatform platform;
    late MapLibreMapController controller;
    late BuildableHighlightController highlightController;

    setUp(() async {
      platform = _RecordingMapLibrePlatform();
      controller = MapLibreMapController(
        maplibrePlatform: platform,
        annotationOrder: const [],
        annotationConsumeTapEvents: const [],
      );
      highlightController = await BuildableHighlightController.install(
        controller,
        layer,
        sourceId: 'terra_town_fog',
      );
    });

    test('初回は指定した全featureIdにsetFeatureStateする', () async {
      await highlightController.setHighlighted({1, 2, 3});

      expect(platform.setFeatureStateCalls, hasLength(3));
      final ids = platform.setFeatureStateCalls
          .map((c) => c['featureId'])
          .toSet();
      expect(ids, {'1', '2', '3'});
      for (final call in platform.setFeatureStateCalls) {
        expect(call['state'], {'buildable': true});
        expect(call['sourceId'], 'terra_town_fog');
      }
      expect(platform.removeFeatureStateCalls, isEmpty);
    });

    test('差分だけを更新する（増えた分だけset、消えた分だけremove）', () async {
      await highlightController.setHighlighted({1, 2, 3});
      platform.setFeatureStateCalls.clear();

      await highlightController.setHighlighted({2, 3, 4});

      final setIds = platform.setFeatureStateCalls
          .map((c) => c['featureId'])
          .toSet();
      expect(setIds, {'4'}, reason: '新たに加わった4だけsetする');

      expect(platform.removeFeatureStateCalls, hasLength(1));
      final removeCall = platform.removeFeatureStateCalls.single;
      expect(removeCall['featureId'], '1', reason: '外れた1だけremoveする');
      expect(
        removeCall['stateKey'],
        'buildable',
        reason: 'buildableキーだけを消し、revealedは触らない',
      );
    });

    test('clearは全てのハイライトをremoveFeatureStateで解除する', () async {
      await highlightController.setHighlighted({1, 2});
      platform.removeFeatureStateCalls.clear();

      await highlightController.clear();

      expect(platform.removeFeatureStateCalls, hasLength(2));
      for (final call in platform.removeFeatureStateCalls) {
        expect(call['stateKey'], 'buildable');
      }
    });
  });
}

/// [MapLibrePlatform] のテスト用フェイク（`terrain_tint_layer_test.dart` の
/// `_RecordingMapLibrePlatform` に `setFeatureState`/`removeFeatureState` の
/// 記録を追加したもの）。
class _RecordingMapLibrePlatform extends MapLibrePlatform {
  final List<Map<String, dynamic>> addFillLayerCalls = [];
  final List<Map<String, dynamic>> setFeatureStateCalls = [];
  final List<Map<String, dynamic>> removeFeatureStateCalls = [];

  @override
  Future<void> initPlatform(int id) async {}

  @override
  Future<void> addFillLayer(
    String sourceId,
    String layerId,
    Map<String, dynamic> properties, {
    String? belowLayerId,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
    required bool enableInteraction,
  }) async {
    addFillLayerCalls.add({
      'sourceId': sourceId,
      'layerId': layerId,
      'properties': properties,
      'belowLayerId': belowLayerId,
      'enableInteraction': enableInteraction,
    });
  }

  @override
  Future<void> setFeatureState(
    String sourceId,
    String featureId,
    Map<String, dynamic> state, {
    String? sourceLayer,
  }) async {
    setFeatureStateCalls.add({
      'sourceId': sourceId,
      'featureId': featureId,
      'state': state,
    });
  }

  @override
  Future<void> removeFeatureState(
    String sourceId, {
    String? featureId,
    String? stateKey,
    String? sourceLayer,
  }) async {
    removeFeatureStateCalls.add({
      'sourceId': sourceId,
      'featureId': featureId,
      'stateKey': stateKey,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
