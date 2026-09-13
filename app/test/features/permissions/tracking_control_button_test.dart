import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town/design/app_theme.dart';
import 'package:terra_town/features/permissions/location_permission_gateway.dart';
import 'package:terra_town/features/permissions/tracking_control_button.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [LocationTrackingHostApi] のフェイク（`NativeLocationTrackingControl` はこの
/// クラスを `api:` として受け取れる。`native_position_provider_test.dart` の
/// `_FakeLocationPointsApi` と同じ「Pigeon 生成クラスをフェイクに差し替える」方式）。
class _FakeLocationTrackingHostApi extends LocationTrackingHostApi {
  TrackingStartOutcome startOutcome = TrackingStartOutcome.started;
  bool isRunning = false;
  int startCallCount = 0;
  int stopCallCount = 0;

  @override
  Future<TrackingStartResult> startTracking() async {
    startCallCount++;
    if (startOutcome == TrackingStartOutcome.started) {
      isRunning = true;
    }
    return TrackingStartResult(outcome: startOutcome);
  }

  @override
  Future<void> stopTracking() async {
    stopCallCount++;
    isRunning = false;
  }

  @override
  Future<TrackingStatus> getTrackingStatus() async {
    return TrackingStatus(
      isRunning: isRunning,
      sessionId: isRunning ? 'session-1' : null,
    );
  }
}

/// [LocationPermissionGateway] のフェイク。
class _FakePermissionGateway implements LocationPermissionGateway {
  _FakePermissionGateway(this._status);

  LocationPermissionState _status;

  /// [request] が返す値。未設定の場合は現在の [_status] をそのまま返す
  /// （「リクエストしても状態が変わらない」ケースを既定にする）。
  LocationPermissionState? requestResult;

  int statusCallCount = 0;
  int requestCallCount = 0;
  int openAppSettingsCallCount = 0;

  @override
  Future<LocationPermissionState> status() async {
    statusCallCount++;
    return _status;
  }

  @override
  Future<LocationPermissionState> request() async {
    requestCallCount++;
    _status = requestResult ?? _status;
    return _status;
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCallCount++;
    return true;
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: child),
  );
}

