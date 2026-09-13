// テーマ（DESIGN.md のデザイントークン）が正しく適用されていることを検証するテスト。
// Issue #25: カウンターデモの smoke test をトークン検証に置き換え。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'package:terra_town/design/app_theme.dart';
import 'package:terra_town/design/color_tokens.dart';
import 'package:terra_town/features/map/map_screen.dart';
import 'package:terra_town/main.dart';

/// 【Issue #135】設定タブが実際に [SettingsScreen] を表示することを確認するテスト
/// （下記「設定タブに切り替えるとスイッチが表示される」）は、`app` から初めて
/// [GameDatabase] を開く。ここでは `path_provider` の実プラットフォーム実装なしに
/// 決定的に検証するため [GameDatabase.forTesting]（インメモリ）を注入する。
/// スイッチの状態遷移・保存失敗時の挙動の詳細は
/// `test/features/settings/settings_screen_test.dart` が担当する。

/// 【Issue #99】`MapScreen`（地図タブ）は既定で実アセットから地域パックを解決し、
/// `packages/location` の `MapView`（MapLibre の実プラットフォームビュー）を描画する。
/// これは widget テスト環境（`flutter test`）では動作しない
/// （プラットフォームチャンネル未接続のため）ので、ナビ/テーマのみを検証する本ファイルの
/// テストは全て、この「パック未取得」を返すフェイクを注入して地図の実描画を回避する。
/// 地図画面自体の状態（ローディング/エラー/成功）の検証は
/// `test/features/map/map_screen_test.dart` が担当する。
Future<String> _missingPackResolver() {
  return Future<String>.error(
    const PackAssetMissingException(MapScreen.mbtilesAssetKey),
  );
}

