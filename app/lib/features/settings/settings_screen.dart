import 'package:flutter/material.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../design/spacing.dart';

/// 設定タブ（DESIGN.md「画面一覧と状態」設定行）の最小実装（Issue #135）。
///
/// 本 Issue で置くのは「歩数による判定を使わない」スイッチ1つのみ。
/// プライバシーゾーン（T103）・通知（T078）等、他の設定項目は本 Issue の
/// スコープ外（Issue #135 本文「スコープ外」）。将来それらが並ぶことを見越して
/// 本画面は [ListView] 1本の構成にしてあり、項目を増やすだけで拡張できる。
///
/// ## DESIGN.md「画面一覧と状態」の4状態のうち本画面が扱うもの
/// - ローディング = [store] からの読み出し中（[_SettingsLoadingView]）
/// - エラー = 読み出し失敗（[_SettingsErrorView]。やり直しボタンつき）
/// - 通常 = 読み出し成功（スイッチが操作可能）
/// - 空 = 該当しない（設定項目は常に1つ以上存在するため未実装）
///
/// ## [store] を抽象（[RewardSettingsStore]）で受け取る理由
/// `app` は Drift・`GameDatabase` を直接知らなくてよいようにする
/// （設定画面の単体テストではフェイクを注入し、保存失敗を決定的に再現するため。
/// 本番では `terra_town_location` の `RewardSettingsRepository` を渡す）。
///
/// ## 保存失敗時の扱い（PR本文にも記載・悲観的更新）
/// スイッチの操作は楽観的更新にせず、[RewardSettingsStore.setStepCheckDisabled]
/// が完了してから表示を更新する。保存中はスイッチを操作不可にし、失敗した場合は
/// 表示を操作前の値に戻したうえで [SnackBar] でエラーを通知する
/// （DESIGN.md「破壊的操作は確認/Undo必須」ほど重い操作ではないため、
/// 確認ダイアログまでは設けない）。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store});

  /// 歩数判定オプトアウト設定の読み書き先。本番では
  /// `RewardSettingsRepository`（`terra_town_location`）を渡す。
  final RewardSettingsStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _LoadState { loading, loaded, error }

class _SettingsScreenState extends State<SettingsScreen> {
  _LoadState _loadState = _LoadState.loading;
  bool _stepCheckDisabled = false;
  bool _saving = false;
  Object? _loadError;

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
            ],
          ),
        );
    }
  }
}

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