void main() {
  // Issue #142・T059 受け入れ基準:
  //   - release ビルドでも製品UIから記録の開始・停止ができる
  //   - 権限が無い状態で開始すると権限要求が出る。許可すれば記録が始まる
  //   - 拒否・永久拒否のそれぞれで適切な案内が出る（本ファイルがそのテスト）
  //   - ACCESS_BACKGROUND_LOCATION を要求していない
  //     （`_FakePermissionGateway` は `LocationPermissionGateway` 抽象だけを見ており、
  //     本番実装 `PermissionHandlerLocationGateway` が `Permission.locationWhenInUse`
  //     のみを使うことは実装コード自体で保証する。本ファイルではフローを検証する）

  testWidgets('許可済み・停止中: 「記録開始」ボタンが表示される', (tester) async {
    final hostApi = _FakeLocationTrackingHostApi();
    final gateway = _FakePermissionGateway(LocationPermissionState.granted);

    await tester.pumpWidget(
      _wrap(
        TrackingControlButton(
          control: NativeLocationTrackingControl(api: hostApi),
          permissionGateway: gateway,
          requestNotificationPermission: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('記録開始'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
  });

  testWidgets('許可済み: タップすると記録が開始され「記録中」に変わる', (tester) async {
    final hostApi = _FakeLocationTrackingHostApi();
    final gateway = _FakePermissionGateway(LocationPermissionState.granted);
    var notificationRequestCount = 0;

    await tester.pumpWidget(
      _wrap(
        TrackingControlButton(
          control: NativeLocationTrackingControl(api: hostApi),
          permissionGateway: gateway,
          requestNotificationPermission: () async {
            notificationRequestCount++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(hostApi.startCallCount, 1);
    expect(find.text('記録中'), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    // 通知権限はベストエフォートでリクエストする（結果は待たない）。
    expect(notificationRequestCount, 1);
  });

  testWidgets('稼働中: タップすると停止し「記録開始」に戻る', (tester) async {
    final hostApi = _FakeLocationTrackingHostApi()..isRunning = true;
    final gateway = _FakePermissionGateway(LocationPermissionState.granted);

    await tester.pumpWidget(
      _wrap(
        TrackingControlButton(
          control: NativeLocationTrackingControl(api: hostApi),
          permissionGateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('記録中'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(hostApi.stopCallCount, 1);
    expect(find.text('記録開始'), findsOneWidget);
  });

  testWidgets('権限未確認/拒否: タップで権限要求ダイアログ相当が呼ばれ、許可されれば記録が始まる',
      (tester) async {
    final hostApi = _FakeLocationTrackingHostApi();
    final gateway = _FakePermissionGateway(LocationPermissionState.denied)
      ..requestResult = LocationPermissionState.granted;

    await tester.pumpWidget(
      _wrap(
        TrackingControlButton(
          control: NativeLocationTrackingControl(api: hostApi),
          permissionGateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('権限が必要です'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(gateway.requestCallCount, 1);
    expect(hostApi.startCallCount, 1);
    expect(find.text('記録中'), findsOneWidget);
  });

  testWidgets('拒否されたまま: 「なぜ必要か」の案内と再リクエスト導線が出る（永久拒否ではない）',
      (tester) async {
    final hostApi = _FakeLocationTrackingHostApi();
    final gateway = _FakePermissionGateway(LocationPermissionState.denied)
      ..requestResult = LocationPermissionState.denied;

    await tester.pumpWidget(
      _wrap(
        TrackingControlButton(
          control: NativeLocationTrackingControl(api: hostApi),
          permissionGateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(gateway.requestCallCount, 1);
    expect(hostApi.startCallCount, 0, reason: '許可されなかった場合は記録を開始しない');
    expect(find.text('位置情報の権限が必要です'), findsOneWidget);
    expect(find.text('もう一度リクエストする'), findsOneWidget);
    expect(find.text('設定を開く'), findsNothing);
    // 記録が始まっていないので、ボタンの状態は「権限が必要です」のまま。
    expect(find.text('権限が必要です'), findsOneWidget);
  });

  testWidgets('永久拒否: OSに再リクエストせず設定画面への案内が出る', (tester) async {
    final hostApi = _FakeLocationTrackingHostApi();
    final gateway =
        _FakePermissionGateway(LocationPermissionState.permanentlyDenied);

    await tester.pumpWidget(
      _wrap(
        TrackingControlButton(
          control: NativeLocationTrackingControl(api: hostApi),
          permissionGateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // 永久拒否の場合、OSがもうダイアログを出さないため request() 自体を呼ばない。
    expect(gateway.requestCallCount, 0);
    expect(hostApi.startCallCount, 0);
    expect(find.text('位置情報の権限が必要です'), findsOneWidget);
    expect(find.text('設定を開く'), findsOneWidget);
    expect(find.text('もう一度リクエストする'), findsNothing);

    await tester.tap(find.text('設定を開く'));
    await tester.pumpAndSettle();
    expect(gateway.openAppSettingsCallCount, 1);
  });

  testWidgets('フォアグラウンド復帰時に権限・記録状態を再確認する', (tester) async {
    final hostApi = _FakeLocationTrackingHostApi();
    final gateway = _FakePermissionGateway(LocationPermissionState.denied);

    await tester.pumpWidget(
      _wrap(
        TrackingControlButton(
          control: NativeLocationTrackingControl(api: hostApi),
          permissionGateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final statusCallsAfterInit = gateway.statusCallCount;
    expect(find.text('権限が必要です'), findsOneWidget);

    // 端末の設定アプリで権限を許可してからアプリに戻ってきた状況を模す。
    gateway._status = LocationPermissionState.granted;
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(gateway.statusCallCount, greaterThan(statusCallsAfterInit));
    expect(find.text('記録開始'), findsOneWidget);
  });

  // Issue #149・T062: HUD（`walk_stats_hud.dart`）が「記録は停止中です」を
  // 表示できるように、記録中フラグを外部の ValueNotifier へ公開する。
  testWidgets('recordingNotifier に記録中フラグを反映する（HUD 用・Issue #149）',
      (tester) async {
    final hostApi = _FakeLocationTrackingHostApi();
    final gateway = _FakePermissionGateway(LocationPermissionState.granted);
    final recordingNotifier = ValueNotifier<bool>(false);
    addTearDown(recordingNotifier.dispose);

    await tester.pumpWidget(
      _wrap(
        TrackingControlButton(
          control: NativeLocationTrackingControl(api: hostApi),
          permissionGateway: gateway,
          requestNotificationPermission: () async {},
          recordingNotifier: recordingNotifier,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(recordingNotifier.value, isFalse);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(recordingNotifier.value, isTrue, reason: '記録開始で true になる');

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(recordingNotifier.value, isFalse, reason: '記録停止で false に戻る');
  });
}