void main() {
  group('AppTheme light', () {
    final theme = AppTheme.light();

    test('useMaterial3 が有効', () {
      expect(theme.useMaterial3, isTrue);
    });

    test('カラートークンが DESIGN.md のライト値と一致する', () {
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, ColorTokens.primaryLight);
      expect(theme.colorScheme.secondary, ColorTokens.secondaryLight);
      expect(theme.colorScheme.tertiary, ColorTokens.accentLight); // accent
      expect(theme.colorScheme.surface, ColorTokens.surfaceLight);
      expect(theme.colorScheme.onSurface, ColorTokens.textPrimaryLight);
      expect(
        theme.colorScheme.onSurfaceVariant,
        ColorTokens.textSecondaryLight,
      );
      expect(theme.colorScheme.error, ColorTokens.errorLight);
      expect(theme.scaffoldBackgroundColor, ColorTokens.backgroundLight);
    });

    test('semantic トークン（success/warning/info/fog）が DESIGN.md と一致する', () {
      final semantic = theme.semanticColors;
      expect(semantic.success, ColorTokens.successLight);
      expect(semantic.warning, ColorTokens.warningLight);
      expect(semantic.info, ColorTokens.infoLight);
      expect(semantic.fog, ColorTokens.fog);
    });
  });

  group('AppTheme dark', () {
    final theme = AppTheme.dark();

    test('useMaterial3 が有効', () {
      expect(theme.useMaterial3, isTrue);
    });

    test('カラートークンが DESIGN.md のダーク値と一致する', () {
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, ColorTokens.primaryDark);
      expect(theme.colorScheme.secondary, ColorTokens.secondaryDark);
      expect(theme.colorScheme.tertiary, ColorTokens.accentDark);
      expect(theme.colorScheme.surface, ColorTokens.surfaceDark);
      expect(theme.colorScheme.onSurface, ColorTokens.textPrimaryDark);
      expect(theme.colorScheme.onSurfaceVariant, ColorTokens.textSecondaryDark);
      expect(theme.colorScheme.error, ColorTokens.errorDark);
      expect(theme.scaffoldBackgroundColor, ColorTokens.backgroundDark);
    });

    test('fog は地図がライトのみ MVP のため単一値のまま', () {
      expect(theme.semanticColors.fog, ColorTokens.fog);
    });
  });

  test('タイポスケールが DESIGN.md の 12/14/16/20/24/32 のみで構成され、行間が1.5〜1.7', () {
    final validSizes = {12.0, 14.0, 16.0, 20.0, 24.0, 32.0};
    final textTheme = AppTheme.light().textTheme;
    final styles = <TextStyle?>[
      textTheme.displayLarge,
      textTheme.displayMedium,
      textTheme.displaySmall,
      textTheme.headlineLarge,
      textTheme.headlineMedium,
      textTheme.headlineSmall,
      textTheme.titleLarge,
      textTheme.titleMedium,
      textTheme.titleSmall,
      textTheme.bodyLarge,
      textTheme.bodyMedium,
      textTheme.bodySmall,
      textTheme.labelLarge,
      textTheme.labelMedium,
      textTheme.labelSmall,
    ];

    for (final style in styles) {
      expect(style, isNotNull);
      expect(
        validSizes.contains(style!.fontSize),
        isTrue,
        reason: 'fontSize ${style.fontSize} は DESIGN.md のスケールに含まれない',
      );
      expect(style.height, inInclusiveRange(1.5, 1.7));
    }

    // 本文16・補助12（DESIGN.md「タイポグラフィ」）。
    expect(textTheme.bodyLarge!.fontSize, 16);
    expect(textTheme.bodySmall!.fontSize, 12);
  });

  testWidgets('MaterialApp に light/dark 両テーマが Material3 で適用されている', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(mapPathResolver: _missingPackResolver));

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme!.useMaterial3, isTrue);
    expect(materialApp.darkTheme!.useMaterial3, isTrue);
    expect(materialApp.theme!.colorScheme.primary, ColorTokens.primaryLight);
    expect(materialApp.darkTheme!.colorScheme.primary, ColorTokens.primaryDark);
  });

  testWidgets('下部ナビは地図/建設/図鑑/設定の4タブで構成される', (tester) async {
    await tester.pumpWidget(MyApp(mapPathResolver: _missingPackResolver));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text('地図'), findsWidgets);
    expect(find.text('建設'), findsOneWidget);
    expect(find.text('図鑑'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);
  });

  testWidgets('タブ切り替えでカウンターデモは存在しない（+ボタン・カウンター文言なし）', (tester) async {
    await tester.pumpWidget(MyApp(mapPathResolver: _missingPackResolver));

    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.textContaining('pushed the button'), findsNothing);
  });

  testWidgets('建設タブに切り替えると資材インベントリ画面（Issue #150）が表示される', (
    tester,
  ) async {
    await tester.pumpWidget(
      MyApp(
        mapPathResolver: _missingPackResolver,
        gameDatabaseBuilder: GameDatabase.forTesting,
      ),
    );

    await tester.tap(find.text('建設'));
    await tester.pumpAndSettle();

    // 新規ゲームDB（インメモリ）は所持資材が0件のため空状態になる
    // （InventoryScreen クラスdoc「所持数が0の資材の扱い」参照）。
    expect(find.text('まだ資材がありません'), findsOneWidget);
  });

  testWidgets('設定タブに切り替えるとスイッチ（歩数判定オプトアウト・Issue #135）が表示される', (
    tester,
  ) async {
    await tester.pumpWidget(
      MyApp(
        mapPathResolver: _missingPackResolver,
        gameDatabaseBuilder: GameDatabase.forTesting,
      ),
    );

    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();

    expect(find.text('歩数による判定を使わない'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  group('日本語ロケール（Issue #51）', () {
    testWidgets('端末ロケールが日本語なら Material 標準文言は日本語', (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('ja', 'JP');
      tester.platformDispatcher.localesTestValue = const [Locale('ja', 'JP')];
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(MyApp(mapPathResolver: _missingPackResolver));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(NavigationBar));
      expect(Localizations.localeOf(context), const Locale('ja'));
      expect(
        MaterialLocalizations.of(context).cancelButtonLabel,
        'キャンセル',
      );
    });

    testWidgets('端末ロケールが英語でも locale 固定により Material 標準文言は日本語のまま', (
      tester,
    ) async {
      // MVP は UI 文言が日本語直書きのため、MaterialApp.locale を ja に固定している
      // （main.dart 参照）。端末設定が英語でも表示が英日混在にならないことを確認する。
      tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
      tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(MyApp(mapPathResolver: _missingPackResolver));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(NavigationBar));
      expect(Localizations.localeOf(context), const Locale('ja'));
      expect(
        MaterialLocalizations.of(context).cancelButtonLabel,
        'キャンセル',
      );
    });
  });
}
