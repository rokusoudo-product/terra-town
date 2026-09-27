import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [BuildingLayerController] の地図登録・再構築（Issue #193・T090）を検証する。
///
/// 【なぜ `building_layer_test.dart` と別ファイルにしたか】
/// `landmark_layer_controller_test.dart` 冒頭コメントと同じ理由（`install` 自体は
/// プラットフォームチャンネルが必要なため `flutter test` では検証できず、
/// `_RecordingMapLibrePlatform` で `MapLibrePlatform` を差し替える必要がある）。
void main() {
  BuildingRow row({
    required int id,
    required int hexId,
    required BuildingType buildingType,
  }) {
    return BuildingRow(
      id: id,
      hexId: hexId,
      buildingType: buildingType,
      level: 1,
      constructionState: BuildingConstructionState.built,
      districtId: null,
      builtAt: DateTime.utc(2026, 9, 21),
    );
  }

  group('BuildingLayerController', () {
    late _RecordingMapLibrePlatform platform;
    late MapLibreMapController controller;
    late Map<String, dynamic> featureCollection;
    late BuildingIconImages images;

    setUp(() {
      platform = _RecordingMapLibrePlatform();
      controller = MapLibreMapController(
        maplibrePlatform: platform,
        annotationOrder: const [],
        annotationConsumeTapEvents: const [],
      );
      featureCollection = buildBuildingFeatureCollection(
        [row(id: 1, hexId: 10, buildingType: BuildingType.house)],
        {
          10: [139.0, 35.0],
        },
      );
      images = BuildingIconImages({
        buildingIconId(BuildingType.house): Uint8List.fromList([1]),
      });
    });

    test('installはaddImage→addGeoJsonSource→addSymbolLayerの順で1回ずつ呼ぶ', () async {
      await BuildingLayerController.install(
        controller,
        images,
        featureCollection,
      );

      expect(platform.addedImageNames, [buildingIconId(BuildingType.house)]);
      expect(platform.addGeoJsonSourceCalls, hasLength(1));
      expect(platform.setGeoJsonSourceCalls, isEmpty);
      expect(platform.addSymbolLayerCalls, hasLength(1));

      final addedFeatures =
          platform.addGeoJsonSourceCalls.single['geojson']['features'] as List;
      expect(addedFeatures, hasLength(1));
    });

    test('enableInteraction: false で追加する（Issue #151と同じ落とし穴）', () async {
      await BuildingLayerController.install(
        controller,
        images,
        featureCollection,
      );

      expect(platform.addSymbolLayerCalls.single['enableInteraction'], isFalse);
    });

    test('addSymbolLayerに渡すレイアウトプロパティの式にfeature-stateを含まない', () async {
      await BuildingLayerController.install(
        controller,
        images,
        featureCollection,
      );

      final properties =
          platform.addSymbolLayerCalls.single['properties']
              as Map<String, dynamic>;
      expect(properties['icon-image'], ['get', 'icon']);
    });

    test('refreshはsetGeoJsonSourceでソース全体を差し替える', () async {
      final buildingLayerController = await BuildingLayerController.install(
        controller,
        images,
        featureCollection,
      );

      final updated = buildBuildingFeatureCollection(
        [
          row(id: 1, hexId: 10, buildingType: BuildingType.house),
          row(id: 2, hexId: 20, buildingType: BuildingType.quarry),
        ],
        {
          10: [139.0, 35.0],
          20: [139.1, 35.1],
        },
      );

      await buildingLayerController.refresh(updated);

      expect(platform.setGeoJsonSourceCalls, hasLength(1));
      final refreshedFeatures =
          platform.setGeoJsonSourceCalls.single['geojson']['features'] as List;
      expect(refreshedFeatures, hasLength(2));
    });

    test('不正なfeatureCollection（idが無い）を渡すとinstall/refreshともに例外を投げる', () async {
      final invalid = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': null,
            'properties': <String, dynamic>{},
          },
        ],
      };

      expect(
        () => BuildingLayerController.install(controller, images, invalid),
        throwsArgumentError,
      );

      final buildingLayerController = await BuildingLayerController.install(
        controller,
        images,
        featureCollection,
      );
      expect(
        () => buildingLayerController.refresh(invalid),
        throwsArgumentError,
      );
    });
  });
}

/// [MapLibrePlatform] のテスト用フェイク（`landmark_layer_controller_test.dart`
/// の `_RecordingMapLibrePlatform` と同じ役割）。
class _RecordingMapLibrePlatform extends MapLibrePlatform {
  final List<Map<String, dynamic>> addGeoJsonSourceCalls = [];
  final List<Map<String, dynamic>> setGeoJsonSourceCalls = [];
  final List<Map<String, dynamic>> addSymbolLayerCalls = [];
  final List<String> addedImageNames = [];

  Map<String, dynamic> _snapshot(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

  @override
  Future<void> initPlatform(int id) async {}

  @override
  Future<void> addImage(
    String name,
    Uint8List bytes, [
    bool sdf = false,
  ]) async {
    addedImageNames.add(name);
  }

  @override
  Future<void> addGeoJsonSource(
    String sourceId,
    Map<String, dynamic> geojson, {
    String? promoteId,
  }) async {
    addGeoJsonSourceCalls.add({
      'sourceId': sourceId,
      'geojson': _snapshot(geojson),
      'promoteId': promoteId,
    });
  }

  @override
  Future<void> setGeoJsonSource(
    String sourceId,
    Map<String, dynamic> geojson,
  ) async {
    setGeoJsonSourceCalls.add({
      'sourceId': sourceId,
      'geojson': _snapshot(geojson),
    });
  }

  @override
  Future<void> addSymbolLayer(
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
    addSymbolLayerCalls.add({
      'sourceId': sourceId,
      'layerId': layerId,
      'properties': _snapshot(properties),
      'enableInteraction': enableInteraction,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
