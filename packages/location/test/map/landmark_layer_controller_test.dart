import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [LandmarkLayerController] の状態更新（Issue #170）を検証する。
///
/// 【なぜ `landmark_layer_test.dart` と別ファイルにしたか】
/// `landmark_layer_test.dart` は `MapLibreMapController` に依存しない純粋関数
/// （`buildLandmarkFeatureCollection` 等）だけを検証する
/// （`fog_of_war_layer_test.dart` 冒頭コメント「install 自体はプラットフォーム
/// チャンネルが必要なため flutter test では検証できない」と同じ制約）。
/// 本ファイルは [_RecordingMapLibrePlatform]（下記）で `MapLibrePlatform` を
/// 実プラットフォームチャンネル無しに差し替えることで、[LandmarkLayerController]
/// が実際にどの `MapLibrePlatform` メソッドをどの引数で呼んだかまで検証する
/// （Issue #170 受け入れ基準「単体テストで状態更新の呼び出しを確認する」）。
void main() {
  group('landmarkSymbolLayerProperties（再発防止・Issue #170）', () {
    test('icon-imageはget式であり、feature-stateを一切参照しない', () {
      final json = landmarkSymbolLayerProperties().toJson();

      expect(json['icon-image'], ['get', 'icon']);
      // レイアウトプロパティ全体（本レイヤーが指定する値はすべて
      // iconImage/iconSize/iconAllowOverlap/iconIgnorePlacementのみ）に
      // 'feature-state' という語が一切含まれないことを再帰的に確認する。
      // MapLibreのスタイル仕様では feature-state 式はペイントプロパティでしか
      // 評価されず、レイアウトプロパティ（icon-image等）やfilterでは常に
      // 既定値扱いになる（本Issueの原因そのもの）。
      expect(_containsFeatureState(json), isFalse);
    });

    test(
      'icon-anchor/icon-offsetを指定せず、スタイル仕様の既定値centerに委ねる'
      '（Issue #173: 円の中心を画像側で中心に一致させる設計のため）',
      () {
        final properties = landmarkSymbolLayerProperties();

        expect(properties.iconAnchor, isNull);
        expect(properties.iconOffset, isNull);

        final json = properties.toJson();
        expect(json.containsKey('icon-anchor'), isFalse);
        expect(json.containsKey('icon-offset'), isFalse);
      },
    );
  });

  group('LandmarkLayerController', () {
    const poiA = PointOfInterestId('node/1');
    const poiB = PointOfInterestId('node/2');

    late _RecordingMapLibrePlatform platform;
    late MapLibreMapController controller;
    late Map<String, dynamic> featureCollection;
    late LandmarkPinImages images;

    setUp(() {
      platform = _RecordingMapLibrePlatform();
      controller = MapLibreMapController(
        maplibrePlatform: platform,
        annotationOrder: const [],
        annotationConsumeTapEvents: const [],
      );
      const poiAObj = PointOfInterest(
        id: poiA,
        name: '名所A',
        kind: 'tourism=museum',
        latitude: 35.0,
        longitude: 139.0,
        hexId: HexId(1),
      );
      const poiBObj = PointOfInterest(
        id: poiB,
        name: '名所B',
        kind: 'leisure=park',
        latitude: 35.1,
        longitude: 139.1,
        hexId: HexId(2),
      );
      featureCollection = buildLandmarkFeatureCollection([poiAObj, poiBObj]);
      images = LandmarkPinImages({
        landmarkLockedIconId: Uint8List.fromList([0]),
        landmarkRevealedIconId(poiA): Uint8List.fromList([1]),
        landmarkCollectedIconId(poiA): Uint8List.fromList([2]),
        landmarkRevealedIconId(poiB): Uint8List.fromList([3]),
        landmarkCollectedIconId(poiB): Uint8List.fromList([4]),
      });
    });

    Map<String, dynamic> iconPropertiesOf(String poiIdValue) {
      final geojson =
          platform.setGeoJsonSourceCalls.last['geojson']
              as Map<String, dynamic>;
      final features = geojson['features'] as List;
      final feature =
          features.firstWhere(
                (f) => (f as Map)['properties']['poi_id_str'] == poiIdValue,
              )
              as Map;
      return Map<String, dynamic>.from(feature['properties'] as Map);
    }

    test('install直後は全POIが伏せピンになり、setGeoJsonSource（差し替え）はまだ呼ばれない', () async {
      await LandmarkLayerController.install(
        controller,
        images,
        featureCollection,
      );

      expect(platform.addGeoJsonSourceCalls, hasLength(1));
      expect(platform.setGeoJsonSourceCalls, isEmpty);
      final features =
          platform.addGeoJsonSourceCalls.single['geojson']['features'] as List;
      for (final feature in features) {
        expect((feature as Map)['properties']['icon'], landmarkLockedIconId);
      }
    });

    test('addSymbolLayerに渡すレイアウトプロパティの式にfeature-stateを含まない', () async {
      await LandmarkLayerController.install(
        controller,
        images,
        featureCollection,
      );

      final call = platform.addSymbolLayerCalls.single;
      final properties = call['properties'] as Map<String, dynamic>;
      expect(properties['icon-image'], ['get', 'icon']);
      expect(_containsFeatureState(properties), isFalse);
    });

    test('enableInteraction: false で追加する（Issue #151と同じ落とし穴）', () async {
      await LandmarkLayerController.install(
        controller,
        images,
        featureCollection,
      );

      expect(platform.addSymbolLayerCalls.single['enableInteraction'], isFalse);
    });

    test(
      'revealPointsOfInterestは対象POIのiconのみ開示済みに切り替え、setGeoJsonSourceを1回呼ぶ',
      () async {
        final landmarkController = await LandmarkLayerController.install(
          controller,
          images,
          featureCollection,
        );

        await landmarkController.revealPointsOfInterest([poiA]);

        expect(platform.setGeoJsonSourceCalls, hasLength(1));
        expect(
          iconPropertiesOf(poiA.value)['icon'],
          landmarkRevealedIconId(poiA),
        );
        expect(iconPropertiesOf(poiB.value)['icon'], landmarkLockedIconId);
        // 旧実装（feature-state方式）の呼び出しが一切残っていないことの確認。
        expect(platform.setFeatureStateCallCount, 0);
      },
    );

    test('markCollectedは対象POIのiconを収集済みに切り替える', () async {
      final landmarkController = await LandmarkLayerController.install(
        controller,
        images,
        featureCollection,
      );

      await landmarkController.markCollected([poiA]);

      expect(
        iconPropertiesOf(poiA.value)['icon'],
        landmarkCollectedIconId(poiA),
      );
    });

    test('収集済みの後にrevealPointsOfInterestを呼んでも伏せピン側に巻き戻さない', () async {
      final landmarkController = await LandmarkLayerController.install(
        controller,
        images,
        featureCollection,
      );

      await landmarkController.markCollected([poiA]);
      await landmarkController.revealPointsOfInterest([poiA]);

      expect(
        iconPropertiesOf(poiA.value)['icon'],
        landmarkCollectedIconId(poiA),
      );
    });

    test('restoreStateは開示済み・収集済みをまとめて1回のsetGeoJsonSourceで反映する'
        '（起動時復元のバッチ化・Issue #170）', () async {
      final landmarkController = await LandmarkLayerController.install(
        controller,
        images,
        featureCollection,
      );

      await landmarkController.restoreState(
        revealed: [poiA, poiB],
        collected: [poiA],
      );

      expect(platform.setGeoJsonSourceCalls, hasLength(1));
      expect(
        iconPropertiesOf(poiA.value)['icon'],
        landmarkCollectedIconId(poiA),
      );
      expect(
        iconPropertiesOf(poiB.value)['icon'],
        landmarkRevealedIconId(poiB),
      );
    });

    test('見た目が変わらない場合はsetGeoJsonSourceを呼ばない（無駄な全件差し替えを避ける）', () async {
      final landmarkController = await LandmarkLayerController.install(
        controller,
        images,
        featureCollection,
      );

      await landmarkController.restoreState(
        revealed: const [],
        collected: const [],
      );

      expect(platform.setGeoJsonSourceCalls, isEmpty);
    });

    test('このレイヤーに存在しないPOI IDは無視する', () async {
      final landmarkController = await LandmarkLayerController.install(
        controller,
        images,
        featureCollection,
      );

      await landmarkController.revealPointsOfInterest([
        const PointOfInterestId('node/unknown'),
      ]);

      expect(platform.setGeoJsonSourceCalls, isEmpty);
    });
  });
}

