import 'package:flutter/material.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../app_version.dart';
import '../../design/spacing.dart';
import 'pack_version_reader.dart';
import 'save_data_transfer_adapters.dart';

/// 設定タブ（DESIGN.md「画面一覧と状態」設定行）の実装（Issue #135・Issue #180）。
///
/// Issue #135（歩数判定オプトアウト）に加え、Issue #180（T105）で
/// 「データの書き出し」「データの読み込み」を追加した。プライバシーゾーン（T103）・
/// 通知（T078）等、他の設定項目は引き続き別Issueのスコープ。
///
/// ## DESIGN.md「画面一覧と状態」の4状態のうち本画面が扱うもの
/// - ローディング = [store] からの読み出し中（[_SettingsLoadingView]）
/// - エラー = 読み出し失敗（[_SettingsErrorView]。やり直しボタンつき）／
///   インポート失敗時の復旧案内（`_showRecoveryDialog`。決定事項4）
/// - 通常 = 読み出し成功（スイッチ・エクスポート/インポート操作可能）
/// - 空 = 該当しない（設定項目は常に1つ以上存在するため未実装）
///
/// ## [store]・[saveDataTransfer]・[saveDataFileAccess]・[recordingStatusCheck] を
/// 抽象で受け取る理由
/// `app` は Drift・`GameDatabase`・Pigeon を直接知らなくてよいようにする
/// （設定画面の単体テストではフェイクを注入し、保存失敗・インポート失敗・
/// 記録中ガード等を決定的に再現するため）。本番では `RootScaffold` が
/// `SaveDataTransferService`・`PigeonSaveDataFileChannel`・
/// `NativeLocationTrackingControl` をそれぞれ包んだ実装を渡す。
///
/// ## エクスポート/インポートの流れ（Issue #180 決定事項4・5）
/// - 書き出し: 注意ダイアログ（決定事項5の文言）→ 同意で
///   [SaveDataTransfer.exportToJsonString] → [SaveDataFileAccess.saveTextFile]
///   （SAF の保存ピッカー）。
/// - 読み込み: [RecordingStatusCheck.isRecording] で記録中を拒否 →
///   [SaveDataFileAccess.openTextFile]（SAF の選択ピッカー）→
///   [SaveDataTransfer.parseSummary] で検証・要約取得（失敗時はここで復旧案内） →
///   確認ダイアログ（要約 + 上書き警告） → 同意で
///   [SaveDataTransfer.importFromJsonString]（内部で自動バックアップ→
///   1トランザクションで読み込み） → 成功したら [onDataRestored] を呼び、
///   アプリの状態を全体的に作り直す（`main.dart` の `MyApp` が `RootScaffold` の
///   `Key` を変える。Issue #180 決定事項4「アプリの状態を全体的に作り直す」）。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.store,
    required this.saveDataTransfer,
    required this.saveDataFileAccess,
    required this.recordingStatusCheck,
    this.resolvePackVersion = defaultResolvePackVersion,
    this.appVersion = kAppVersion,
    this.onDataRestored,
  });

  /// 歩数判定オプトアウト設定の読み書き先。本番では
  /// `RewardSettingsRepository`（`terra_town_location`）を渡す。
  final RewardSettingsStore store;

  /// セーブデータの Drift⇔JSON 処理。本番では [LocationSaveDataTransfer]。
  final SaveDataTransfer saveDataTransfer;

  /// SAF 経由のファイル受け渡し。本番では [PigeonSaveDataFileAccess]。
  final SaveDataFileAccess saveDataFileAccess;

  /// 記録中（foreground service 稼働中）かどうかの確認。本番では
  /// [NativeRecordingStatusCheck]。
  final RecordingStatusCheck recordingStatusCheck;

  /// エクスポートのメタデータ `pack_version` の取得元（既定は同梱パックから読む）。
  final ResolvePackVersion resolvePackVersion;

  /// エクスポートのメタデータ `app_version`（既定は [kAppVersion]）。
  final String appVersion;

  /// インポート成功後に呼ばれるコールバック（`main.dart` の `MyApp` が
  /// `RootScaffold` の `Key` を変えてアプリの状態を作り直すために使う）。
  /// このコールバックの呼び出しにより本ウィジェット自体も破棄される
  /// （呼び出し後は `setState` を呼ばないこと）。
  final VoidCallback? onDataRestored;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _LoadState { loading, loaded, error }

class _SettingsScreenState extends State<SettingsScreen> {
  _LoadState _loadState = _LoadState.loading;
  bool _stepCheckDisabled = false;
  bool _saving = false;
  Object? _loadError;

