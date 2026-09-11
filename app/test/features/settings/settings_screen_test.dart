// SettingsScreen（Issue #135）のウィジェットテスト。
//
// RewardSettingsStore（terra_town_location）を実装したフェイクを注入し、
// 初期状態の反映・トグル操作での保存・保存失敗時の復元（悲観的更新）を
// Drift の実DBを経由せず決定的に検証する。
// 「settings テーブルへの実際の保存・既定値」は
// packages/location/test/db/reward_settings_repository_test.dart が担当する。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'package:terra_town/design/app_theme.dart';
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

Widget _wrap(Widget child) {
  return MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));
}

void main() {
  group('SettingsScreen', () {
    testWidgets('既定（オフ）のとき、スイッチはオフで見出し・説明文が表示される', (tester) async {
      final store = _FakeRewardSettingsStore();
      await tester.pumpWidget(_wrap(SettingsScreen(store: store)));
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
      await tester.pumpWidget(_wrap(SettingsScreen(store: store)));
      await tester.pumpAndSettle();

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isTrue);
    });

    testWidgets('スイッチをタップすると保存され、表示もオンに切り替わる', (tester) async {
      final store = _FakeRewardSettingsStore();
      await tester.pumpWidget(_wrap(SettingsScreen(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(store.lastSavedValue, isTrue);
      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isTrue);
    });

    testWidgets('保存に失敗した場合、表示は操作前の値に戻りSnackBarでエラーを通知する', (tester) async {
      final store = _FakeRewardSettingsStore(throwOnSave: true);
      await tester.pumpWidget(_wrap(SettingsScreen(store: store)));
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
      await tester.pumpWidget(_wrap(SettingsScreen(store: store)));
      await tester.pumpAndSettle();

      expect(find.text('設定を読み込めませんでした'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'やり直す'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });
  });
}
