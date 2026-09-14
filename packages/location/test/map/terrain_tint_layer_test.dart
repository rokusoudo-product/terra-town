import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [TerrainTintLayer]・[terrainTintFillLayerProperties]・
/// [terrainTintOutlineLayerProperties]・[TerrainTintController] を検証する
/// （Issue #176。見た目の定義そのものは #175 の承認文面。色の正しさ（DESIGN.md の
/// トークンと一致すること）を担保する責務は `app` 側のテスト
/// （`app/test/map/terrain_tint_layer_factory_test.dart`）にあり、本ファイルは
/// フェイク値を渡して式の組み立て・地図登録の挙動のみを検証する。役割分担は
/// `fog_of_war_layer_test.dart` 冒頭コメントと同じ）。
void main() {
  const layer = TerrainTintLayer(
    fillColorHexByTerrainType: {
      'forest': '#112233',
      'mountain': '#445566',
      'waterside': '#778899',
      'sea': '#AABBCC',
    },
    fillOpacity: 0.22,
    outlineColorHex: '#333333',
    outlineOpacity: 0.3,
    outlineWidth: 1.0,
  );

  group('terrainTintFillLayerProperties', () {
    test('fill-colorのmatch式は4地形の色を網羅し、terrain_typeで判定する（feature-stateは使わない）', () {
      final json = terrainTintFillLayerProperties(layer).toJson();
      final colorExpr = json['fill-color'] as List;

      expect(colorExpr[0], 'match');
      expect(colorExpr[1], const ['get', 'terrain_type']);
      final pairs = _matchPairs(colorExpr);
      expect(pairs['forest'], '#112233');
      expect(pairs['mountain'], '#445566');
      expect(pairs['waterside'], '#778899');
      expect(pairs['sea'], '#AABBCC');
      // 空き地(vacant_lot)は塗り色のmatchに含めない（既定値にフォールバックさせる）。
      expect(pairs.containsKey('vacant_lot'), isFalse);
      expect(_containsFeatureState(colorExpr), isFalse);
    });

    test(
      'fill-opacityは未開示時0、開示済みでも空き地・未知のterrain_typeは0、'
      '4地形は指定した不透明度になる（受け入れ基準）',
      () {
        final json = terrainTintFillLayerProperties(layer).toJson();
        final opacityExpr = json['fill-opacity'] as List;

        expect(opacityExpr[0], 'case');
        expect(opacityExpr[1], const [
          'boolean',
          ['feature-state', 'revealed'],
          false,
        ]);
        // 未開示時（case の3番目の引数＝elseの値）は常に0。
        expect(opacityExpr[3], 0.0);

        final revealedExpr = opacityExpr[2] as List;
        expect(revealedExpr[0], 'match');
        final pairs = _matchPairs(revealedExpr);
        expect(pairs['forest'], 0.22);
        expect(pairs['mountain'], 0.22);
        expect(pairs['waterside'], 0.22);
        expect(pairs['sea'], 0.22);
        // 空き地・未知の terrain_type に対応する既定値（match式の最後の要素）は0。
        expect(revealedExpr.last, 0.0);
      },
    );

    test('feature-stateはfill-opacityにのみ現れ、fill-color全体には現れない', () {
      final json = terrainTintFillLayerProperties(layer).toJson();

      expect(_containsFeatureState(json['fill-color']), isFalse);
      expect(_containsFeatureState(json['fill-opacity']), isTrue);
    });

    test('レイアウトプロパティ（visibility等）は一切設定しない（feature-stateの誤用の余地を無くす）', () {
      final json = terrainTintFillLayerProperties(layer).toJson();

      expect(json.containsKey('visibility'), isFalse);
      expect(json.keys, unorderedEquals(['fill-color', 'fill-opacity']));
    });
  });

  group('terrainTintOutlineLayerProperties', () {
    test('line-color/line-widthはterrain_typeによらず定数（空き地を含む全地形が対象）', () {
      final json = terrainTintOutlineLayerProperties(layer).toJson();

      expect(json['line-color'], '#333333');
      expect(json['line-width'], 1.0);
      expect(_containsFeatureState(json['line-color']), isFalse);
      expect(_containsFeatureState(json['line-width']), isFalse);
    });

    test('line-opacityは開示済み(revealed)のときのみ指定値、それ以外は0', () {
      final json = terrainTintOutlineLayerProperties(layer).toJson();

      expect(json['line-opacity'], [
        'case',
        const [
          'boolean',
          ['feature-state', 'revealed'],
          false,
        ],
        0.3,
        0.0,
      ]);
    });

    test('レイアウトプロパティは一切設定しない', () {
      final json = terrainTintOutlineLayerProperties(layer).toJson();

      expect(
        json.keys,
        unorderedEquals(['line-color', 'line-width', 'line-opacity']),
      );
    });
  });

  group('TerrainTintController.install', () {
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

    test('新しいソースを追加せず、fogと同じsourceIdに対して塗り→縁取りの順で2レイヤーを追加する', () async {
      await TerrainTintController.install(
        controller,
        layer,
        sourceId: 'terra_town_fog',
        belowLayerId: 'terra_town_fog_layer',
      );

      // addGeoJsonSource をオーバーライドしていないため、万一呼ばれれば
      // noSuchMethod 経由で例外になりテストが失敗する（＝新規ソース追加が
      // 無いことの間接的な検証）。
      expect(platform.addFillLayerCalls, hasLength(1));
      expect(platform.addLineLayerCalls, hasLength(1));

      final fillCall = platform.addFillLayerCalls.single;
      expect(fillCall['sourceId'], 'terra_town_fog');
      expect(fillCall['layerId'], TerrainTintController.defaultFillLayerId);
      expect(fillCall['belowLayerId'], 'terra_town_fog_layer');

      final lineCall = platform.addLineLayerCalls.single;
      expect(lineCall['sourceId'], 'terra_town_fog');
      expect(lineCall['layerId'], TerrainTintController.defaultLineLayerId);
      expect(lineCall['belowLayerId'], 'terra_town_fog_layer');
    });

    test('enableInteraction: false で両レイヤーとも追加する（Issue #151・#160と同じ落とし穴）', () async {
      await TerrainTintController.install(
        controller,
        layer,
        sourceId: 'terra_town_fog',
      );

      expect(platform.addFillLayerCalls.single['enableInteraction'], isFalse);
      expect(platform.addLineLayerCalls.single['enableInteraction'], isFalse);
    });

    test('belowLayerIdを省略した場合はnullのまま渡す（末尾に追加される）', () async {
      await TerrainTintController.install(
        controller,
        layer,
        sourceId: 'terra_town_fog',
      );

      expect(platform.addFillLayerCalls.single['belowLayerId'], isNull);
      expect(platform.addLineLayerCalls.single['belowLayerId'], isNull);
    });

    test('カスタムのレイヤーIDを指定できる', () async {
      final result = await TerrainTintController.install(
        controller,
        layer,
        sourceId: 'terra_town_fog',
        fillLayerId: 'custom_fill',
        lineLayerId: 'custom_line',
      );

      expect(result.fillLayerId, 'custom_fill');
      expect(result.lineLayerId, 'custom_line');
      expect(platform.addFillLayerCalls.single['layerId'], 'custom_fill');
      expect(platform.addLineLayerCalls.single['layerId'], 'custom_line');
    });
  });
}

