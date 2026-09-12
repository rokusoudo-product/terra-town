import 'package:permission_handler/permission_handler.dart' as ph;

/// 位置情報権限（フォアグラウンドのみ）の状態を3値に単純化したもの（Issue #142・T059）。
///
/// `permission_handler` の [ph.PermissionStatus] は iOS 由来の値
/// （`restricted`/`limited`/`provisional`）を含み Android では意味を持たないため、
/// `app` 層はこの3値だけを扱う。
///   - [granted]: 許可済み。記録を開始できる。
///   - [denied]: 未確認、または「今後表示しない」を選ばずに拒否された状態。
///     再度リクエストすればOSの許可ダイアログが**再び表示されうる**。
///   - [permanentlyDenied]: 「今後表示しない」を選んで拒否された状態
///     （Android の `shouldShowRequestPermissionRationale` が false を返す状態。
///     `permission_handler` 内部でこの判定をラップしている）。再度
///     [LocationPermissionGateway.request] を呼んでも**OSはダイアログを出さず
///     即座に拒否を返す**ため、端末の設定アプリへ誘導する以外に許可を得る手段がない。
enum LocationPermissionState { granted, denied, permanentlyDenied }

/// 位置情報権限の確認・要求・設定画面誘導を抽象化したゲートウェイ。
///
/// `permission_handler`（Issue #142・PR本文に追加理由を記載）への直接依存を
/// [PermissionHandlerLocationGateway] 1箇所に閉じ込め、UI 側
/// （`tracking_control_button.dart`）と単体テストはこの抽象だけを見ればよいようにする。
abstract class LocationPermissionGateway {
  /// 現在の権限状態を確認する（OSのダイアログは出ない。副作用なし）。
  Future<LocationPermissionState> status();

  /// 権限をリクエストする。[LocationPermissionState.denied] の状態から呼ぶと
  /// OSの許可ダイアログが表示されうる。[LocationPermissionState.permanentlyDenied]
  /// の状態から呼んだ場合はダイアログが出ず、即座に同じ状態が返る
  /// （呼び出し側は事前に [status] で判定し、permanentlyDenied なら
  /// [openAppSettings] へ誘導すること）。
  Future<LocationPermissionState> request();

  /// 端末のアプリ設定画面を開く（権限が「今後表示しない」の場合の唯一の導線）。
  /// 開けなかった場合は false を返す。
  Future<bool> openAppSettings();
}

/// `permission_handler` を使う本番実装（Android の `ACCESS_FINE_LOCATION`/
/// `ACCESS_COARSE_LOCATION` に対応する `Permission.locationWhenInUse` のみを扱う。
/// **`Permission.location`（背景位置を含みうる）は使わない** — plan.md §10・
/// Issue #142 受け入れ基準「`ACCESS_BACKGROUND_LOCATION` を要求していない」に対応する。
class PermissionHandlerLocationGateway implements LocationPermissionGateway {
  const PermissionHandlerLocationGateway();

  @override
  Future<LocationPermissionState> status() async =>
      _map(await ph.Permission.locationWhenInUse.status);

  @override
  Future<LocationPermissionState> request() async =>
      _map(await ph.Permission.locationWhenInUse.request());

  @override
  Future<bool> openAppSettings() => ph.openAppSettings();

  static LocationPermissionState _map(ph.PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return LocationPermissionState.granted;
    }
    if (status.isPermanentlyDenied) {
      return LocationPermissionState.permanentlyDenied;
    }
    return LocationPermissionState.denied;
  }
}

/// 通知権限（`POST_NOTIFICATIONS`。Android 13+）のベストエフォート要求。
///
/// 常駐通知が見えなくても記録自体は動く（`AndroidManifest.xml` のコメント・
/// Issue #142 提案内容2「`ACTIVITY_RECOGNITION` は無くても動く」と同じ「罰しない」
/// 方針）ため、位置情報権限のような状態管理（拒否/永久拒否の案内）はしない。
/// 結果を問わず呼びっぱなしにしてよい設計であり、失敗しても記録開始をブロックしない。
Future<void> requestNotificationPermissionBestEffort() async {
  try {
    await ph.Permission.notification.request();
  } catch (_) {
    // 通知権限が存在しない環境（API 32以下）や取得失敗はここで握りつぶす。
    // 記録開始をブロックしてはならない（本関数の責務はベストエフォートのみ）。
  }
}
