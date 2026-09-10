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
/// 代表が実機で行う（PR本文「代表が実機で確認する手順」参照）。
Widget _wrap(Widget child) {
  return MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));
}

void main() {
  testWidgets('パック解決中はローディング表示になる', (tester) async {
    // Timer ベースの遅延ではなく、意図的に完了させない Completer を使う
    // （Timer を残したままテストを終えると "A Timer is still pending" で失敗するため）。
    final completer = Completer<String>();
    addTearDown(() => completer.complete('/fake/tiles.mbtiles'));

    await tester.pumpWidget(
      _wrap(
        MapScreen(
          resolveMbtilesPath: () => completer.future,
          mapBuilder: (context, path) => Text('map:$path'),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('map:'), findsNothing);
  });

  testWidgets('パック未取得の場合はエラー表示になり、対処方法を提示する', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MapScreen(
          resolveMbtilesPath: () => Future<String>.error(
            const PackAssetMissingException('assets/pack/tiles.mbtiles'),
          ),
          mapBuilder: (context, path) => Text('map:$path'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('地図を表示できませんでした'), findsOneWidget);
    expect(find.textContaining('bundle_region_pack.sh'), findsOneWidget);
    expect(find.textContaining('map:'), findsNothing);
  });

  testWidgets('パック解決に成功したら mapBuilder が解決済みパスで呼ばれる', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MapScreen(
          resolveMbtilesPath: () async => '/fake/tiles.mbtiles',
          mapBuilder: (context, path) => Text('map:$path'),
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
          mapBuilder: (context, path) => Text('map:$path'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('地図を表示できませんでした'), findsOneWidget);
    expect(find.textContaining('bundle_region_pack.sh'), findsNothing);
  });
}
