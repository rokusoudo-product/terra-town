import 'package:flutter_test/flutter_test.dart';

import 'package:terra_town/map/debug/nearest_pack_hex.dart';

Map<String, dynamic> _feature({
  required int id,
  required int hexId,
  required List<List<double>> ring,
}) {
  return {
    'type': 'Feature',
    'id': id,
    'geometry': {
      'type': 'Polygon',
      'coordinates': [ring],
    },
    'properties': {'hex_id_str': hexId.toString()},
  };
}

void main() {
  group('findNearestPackHex', () {
    test('パックが空なら null', () {
      final result = findNearestPackHex(
        {'type': 'FeatureCollection', 'features': <dynamic>[]},
        latitude: 35.0,
        longitude: 139.0,
      );
      expect(result, isNull);
    });

    test('最も中心に近いヘクスを選ぶ', () {
      final fc = {
        'type': 'FeatureCollection',
        'features': [
          _feature(
            id: 100,
            hexId: 1,
            ring: [
              [139.0, 35.0],
              [139.001, 35.0],
              [139.001, 35.001],
              [139.0, 35.001],
              [139.0, 35.0],
            ],
          ),
          _feature(
            id: 200,
            hexId: 2,
            ring: [
              [139.5, 35.5],
              [139.501, 35.5],
              [139.501, 35.501],
              [139.5, 35.501],
              [139.5, 35.5],
            ],
          ),
        ],
      };

      final result = findNearestPackHex(fc, latitude: 35.0002, longitude: 139.0002);

      expect(result, isNotNull);
      expect(result!.hexId, 1);
      expect(result.featureId, 100);
      expect(result.latitude, closeTo(35.0005, 0.001));
      expect(result.longitude, closeTo(139.0005, 0.001));
    });

    test('経度方向のスケール補正により、緯度距離換算で近い方を正しく選ぶ', () {
      // originから見て、Aは緯度方向にわずかに離れているが真の距離では最も近い。
      // Bは経度方向に「見かけ上」小さいΔだが、高緯度では経度1度の実距離が小さいため
      // 補正なしだと誤って近いと判定されうる差を作る。
      const originLat = 60.0; // cos(60°) = 0.5 と大きな補正が効く緯度を選ぶ
      const originLon = 139.0;

      final fc = {
        'type': 'FeatureCollection',
        'features': [
          // A: 緯度方向に0.01離れているだけ（実距離 ≈ 0.01度分）。
          _feature(
            id: 1,
            hexId: 1,
            ring: [
              [originLon, originLat + 0.01],
              [originLon, originLat + 0.01],
              [originLon, originLat + 0.01],
            ],
          ),
          // B: 経度方向に0.015離れている。cos(60°)=0.5 補正後の実距離 ≈ 0.0075度分で
          // Aより近くなるはず。
          _feature(
            id: 2,
            hexId: 2,
            ring: [
              [originLon + 0.015, originLat],
              [originLon + 0.015, originLat],
              [originLon + 0.015, originLat],
            ],
          ),
        ],
      };

      final result = findNearestPackHex(fc, latitude: originLat, longitude: originLon);

      expect(result!.hexId, 2, reason: '経度スケール補正が効いていればBの方が実距離は近い');
    });
  });
}