  bool _exporting = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadState = _LoadState.loading;
      _loadError = null;
    });
    try {
      final value = await widget.store.isStepCheckDisabled();
      if (!mounted) return;
      setState(() {
        _stepCheckDisabled = value;
        _loadState = _LoadState.loaded;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loadState = _LoadState.error;
      });
    }
  }

  Future<void> _onChanged(bool newValue) async {
    final previousValue = _stepCheckDisabled;
    setState(() => _saving = true);
    try {
      await widget.store.setStepCheckDisabled(newValue);
      if (!mounted) return;
      setState(() {
        _stepCheckDisabled = newValue;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stepCheckDisabled = previousValue; // 保存失敗時は操作前の値に戻す
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('設定の保存に失敗しました: $error')),
      );
    }
  }

  // --- データの書き出し（Issue #180 決定事項5・6） --------------------------

  Future<void> _onExportPressed() async {
    final proceed = await _showExportNoticeDialog();
    if (proceed != true) return;
    if (!mounted) return;

    setState(() => _exporting = true);
    try {
      final packVersion = await widget.resolvePackVersion();
      final jsonContents = await widget.saveDataTransfer.exportToJsonString(
        appVersion: widget.appVersion,
        packVersion: packVersion,
      );
      final suggestedFileName = _defaultExportFileName(DateTime.now());
      final saved = await widget.saveDataFileAccess.saveTextFile(
        suggestedFileName,
        jsonContents,
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('データを書き出しました')));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('データの書き出しに失敗しました: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<bool?> _showExportNoticeDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('データの書き出し'),
        content: const Text(
          'このファイルには、歩いて開拓した場所（地図上のマス）の情報が含まれます。'
          '信頼できる保存先にだけ保存してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('書き出す'),
          ),
        ],
      ),
    );
  }

  // --- データの読み込み（Issue #180 決定事項4） ------------------------------

  Future<void> _onImportPressed() async {
    setState(() => _importing = true);
    try {
      final recording = await widget.recordingStatusCheck.isRecording();
      if (recording) {
        if (!mounted) return;
        await _showRecoveryDialog(
          title: '読み込めません',
          message: '記録中は読み込みできません。記録を停止してから、もう一度お試しください。',
        );
        return;
      }

      final content = await widget.saveDataFileAccess.openTextFile();
      if (content == null) return; // ユーザーがピッカーをキャンセルした。
      if (!mounted) return;

      final SaveDataSummary summary;
      try {
        summary = widget.saveDataTransfer.parseSummary(content);
      } on SaveDataSchemaTooNewException {
        if (!mounted) return;
        await _showRecoveryDialog(
          title: '読み込めません',
          message: 'このファイルは新しいバージョンのアプリで書き出されています。'
              'アプリを更新してから、もう一度お試しください。',
        );
        return;
      } on SaveDataSchemaMigrationUnsupportedException {
        if (!mounted) return;
        await _showRecoveryDialog(
          title: '読み込めません',
          message: 'このファイルの形式（古いバージョンのセーブデータ）の読み込みには、'
              'まだ対応していません。',
        );
        return;
      } on SaveDataFormatException catch (error) {
        if (!mounted) return;
        await _showRecoveryDialog(
          title: '読み込めません',
          message: 'ファイルの内容を読み取れませんでした。壊れているか、'
              'terra-town のセーブデータではない可能性があります。\n($error)',
        );
        return;
      }

      if (!mounted) return;
      final confirmed = await _showImportConfirmationDialog(summary);
      if (confirmed != true) return;
      if (!mounted) return;

      final String backupFilePath;
      try {
        backupFilePath = await widget.saveDataTransfer.importFromJsonString(
          content,
        );
      } on SaveDataBackupFailedException {
        if (!mounted) return;
        await _showRecoveryDialog(
          title: '読み込みを中断しました',
          message: '上書き前の自動バックアップの作成に失敗したため、読み込みを中断しました。'
              '現在のデータは変更されていません。',
        );
        return;
      } on SaveDataImportFailedException catch (error) {
        if (!mounted) return;
        await _showRecoveryDialog(
          title: '読み込みに失敗しました',
          message: '読み込み中にエラーが発生したため、データは読み込み前の状態のままです。\n\n'
              '自動バックアップの保存先:\n${error.backupFilePath}\n\n'
              'もう一度ファイルを選び直してお試しください。',
        );
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('データを読み込みました（バックアップ: $backupFilePath）')),
      );
      // クラスdoc参照: このコールバックによりアプリの状態が全体的に作り直され、
      // 本ウィジェット自体も破棄される。以後 setState を呼ばない。
      widget.onDataRestored?.call();
    } catch (error) {
      // 上記の個別 catch が拾わない例外（記録中確認・ファイル選択の Pigeon 呼び出し
      // 自体の失敗〔`PlatformException`〕、[SaveDataTransfer.importFromJsonString]
      // 内部でトランザクション開始前に失敗した場合〔`getMaxLocationPointId`・
      // バックアップ用のエクスポート自体〕等）を拾う最後の砦。
      //
      // これらはいずれも `GameDatabase.transaction`（削除・挿入）に到達する前の
      // 失敗であるため、「データは読み込み前の状態のまま」という説明は常に正しい
      // （トランザクション自体の失敗は [SaveDataImportFailedException] として
      // 個別 catch 済み）。
      if (!mounted) return;
      await _showRecoveryDialog(
        title: '読み込みに失敗しました',
        message: '予期しないエラーが発生したため、読み込みを中断しました。'
            'データは読み込み前の状態のままです。もう一度お試しください。\n($error)',
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<bool?> _showImportConfirmationDialog(SaveDataSummary summary) {
    final theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('このデータを読み込みますか？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('書き出し日時: ${_formatDateTime(summary.exportedAt.toLocal())}'),
            const SizedBox(height: AppSpacing.xs),
            Text('開示済みヘクス: ${summary.disclosedHexCount}件'),
            Text('開放ポイント: ${summary.openingPoints}P'),
            Text('名所の収集数: ${summary.collectionCount}件'),
            const SizedBox(height: AppSpacing.md),
            Text(
              '現在のデータは上書きされます（上書き前に自動でバックアップします）。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('読み込む'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRecoveryDialog({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_loadState) {
      case _LoadState.loading:
        return const _SettingsLoadingView();
      case _LoadState.error:
        return _SettingsErrorView(error: _loadError!, onRetry: _load);
      case _LoadState.loaded:
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SwitchListTile(
                title: const Text('歩数による判定を使わない'),
                subtitle: const Text(
                  '車いす・自転車など、歩数が出ない移動で遊ぶときにオンにします。'
                  'オンにしても、位置の偽装の検出と時速10km超の判定は働きます。',
                ),
                value: _stepCheckDisabled,
                onChanged: _saving ? null : _onChanged,
              ),
              const Divider(height: AppSpacing.xl),
              ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('データの書き出し'),
                subtitle: const Text('開拓した場所・資材・設定をファイルに保存します'),
                // 進行中インジケーターは意図的に置かない: 確認ダイアログでの
                // ユーザー入力待ちの間もアニメーションが回り続けると、widget
                // テストの pumpAndSettle が終了しなくなる（不定サイズの
                // CircularProgressIndicator は自己アニメーションが止まらない
                // ため）。多重タップの防止は onTap の無効化だけで十分。
                onTap: _exporting ? null : _onExportPressed,
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('データの読み込み'),
                subtitle: const Text('書き出したファイルから復元します（現在のデータは上書きされます）'),
                onTap: _importing ? null : _onImportPressed,
              ),
            ],
          ),
        );
    }
  }
}

