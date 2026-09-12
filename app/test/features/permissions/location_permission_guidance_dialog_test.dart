import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town/features/permissions/location_permission_gateway.dart';
import 'package:terra_town/features/permissions/location_permission_guidance_dialog.dart';

/// [showLocationPermissionGuidanceDialog] のテスト（Issue #142・T059 受け入れ基準
/// 「拒否・永久拒否のそれぞれで適切な案内が出る（テストがある）」）。
///
/// 「なぜ必要か」の説明文言そのものより、**denied と permanentlyDenied で
/// 出る導線（ボタン）が異なること**・**押したボタンに応じたコールバックが
/// 呼ばれること**を検証する（文言はUI文言のため厳密な一致は求めない）。
void main() {
  Future<void> pumpDialogTrigger(
    WidgetTester tester, {
    required LocationPermissionState state,
    required VoidCallback onRetryRequest,
    required VoidCallback onOpenSettings,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showLocationPermissionGuidanceDialog(
              context: context,
              state: state,
              onRetryRequest: onRetryRequest,
              onOpenSettings: onOpenSettings,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  testWidgets('denied: 再リクエストの導線が出て、タップで onRetryRequest が呼ばれる',
      (tester) async {
    var retryCount = 0;
    var openSettingsCount = 0;
    await pumpDialogTrigger(
      tester,
      state: LocationPermissionState.denied,
      onRetryRequest: () => retryCount++,
      onOpenSettings: () => openSettingsCount++,
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('もう一度リクエストする'), findsOneWidget);
    // 永久拒否用の導線は出ない。
    expect(find.text('設定を開く'), findsNothing);

    await tester.tap(find.text('もう一度リクエストする'));
    await tester.pumpAndSettle();

    expect(retryCount, 1);
    expect(openSettingsCount, 0);
    // ダイアログは閉じている。
    expect(find.text('もう一度リクエストする'), findsNothing);
  });

  testWidgets('permanentlyDenied: 設定を開く導線が出て、タップで onOpenSettings が呼ばれる',
      (tester) async {
    var retryCount = 0;
    var openSettingsCount = 0;
    await pumpDialogTrigger(
      tester,
      state: LocationPermissionState.permanentlyDenied,
      onRetryRequest: () => retryCount++,
      onOpenSettings: () => openSettingsCount++,
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('設定を開く'), findsOneWidget);
    // 再リクエストの導線は出ない（OSがもうダイアログを出さないため）。
    expect(find.text('もう一度リクエストする'), findsNothing);

    await tester.tap(find.text('設定を開く'));
    await tester.pumpAndSettle();

    expect(openSettingsCount, 1);
    expect(retryCount, 0);
  });

  testWidgets('キャンセルするとどちらのコールバックも呼ばれずダイアログが閉じる',
      (tester) async {
    var retryCount = 0;
    var openSettingsCount = 0;
    await pumpDialogTrigger(
      tester,
      state: LocationPermissionState.denied,
      onRetryRequest: () => retryCount++,
      onOpenSettings: () => openSettingsCount++,
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(retryCount, 0);
    expect(openSettingsCount, 0);
    expect(find.text('キャンセル'), findsNothing);
  });
}