/// [value] の中に文字列 `'feature-state'` が（ネストしたMap/Listの中も含めて）
/// 含まれていないかを再帰的に調べる。
bool _containsFeatureState(dynamic value) {
  if (value is String) return value == 'feature-state';
  if (value is Map) return value.values.any(_containsFeatureState);
  if (value is List) return value.any(_containsFeatureState);
  return false;
}

/// [MapLibrePlatform] のテスト用フェイク。プラットフォームチャンネルに一切
/// 依存せず、[LandmarkLayerController] が実際にどのメソッドをどの引数で
/// 呼んだかを記録する。
///
/// オーバーライドしていないメソッドが呼ばれた場合は [noSuchMethod] を
/// 経由してエラーになる。これにより、[LandmarkLayerController] が
/// （旧実装の）`setFeatureState` 以外の想定外の platform 呼び出しを
/// 行っていないことも間接的に保証される。
class _RecordingMapLibrePlatform extends MapLibrePlatform {
  final List<Map<String, dynamic>> addGeoJsonSourceCalls = [];
  final List<Map<String, dynamic>> setGeoJsonSourceCalls = [];
  final List<Map<String, dynamic>> addSymbolLayerCalls = [];
  final List<String> addedImageNames = [];
  int setFeatureStateCallCount = 0;

  /// テストの経過中に呼び出し元がまだ保持しているミュータブルな Map を
  /// そのまま記録すると、後続の呼び出しでの書き換えが過去の記録にも
  /// 反映されてしまう（同一インスタンスのため）。JSON往復でスナップショットの
  /// ディープコピーを作る（GeoJSON はプレーンな Map/List/String/num/bool の
  /// みで構成されるため安全）。
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
  Future<void> setFeatureState(
    String sourceId,
    String featureId,
    Map<String, dynamic> state, {
    String? sourceLayer,
  }) async {
    setFeatureStateCallCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
