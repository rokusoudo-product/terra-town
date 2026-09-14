// CollectionScreen（Issue #161・T075）のウィジェットテスト。
//
// `test/features/inventory/inventory_screen_test.dart` と同じ方針:
// 実 CollectionRepository + GameDatabase.forTesting()（インメモリ）を使い、
// フェイクのRepositoryは作らない。地域パックだけは path_provider の実
// プラットフォーム実装が無い widget テスト環境では読めないため、
// `loadRegionPack` にフェイク（RegionPackConnection.forTesting）を注入する
// （`app/test/widget_test.dart` が MapScreen に対して行っているのと同じ考え方）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'package:terra_town/design/app_theme.dart';
import 'package:terra_town/features/collection/collection_screen.dart';

Widget _wrap(Widget child) {
  return MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));
}

Future<RegionPack> _fakeLoadRegionPack(List<Map<String, Object?>> pois) async {
  final connection = RegionPackConnection.forTesting(
    seed: (db) {
      db.execute('CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT)');
      db.execute(
        "INSERT INTO pack_meta (key, value) VALUES ('pack_version', 'test-v1')",
      );
      db.execute(
        'CREATE TABLE hex_terrain ('
        'hex_id INTEGER PRIMARY KEY, terrain_type TEXT NOT NULL, '
        'feature_id INTEGER NOT NULL, cell_count INTEGER NOT NULL, '
        'boundary_geojson TEXT NOT NULL)',
      );
      db.execute(
        'CREATE TABLE poi (id TEXT PRIMARY KEY, lat REAL NOT NULL, '
        'lon REAL NOT NULL, kind TEXT NOT NULL, name TEXT NOT NULL)',
      );
      for (final poi in pois) {
        db.execute(
          'INSERT INTO poi (id, lat, lon, kind, name) VALUES (?, ?, ?, ?, ?)',
          [poi['id'], 35.0, 135.0, poi['kind'], poi['name']],
        );
      }
    },
  );
  return RegionPackRepository.load(connection);
}

void main() {
  group('CollectionScreen', () {
    late GameDatabase database;
    late CollectionRepository repository;

    setUp(() {
      database = GameDatabase.forTesting();
      repository = CollectionRepository(database);
    });

    tearDown(() async => database.close());

    testWidgets('カテゴリ集計・一覧を表示する（収集済み1件・未収集1件）', (tester) async {
      await repository.save(
        LandmarkCollectionRecord(
          poiId: const PointOfInterestId('poi-1'),
          kind: 'amenity=place_of_worship',
          name: '清泰寺',
          isBonus: false,
          collectedAt: DateTime(2026, 9, 13, 18, 0),
          collectMethod: CollectMethod.point,
          bonusGranted: null,
        ),
      );

      await tester.pumpWidget(
        _wrap(
          CollectionScreen(
            collectionRepository: repository,
            loadRegionPack: () => _fakeLoadRegionPack([
              {'id': 'poi-1', 'kind': 'amenity=place_of_worship', 'name': '清泰寺（パック側）'},
              {'id': 'poi-2', 'kind': 'tourism=museum', 'name': '秘密の博物館'},
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // カテゴリ集計: 収集数/総数。
      // カテゴリラベル自体はカテゴリ集計欄と未収集行の両方に出るため
      // findsWidgets（1件以上）で見る。集計欄の値（分数表記）はここにしか
      // 出ない文字列なので findsOneWidget で厳密に見る。
      expect(find.text('神社・寺'), findsWidgets);
      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.text('博物館・美術館'), findsWidgets);
      expect(find.text('0 / 1'), findsOneWidget);
      expect(find.text('収集済み 1 / 2'), findsOneWidget);

      // 収集済み: スナップショットの名称・収集手段が出る（パック側の名称ではない）。
      expect(find.text('清泰寺'), findsOneWidget);
      expect(find.text('清泰寺（パック側）'), findsNothing);
      expect(find.textContaining('ポイントで開放'), findsOneWidget);

      // 未収集: 名称が伏せられ「？」になる。
      expect(find.text('秘密の博物館'), findsNothing);
      expect(find.text('？'), findsOneWidget);
    });

    testWidgets('現地で発見した名所は「現地で発見」と表示される', (tester) async {
      await repository.save(
        LandmarkCollectionRecord(
          poiId: const PointOfInterestId('poi-1'),
          kind: 'historic=memorial',
          name: '六創堂の碑',
          isBonus: false,
          collectedAt: DateTime(2026, 9, 10, 8, 0),
          collectMethod: CollectMethod.walk,
          bonusGranted: null,
        ),
      );

      await tester.pumpWidget(
        _wrap(
          CollectionScreen(
            collectionRepository: repository,
            loadRegionPack: () => _fakeLoadRegionPack([
              {'id': 'poi-1', 'kind': 'historic=memorial', 'name': '六創堂の碑'},
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('現地で発見'), findsOneWidget);
    });

    testWidgets('全件未収集でも「？」で伏せて一覧表示される（受け入れ基準の空状態）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          CollectionScreen(
            collectionRepository: repository,
            loadRegionPack: () => _fakeLoadRegionPack([
              {'id': 'poi-1', 'kind': 'leisure=park', 'name': '謎の公園'},
              {'id': 'poi-2', 'kind': 'tourism=viewpoint', 'name': '謎の展望台'},
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('収集済み 0 / 2'), findsOneWidget);
      expect(find.text('？'), findsNWidgets(2));
      expect(find.text('謎の公園'), findsNothing);
      expect(find.text('謎の展望台'), findsNothing);
    });

    testWidgets('未知の kind でも落ちず「その他」として表示される（forward-compat）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          CollectionScreen(
            collectionRepository: repository,
            loadRegionPack: () => _fakeLoadRegionPack([
              {'id': 'poi-1', 'kind': 'shop=bakery', 'name': '謎の店'},
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 「その他」ラベルはカテゴリ集計欄と未収集行の両方に出る。
      expect(find.text('その他'), findsWidgets);
      expect(find.text('0 / 1'), findsOneWidget);
    });

    testWidgets('読み込み中はローディング表示になる', (tester) async {
      final completer = Completer<RegionPack>();
      await tester.pumpWidget(
        _wrap(
          CollectionScreen(
            collectionRepository: repository,
            loadRegionPack: () => completer.future,
          ),
        ),
      );

      expect(find.text('名所図鑑を読み込み中…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(await _fakeLoadRegionPack(const []));
      await tester.pumpAndSettle();
    });

    testWidgets('地域パックの読み込みに失敗した場合、エラー表示とやり直しボタンが出る', (tester) async {
      await tester.pumpWidget(
        _wrap(
          CollectionScreen(
            collectionRepository: repository,
            loadRegionPack: () => Future<RegionPack>.error(Exception('読み込み失敗')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('名所図鑑を読み込めませんでした'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'やり直す'), findsOneWidget);
    });
  });
}
