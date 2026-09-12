import 'package:flutter/material.dart';

import 'location_permission_gateway.dart';

/// 位置情報権限が拒否された場合の案内ダイアログ（Issue #142・T059 受け入れ基準
/// 「拒否・永久拒否のそれぞれで適切な案内が出る」）。
///
/// **「なぜ必要か」を説明したうえで**、状態に応じて導線を変える:
///   - [LocationPermissionState.denied]（永久拒否ではない）: 「もう一度リクエストする」
///     ボタンで [onRetryRequest] を呼ぶ。Android では再度OSの許可ダイアログが表示されうる。
///   - [LocationPermissionState.permanentlyDenied]: OSはもうダイアログを出さないため、
///     「設定を開く」ボタンで [onOpenSettings] を呼び、端末の設定アプリへ誘導する。
///
/// ボタンは Material 3 標準コンポーネント（[TextButton]/[FilledButton]）のみを使う
/// （DESIGN.md「プロジェクト固有ルール」）。色は [AlertDialog] 既定のテーマ配色に任せ、
/// 本ファイルは色リテラル・独自トークンを一切持たない。
Future<void> showLocationPermissionGuidanceDialog({
  required BuildContext context,
  required LocationPermissionState state,
  required VoidCallback onRetryRequest,
  required VoidCallback onOpenSettings,
}) {
  assert(
    state != LocationPermissionState.granted,
    '許可済みの状態でこのダイアログを呼び出さないこと（呼び出し側の分岐漏れ）',
  );
  final isPermanentlyDenied = state == LocationPermissionState.permanentlyDenied;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('位置情報の権限が必要です'),
        content: Text(
          isPermanentlyDenied
              ? _permanentlyDeniedMessage
              : _deniedMessage,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('キャンセル'),
          ),
          if (isPermanentlyDenied)
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onOpenSettings();
              },
              child: const Text('設定を開く'),
            )
          else
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onRetryRequest();
              },
              child: const Text('もう一度リクエストする'),
            ),
        ],
      );
    },
  );
}

// 【文言の正確性について・Issue #142 advisor指摘】以前の草稿は「アプリを閉じている間や
// 画面オフの間は位置情報を取得しない」としていたが、これは事実と異なる。記録中は
// フォアグラウンドサービス（常駐通知つき）が動き続け、画面を消してもアプリを
// バックグラウンドに回しても記録は継続する（`docs/location-track-db.md` §7 参照。
// 停止するのは明示的な「記録を停止する」操作のみ）。ここで正確に区別すべきなのは
// 「バックグラウンドでも記録し続けるか」ではなく、「バックグラウンド**位置権限**
// （`ACCESS_BACKGROUND_LOCATION`）を要求するか」であり、本アプリは後者を要求しない
// （フォアグラウンドサービスの例外により、前者はその権限が無くても実現できる）。
const _deniedMessage =
    'terra-townは、あなたが歩いた場所の地図を切り開くために現在地（位置情報）を使います。\n\n'
    '記録中は、画面を消したり他のアプリに切り替えても、通知を表示しながら記録を続けます。'
    '記録を停止すると位置情報は使いません。\n\n'
    '続けるには「アプリの使用中のみ許可」を選んでください（常に許可は不要です）。';

const _permanentlyDeniedMessage =
    '位置情報の権限が拒否されているため、アプリからは再度リクエストできません'
    '（2回連続で拒否すると、端末が自動的にこの状態にすることがあります）。\n\n'
    'terra-townは、あなたが歩いた場所の地図を切り開くために現在地（位置情報）を使います。'
    '記録中は画面を消したり他のアプリに切り替えても記録を続けますが、常に許可（背景位置）は'
    '不要です。\n\n'
    '端末の設定アプリから、terra-townに位置情報の使用を許可してください。';
