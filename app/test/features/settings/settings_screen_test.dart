// SettingsScreen（Issue #135・Issue #180）のウィジェットテスト。
//
// RewardSettingsStore・SaveDataTransfer・SaveDataFileAccess・RecordingStatusCheck
// （terra_town_location／save_data_transfer_adapters.dart）を実装したフェイクを
// 注入し、Drift の実DB・Pigeon・SAF に一切触れずに決定的に検証する。
// 「settings テーブルへの実際の保存」「SaveDataTransferServiceの往復・
// ウォーターマーク補正・ロールバック」はそれぞれ
// packages/location/test/db/reward_settings_repository_test.dart・
// packages/location/test/save_data/save_data_transfer_service_test.dart が担当する。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'package:terra_town/design/app_theme.dart';
import 'package:terra_town/features/settings/save_data_transfer_adapters.dart';
import 'package:terra_town/features/settings/settings_screen.dart';

class _FakeRewardSettingsStore implements RewardSettingsStore {
  _FakeRewardSettingsStore({
    bool initialValue = false,
    this.throwOnSave = false,
    this.throwOnLoad = false,
  }) : _value = initialValue;

  bool _value;
  final bool throwOnSave;
  final bool throwOnLoad;
  bool? lastSavedValue;

  @override
  Future<bool> isStepCheckDisabled() async {
    if (throwOnLoad) {
      throw StateError('読み込み失敗（テスト用フェイク）');
    }
    return _value;
  }

  @override
  Future<void> setStepCheckDisabled(bool value) async {
    if (throwOnSave) {
      throw StateError('保存失敗（テスト用フェイク）');
    }
    _value = value;
    lastSavedValue = value;
  }
}

/// [SaveDataTransfer] のフェイク（Issue #180）。
class _FakeSaveDataTransfer implements SaveDataTransfer {
  _FakeSaveDataTransfer({
    this.exportResult = '{"fake":"export"}',
    this.exportError,
    this.summary,
    this.summaryError,
    this.importResult = '/fake/backups/pre-import-1.json',
    this.importError,
  });

  final String exportResult;
  final Object? exportError;
  SaveDataSummary? summary;
  final Object? summaryError;
  final String importResult;
  final Object? importError;

  String? lastExportAppVersion;
  String? lastExportPackVersion;
  String? lastImportedJson;

  @override
  Future<String> exportToJsonString({
    required String appVersion,
    required String packVersion,
  }) async {
    lastExportAppVersion = appVersion;
    lastExportPackVersion = packVersion;
    if (exportError != null) throw exportError!;
    return exportResult;
  }

  @override
  SaveDataSummary parseSummary(String jsonString) {
    if (summaryError != null) throw summaryError!;
    return summary!;
  }

  @override
  Future<String> importFromJsonString(String jsonString) async {
    lastImportedJson = jsonString;
    if (importError != null) throw importError!;
    return importResult;
  }
}

/// [SaveDataFileAccess] のフェイク（Issue #180）。
class _FakeSaveDataFileAccess implements SaveDataFileAccess {
  _FakeSaveDataFileAccess({this.saveResult = true, this.openResult});

  final bool saveResult;
  final String? openResult;

  bool saveCalled = false;
  bool openCalled = false;
  String? lastSuggestedFileName;
  String? lastSavedContents;

  @override
  Future<bool> saveTextFile(String suggestedFileName, String contents) async {
    saveCalled = true;
    lastSuggestedFileName = suggestedFileName;
    lastSavedContents = contents;
    return saveResult;
  }

  @override
  Future<String?> openTextFile() async {
    openCalled = true;
    return openResult;
  }
}

/// [RecordingStatusCheck] のフェイク（Issue #180 決定事項4「記録中は読み込みを拒否」）。
class _FakeRecordingStatusCheck implements RecordingStatusCheck {
  _FakeRecordingStatusCheck({this.recording = false});

  final bool recording;

  @override
  Future<bool> isRecording() async => recording;
}

Widget _wrap(Widget child) {
  return MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));
}