/// `['match', ['get', field], k1, v1, k2, v2, ..., default]` 形式の式から
/// `k1: v1, k2: v2, ...`（既定値を除く）の対応表を作る。
Map<String, dynamic> _matchPairs(List<dynamic> matchExpr) {
  final body = matchExpr.sublist(2, matchExpr.length - 1);
  final pairs = <String, dynamic>{};
  for (var i = 0; i < body.length; i += 2) {
    pairs[body[i] as String] = body[i + 1];
  }
  return pairs;
}

/// [value] の中に文字列 `'feature-state'` が（ネストしたMap/Listの中も含めて）
/// 含まれていないかを再帰的に調べる（`landmark_layer_controller_test.dart` と同じ
/// ヘルパー）。
bool _containsFeatureState(dynamic value) {
  if (value is String) return value == 'feature-state';
  if (value is Map) return value.values.any(_containsFeatureState);
  if (value is List) return value.any(_containsFeatureState);
  return false;
}

/// [MapLibrePlatform] のテスト用フェイク。プラットフォームチャンネルに一切
/// 依存せず、[TerrainTintController] が実際にどのメソッドをどの引数で
/// 呼んだかを記録する（`landmark_layer_controller_test.dart` の
/// `_RecordingMapLibrePlatform` と同じ方式）。
///
/// `addGeoJsonSource` をオーバーライドしていないため、[TerrainTintController]
/// が誤って新しいソースを追加しようとした場合は [noSuchMethod] を経由して
/// 例外になる（新規ソース追加が無いことの間接的な検証）。
class _RecordingMapLibrePlatform extends MapLibrePlatform {
  final List<Map<String, dynamic>> addFillLayerCalls = [];
  final List<Map<String, dynamic>> addLineLayerCalls = [];

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
  Future<void> addLineLayer(
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
    addLineLayerCalls.add({
      'sourceId': sourceId,
      'layerId': layerId,
      'properties': properties,
      'belowLayerId': belowLayerId,
      'enableInteraction': enableInteraction,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