/// SAF の保存ピッカーへ渡す既定のファイル名（Issue #180 決定事項6
/// 「既定のファイル名: `terra-town-save-YYYYMMDD-HHMM.json`」）。端末のローカル
/// 時刻を使う（ユーザーが後でファイル名から判読しやすいようにするため。
/// ファイル中身の `exported_at` はUTCのまま・`save_data_codec.dart` 参照）。
String _defaultExportFileName(DateTime now) {
  final local = now.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = _pad2(local.month);
  final day = _pad2(local.day);
  final hour = _pad2(local.hour);
  final minute = _pad2(local.minute);
  return 'terra-town-save-$year$month$day-$hour$minute.json';
}

/// 確認ダイアログに表示する日時の簡易フォーマット（`intl` 非依存。
/// `_defaultExportFileName` と同じ手書きの0埋め方式）。
String _formatDateTime(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = _pad2(value.month);
  final day = _pad2(value.day);
  final hour = _pad2(value.hour);
  final minute = _pad2(value.minute);
  return '$year-$month-$day $hour:$minute';
}

String _pad2(int value) => value.toString().padLeft(2, '0');

class _SettingsLoadingView extends StatelessWidget {
  const _SettingsLoadingView();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text('設定を読み込み中…', style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SettingsErrorView extends StatelessWidget {
  const _SettingsErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.settings_outlined,
              size: AppSpacing.xxl,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('設定を読み込めませんでした', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '$error',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onRetry, child: const Text('やり直す')),
          ],
        ),
      ),
    );
  }
}
