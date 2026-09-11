import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'package:terra_town/design/app_theme.dart';
import 'package:terra_town/features/map/map_screen.dart';

/// 【なぜ MapView（実地図）自体は widget テストしないか】
/// `packages/location` の `MapView` は MapLibre の実プラットフォームビュー
/// （Android の `PlatformView`）を組み立てる。`flutter test` のテスト環境には
/// 実機/エミュレータのプラットフォームチャンネルが存在しないため、`MapView` を
/// widget ツリーに pump すると `MissingPluginException` 等で不安定になる
/// （実測未検証だが、`google_maps_flutter`/`webview_flutter` 等 PlatformView に
/// 依存するプラグイン全般で広く知られる制約）。
///
/// そのため本ファイルは `MapScreen` の「ローディング/エラー/成功」の状態遷移と
/// DESIGN.md トークンの使用のみを検証し、[MapScreen.mapBuilder] を差し替えて
/// 実 [MapView] を一切 pump しない。実際に地図が描画されることの確認は
/// 代表が実機で行う（PR本文「実機確認は未実施」参照）。
///
/// 【Issue #137】`MapScreen` は MBTiles（表示専用タイル）と地域パック
/// （`region_pack.sqlite`・fog of war 用のヘクス境界・`RegionPack` 実装のソース）の
/// **両方**を解決してから [mapBuilder] を呼ぶようになった。実アセットへ
/// 依存しないよう、全テストで両方の解決関数を明示的に差し替える
/// （既定の同梱アセット解決に一切触れさせない）。
Widget _wrap(Widget child) {
  return MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));
}

void main() {
  testWidgets('パック解決中はローディング表示になる', (tester) async {
    // Timer ベースの遅延ではなく、意図的に完了させない Completer を使う
    // （Timer を残したままテストを終えると "A Timer is still pending" で失敗するため）。
    final mbtilesCompleter = Completer<String>();
    addTearDown(() => mbtilesCompleter.complete('/fake/tiles.mbtiles'));

    await tester.pumpWidget(
      _wrap(
        MapScreen(
          resolveMbtilesPath: () => mbtilesCompleter.future,
          resolveRegionPackPath: () async => '/fake/region_pack.sqlite',
          mapBuilder: (context, assets) => Text('map:${assets.mbtilesFilePath}'),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('map:'), findsNothing);
  });

  testWidgets('MBTilesパック未取得の場合はエラー表示になり、対処方法を提示する', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MapScreen(
          resolveMbtilesPath: () => Future<String>.error(
            const PackAssetMissingException('assets/pack/tiles.mbtiles'),
          ),
          resolveRegionPackPath: () async => '/fake/region_pack.sqlite',
          mapBuilder: (context, assets) => Text('map:${assets.mbtilesFilePath}'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('地図を表示できませんでした'), findsOneWidget);
    expect(find.textContaining('bundle_region_pack.sh'), findsOneWidget);
    expect(find.textContaining('map:'), findsNothing);
  });

  testWidgets('地域パック未取得の場合もエラー表示になり、対処方法を提示する', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MapScreen(
          resolveMbtilesPath: () async => '/fake/tiles.mbtiles',
          resolveRegionPackPath: () => Future<String>.error(
            const PackAssetMissingException('assets/pack/region_pack.sqlite'),
          ),
          mapBuilder: (context, assets) => Text('map:${assets.mbtilesFilePath}'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('地図を表示できませんでした'), findsOneWidget);
    expect(find.textContaining('bundle_region_pack.sh'), findsOneWidget);
    expect(find.textContaining('map:'), findsNothing);
  });

  testWidgets('両方のパック解決に成功したら mapBuilder が解決済みアセット一式で呼ばれる', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        MapScreen(
          resolveMbtilesPath: () async => '/fake/tiles.mbtiles',
          resolveRegionPackPath: () async => '/fake/region_pack.sqlite',
          mapBuilder: (context, assets) => Text('map:${assets.mbtilesFilePath}'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('map:/fake/tiles.mbtiles'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('パック解決失敗時、原因不明のエラーでは汎用メッセージを出す', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MapScreen(
          resolveMbtilesPath: () => Future<String>.error(
            StateError('予期しないエラー'),
          ),
          resolveRegionPackPath: () async => '/fake/region_pack.sqlite',
          mapBuilder: (context, assets) => Text('map:${assets.mbtilesFilePath}'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('地図を表示できませんでした'), findsOneWidget);
    expect(find.textContaining('bundle_region_pack.sh'), findsNothing);
  });
}