SettingsScreen _buildScreen({
  RewardSettingsStore? store,
  SaveDataTransfer? saveDataTransfer,
  SaveDataFileAccess? saveDataFileAccess,
  RecordingStatusCheck? recordingStatusCheck,
  VoidCallback? onDataRestored,
}) {
  return SettingsScreen(
    store: store ?? _FakeRewardSettingsStore(),
    saveDataTransfer: saveDataTransfer ?? _FakeSaveDataTransfer(),
    saveDataFileAccess: saveDataFileAccess ?? _FakeSaveDataFileAccess(),
    recordingStatusCheck:
        recordingStatusCheck ?? _FakeRecordingStatusCheck(),
    resolvePackVersion: () async => 'pack-v1',
    appVersion: '1.0.0+1',
    onDataRestored: onDataRestored,
  );
}

void main() {
  group('SettingsScreen（歩数判定オプトアウト・Issue #135）', () {
    testWidgets('既定（オフ）のとき、スイッチはオフで見出し・説明文が表示される', (tester) async {
      final store = _FakeRewardSettingsStore();
      await tester.pumpWidget(_wrap(_buildScreen(store: store)));
      await tester.pumpAndSettle();

      expect(find.text('歩数による判定を使わない'), findsOneWidget);
      expect(
        find.text(
          '車いす・自転車など、歩数が出ない移動で遊ぶときにオンにします。'
          'オンにしても、位置の偽装の検出と時速10km超の判定は働きます。',
        ),
        findsOneWidget,
      );
      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isFalse);
    });

    testWidgets('保存済みの値がオンなら、スイッチはオンで表示される', (tester) async {
      final store = _FakeRewardSettingsStore(initialValue: true);
      await tester.pumpWidget(_wrap(_buildScreen(store: store)));
      await tester.pumpAndSettle();

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isTrue);
    });

    testWidgets('スイッチをタップすると保存され、表示もオンに切り替わる', (tester) async {
      final store = _FakeRewardSettingsStore();
      await tester.pumpWidget(_wrap(_buildScreen(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(store.lastSavedValue, isTrue);
      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isTrue);
    });

    testWidgets('保存に失敗した場合、表示は操作前の値に戻りSnackBarでエラーを通知する', (tester) async {
      final store = _FakeRewardSettingsStore(throwOnSave: true);
      await tester.pumpWidget(_wrap(_buildScreen(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isFalse, reason: '保存失敗時は操作前の値（オフ）に戻る');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('設定の保存に失敗しました'), findsOneWidget);
    });

    testWidgets('読み込みに失敗した場合、エラー表示とやり直しボタンが出る', (tester) async {
      final store = _FakeRewardSettingsStore(throwOnLoad: true);
      await tester.pumpWidget(_wrap(_buildScreen(store: store)));
      await tester.pumpAndSettle();

      expect(find.text('設定を読み込めませんでした'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'やり直す'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });
  });

  group('SettingsScreen（データの書き出し・Issue #180）', () {
    testWidgets('注意ダイアログに同意すると書き出され、SnackBarで成功が通知される', (tester) async {
      final transfer = _FakeSaveDataTransfer(exportResult: '{"a":1}');
      final fileAccess = _FakeSaveDataFileAccess(saveResult: true);
      await tester.pumpWidget(
        _wrap(
          _buildScreen(saveDataTransfer: transfer, saveDataFileAccess: fileAccess),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('データの書き出し'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('信頼できる保存先にだけ保存してください'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, '書き出す'));
      await tester.pumpAndSettle();

      expect(fileAccess.saveCalled, isTrue);
      expect(fileAccess.lastSavedContents, '{"a":1}');
      expect(
        fileAccess.lastSuggestedFileName,
        matches(RegExp(r'^terra-town-save-\d{8}-\d{4}\.json$')),
      );
      expect(transfer.lastExportAppVersion, '1.0.0+1');
      expect(transfer.lastExportPackVersion, 'pack-v1');
      expect(find.text('データを書き出しました'), findsOneWidget);
    });

    testWidgets('注意ダイアログでキャンセルすると書き出さない', (tester) async {
      final fileAccess = _FakeSaveDataFileAccess();
      await tester.pumpWidget(
        _wrap(_buildScreen(saveDataFileAccess: fileAccess)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('データの書き出し'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'キャンセル'));
      await tester.pumpAndSettle();

      expect(fileAccess.saveCalled, isFalse);
    });

    testWidgets('SAFピッカーでキャンセルした場合は成功SnackBarを出さない', (tester) async {
      final fileAccess = _FakeSaveDataFileAccess(saveResult: false);
      await tester.pumpWidget(
        _wrap(_buildScreen(saveDataFileAccess: fileAccess)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('データの書き出し'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '書き出す'));
      await tester.pumpAndSettle();

      expect(fileAccess.saveCalled, isTrue);
      expect(find.text('データを書き出しました'), findsNothing);
    });

    testWidgets('書き出しに失敗した場合はSnackBarでエラーを通知する', (tester) async {
      final transfer = _FakeSaveDataTransfer(exportError: StateError('書き出し失敗'));
      await tester.pumpWidget(_wrap(_buildScreen(saveDataTransfer: transfer)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('データの書き出し'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '書き出す'));
      await tester.pumpAndSettle();

      expect(find.textContaining('データの書き出しに失敗しました'), findsOneWidget);
    });
  });

  group('SettingsScreen（データの読み込み・Issue #180）', () {
    testWidgets('記録中はエラーダイアログを表示し、ファイル選択に進まない', (tester) async {
      final fileAccess = _FakeSaveDataFileAccess(openResult: '{}');
      final recordingCheck = _FakeRecordingStatusCheck(recording: true);
      await tester.pumpWidget(
        _wrap(
          _buildScreen(
            saveDataFileAccess: fileAccess,
            recordingStatusCheck: recordingCheck,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('データの読み込み'));
      await tester.pumpAndSettle();

      expect(find.text('読み込めません'), findsOneWidget);
      expect(find.textContaining('記録を停止してから'), findsOneWidget);
      expect(fileAccess.openCalled, isFalse);
    });

    testWidgets('ファイル選択をキャンセルすると何も起きない', (tester) async {
      final fileAccess = _FakeSaveDataFileAccess(openResult: null);
      await tester.pumpWidget(
        _wrap(_buildScreen(saveDataFileAccess: fileAccess)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('データの読み込み'));
      await tester.pumpAndSettle();

      expect(fileAccess.openCalled, isTrue);
      expect(find.text('このデータを読み込みますか？'), findsNothing);
    });

    testWidgets('壊れたファイルの場合はエラーダイアログを表示する', (tester) async {
      final fileAccess = _FakeSaveDataFileAccess(openResult: '{bad json');
      final transfer = _FakeSaveDataTransfer(
        summaryError: const SaveDataFormatException('JSONとして解釈できません'),
      );
      await tester.pumpWidget(
        _wrap(
          _buildScreen(saveDataTransfer: transfer, saveDataFileAccess: fileAccess),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('データの読み込み'));
      await tester.pumpAndSettle();

      expect(find.text('読み込めません'), findsOneWidget);
      expect(find.textContaining('ファイルの内容を読み取れませんでした'), findsOneWidget);
    });

    testWidgets('新しいschema_versionのファイルはアプリ更新を促すメッセージを表示する', (
      tester,
    ) async {
      final fileAccess = _FakeSaveDataFileAccess(openResult: '{}');
      final transfer = _FakeSaveDataTransfer(
        summaryError: const SaveDataSchemaTooNewException(
          foundVersion: 4,
          supportedVersion: 3,
        ),
      );
      await tester.pumpWidget(
        _wrap(
          _buildScreen(saveDataTransfer: transfer, saveDataFileAccess: fileAccess),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('データの読み込み'));
      await tester.pumpAndSettle();

      expect(find.textContaining('アプリを更新してから'), findsOneWidget);
    });

    testWidgets('確認ダイアログに書き出し日時・開示数・開放ポイント・収集数が表示される', (
      tester,
    ) async {
      final fileAccess = _FakeSaveDataFileAccess(openResult: '{}');
      final transfer = _FakeSaveDataTransfer(
        summary: SaveDataSummary(
          exportedAt: DateTime.utc(2026, 9, 14, 10, 30),
          disclosedHexCount: 9,
          openingPoints: 3,
          collectionCount: 1,
        ),
      );
      await tester.pumpWidget(
        _wrap(
          _buildScreen(saveDataTransfer: transfer, saveDataFileAccess: fileAccess),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('データの読み込み'));
      await tester.pumpAndSettle();

      expect(find.text('このデータを読み込みますか？'), findsOneWidget);
      expect(find.textContaining('開示済みヘクス: 9件'), findsOneWidget);
      expect(find.textContaining('開放ポイント: 3P'), findsOneWidget);
      expect(find.textContaining('名所の収集数: 1件'), findsOneWidget);
      expect(
        find.textContaining('上書き前に自動でバックアップします'),
        findsOneWidget,
      );
    });

    testWidgets('確認ダイアログでキャンセルすると読み込まれない', (tester) async {
      final fileAccess = _FakeSaveDataFileAccess(openResult: '{}');
      final transfer = _FakeSaveDataTransfer(
        summary: SaveDataSummary(
          exportedAt: DateTime.utc(2026, 9, 14),
          disclosedHexCount: 1,
          openingPoints: 0,
          collectionCount: 0,
        ),
      );
      await tester.pumpWidget(
        _wrap(
          _buildScreen(saveDataTransfer: transfer, saveDataFileAccess: fileAccess),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('データの読み込み'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'キャンセル'));
      await tester.pumpAndSettle();

      expect(transfer.lastImportedJson, isNull);
    });

    testWidgets('同意すると読み込まれ、成功メッセージが表示されonDataRestoredが呼ばれる', (
      tester,
    ) async {
      final fileAccess = _FakeSaveDataFileAccess(openResult: '{"ok":true}');
      final transfer = _FakeSaveDataTransfer(
        summary: SaveDataSummary(
          exportedAt: DateTime.utc(2026, 9, 14),
          disclosedHexCount: 1,
          openingPoints: 0,
          collectionCount: 0,
        ),
        importResult: '/fake/backups/pre-import-9.json',
      );
      var restoredCalled = false;
      await tester.pumpWidget(
        _wrap(
          _buildScreen(
            saveDataTransfer: transfer,
            saveDataFileAccess: fileAccess,
            onDataRestored: () => restoredCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('データの読み込み'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '読み込む'));
      await tester.pumpAndSettle();

      expect(transfer.lastImportedJson, '{"ok":true}');
      expect(find.textContaining('データを読み込みました'), findsOneWidget);
      expect(find.textContaining('/fake/backups/pre-import-9.json'), findsOneWidget);
      expect(restoredCalled, isTrue);
    });

    testWidgets('自動バックアップに失敗した場合は中断メッセージを表示する', (tester) async {
      final fileAccess = _FakeSaveDataFileAccess(openResult: '{}');
      final transfer = _FakeSaveDataTransfer(
        summary: SaveDataSummary(
          exportedAt: DateTime.utc(2026, 9, 14),
          disclosedHexCount: 1,
          openingPoints: 0,
          collectionCount: 0,
        ),
        importError: const SaveDataBackupFailedException('disk full'),
      );
      await tester.pumpWidget(
        _wrap(
          _buildScreen(saveDataTransfer: transfer, saveDataFileAccess: fileAccess),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('データの読み込み'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '読み込む'));
      await tester.pumpAndSettle();

      expect(find.text('読み込みを中断しました'), findsOneWidget);
      expect(find.textContaining('現在のデータは変更されていません'), findsOneWidget);
    });

    testWidgets('読み込みに失敗した場合はバックアップの場所を含む復旧案内を表示する', (
      tester,
    ) async {
      final fileAccess = _FakeSaveDataFileAccess(openResult: '{}');
      final transfer = _FakeSaveDataTransfer(
        summary: SaveDataSummary(
          exportedAt: DateTime.utc(2026, 9, 14),
          disclosedHexCount: 1,
          openingPoints: 0,
          collectionCount: 0,
        ),
        importError: const SaveDataImportFailedException(
          backupFilePath: '/fake/backups/pre-import-recovery.json',
          cause: '制約違反（テスト用）',
        ),
      );
      await tester.pumpWidget(
        _wrap(
          _buildScreen(saveDataTransfer: transfer, saveDataFileAccess: fileAccess),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('データの読み込み'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '読み込む'));
      await tester.pumpAndSettle();

      expect(find.text('読み込みに失敗しました'), findsOneWidget);
      expect(
        find.textContaining('/fake/backups/pre-import-recovery.json'),
        findsOneWidget,
      );
    });
  });
}
