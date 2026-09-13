import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';

import 'package:terra_town/design/app_theme.dart';
import 'package:terra_town/features/map/widgets/hex_opening_sheet.dart';
import 'package:terra_town/map/economy/terrain_yield_pipeline.dart';

/// [HexOpeningSheet] のテスト（Issue #151・T064、Issue #159・T070）。
///
/// Issue #159 の advisor 指摘（2026-09-14）: 名所の収集通知（SnackBar）を
/// シート側の `Navigator.pop()` 戻り値経由で伝える設計は、利用者が「閉じる」
/// ボタン以外（スワイプ・バリアタップ）で閉じると戻り値が `null` になり
/// 抜け漏れる。本テストは、シート自体が [onConfirm] の結果を保持し「開放
/// しました」を表示すること、および `pop()` が引数なしで呼ばれても
/// [onConfirm] が返した結果（収集記録を含む）自体は失われないことを確認する
/// （`map_screen.dart` の `_handleFogHexTapped` はシートの外側で結果を
/// 自前で捕まえる設計にしたため、シート自体の pop 戻り値は検証対象外）。
void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (context) => child,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  final evaluation = HexOpeningEvaluationTestHelper.allowed;

  testWidgets('開放できる場合: 確定すると「開放しました」を表示し、閉じるボタンでシートが閉じる',
      (tester) async {
    HexOpeningAttemptResult? capturedResult;

    await tester.pumpWidget(
      wrap(
        HexOpeningSheet(
          evaluation: evaluation,
          currentPoints: 3,
          onConfirm: () async {
            final result = HexOpeningAttemptResult.success(
              const DisclosedHex(
                hexId: HexId(1),
                terrainType: TerrainType.forest,
                discoveredAtVersion: PackVersion('test'),
              ),
              collectedLandmarks: [
                LandmarkCollectionRecord(
                  poiId: const PointOfInterestId('poi-1'),
                  kind: 'tourism=attraction',
                  name: '六創堂タワー',
                  isBonus: false,
                  collectedAt: DateTime(2026, 9, 14),
                  collectMethod: CollectMethod.point,
                  bonusGranted: null,
                ),
              ],
            );
            capturedResult = result;
            return result;
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('所持ポイント 3P（コスト1P）'), findsOneWidget);

    await tester.tap(find.text('開放ポイントを1P使って開放する'));
    await tester.pumpAndSettle();

    expect(find.text('開放しました'), findsOneWidget);
    // onConfirm の結果（収集記録を含む）は呼び出し側が自前で捕まえられる
    // （map_screen.dart の設計。シートの pop 戻り値には依存しない）。
    expect(capturedResult, isNotNull);
    expect(capturedResult!.collectedLandmarks, hasLength(1));
    expect(capturedResult!.collectedLandmarks.single.name, '六創堂タワー');

    // 「閉じる」で pop() が呼ばれてもシートは正常に閉じる
    // （pop() に値を渡さない実装であることの回帰確認）。
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(find.text('開放しました'), findsNothing);
  });

  testWidgets('開放できない場合: 拒否理由を表示し、ボタンは押せない', (tester) async {
    await tester.pumpWidget(
      wrap(
        HexOpeningSheet(
          evaluation: HexOpeningEvaluation.denied(
            HexOpeningDenialReason.insufficientPoints,
            terrainType: TerrainType.forest,
          ),
          currentPoints: 0,
          onConfirm: () async =>
              HexOpeningAttemptResult.denied(HexOpeningDenialReason.insufficientPoints),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('開放ポイントが足りません（コスト1P）'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}

/// テスト用の共通フィクスチャ（`HexOpeningEvaluation` はコンストラクタが
/// private のため、`allowed` ファクトリを介して1箇所にまとめる）。
abstract final class HexOpeningEvaluationTestHelper {
  static final HexOpeningEvaluation allowed =
      HexOpeningEvaluation.allowed(TerrainType.forest);
}
