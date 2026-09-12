import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// 開放ポイント（歩行距離換算・`docs/opening_points.md` §2.2）の二重計上防止
/// ロジック本体（Issue #143・T063）。
///
/// [OpeningPointLedgerStore]（`packages/location`）への永続化と、
/// `computeOpeningPointAccrual`（`packages/core`）による決定論的な計算とを
/// つなぐ役割は `TerrainYieldAccrualCoordinator`（Issue #138）と同じだが、
/// 開放ポイントは `RewardPolicy.classify` が要求する**移動窓**（既定120秒。
/// [SpeedFilter.smoothingWindow]・`RewardPolicy.stepWindow`）を使った平滑化済みの
/// 倍率が必要なため、直前の1点だけでなく直近の窓ぶんの [GeoPosition] を
/// [_window] に保持する点が異なる。
///
/// ## なぜ窓（直近数点の履歴）を持つ必要があるか
/// `RewardPolicy.classify` は速度超過（[SpeedFilter]）・歩数不一致のどちらも
/// **移動平均**（時間窓）で判定する（`reward_policy.dart` クラスdoc「歩数突合の
/// 設計」参照）。区間ごとに正しい倍率を得るには、その区間だけでなく直近
/// [_maxWindowDuration] 分の [GeoPosition] を含めて `classify` を呼ぶ必要がある
/// （1区間〔2点〕だけを渡すと平滑化が効かず、常に生の値で判定してしまう）。
///
/// 本クラスは新しい位置が届くたびに、既存の [_window] と新しい位置を合成した
/// **候補の窓**を作り、直近 [_maxWindowDuration] を超える古い点を先頭から
/// 除いたうえで `rewardPolicy.classify(候補の窓)` を呼び、**その結果の最後の
/// 区間**（＝今回追加した点の区間）の [RewardSegment.multiplier]・
/// [RewardSegment.distanceMeters] だけを開放ポイントの計算に使う。実際に
/// [_window] を候補で置き換える（コミットする）のは [ledger.applyAccrual] が
/// 成功した後だけである（クラスdoc「失敗時の挙動」参照）。窓を
/// [_maxWindowDuration] 程度に制限するのは、位置ストリーム全体を無制限に
/// 保持すると `classify` の呼び出しコストがセッション長に比例して増え続けて
/// しまうため（[SpeedFilter]・歩数ウィンドウ自身も同じ時間窓しか見ないため、
/// これより長く保持しても判定結果は変わらない）。
///
/// ## ウォーターマークの方式（`TerrainYieldAccrualCoordinator` と同じ設計）
/// ウォーターマークは「最後に計上した位置記録の行id」
/// （[LocationPointRecord.rowId]）。[NativePositionProvider] は起動のたびに
/// 記録の先頭から全件を再生するため、[accrue] は
/// `record.rowId <= watermarkRowId`（既に計上済み・ウォーターマークそのもの）の
/// 行については**計上を一切行わない**が、[_window] には追加し続ける
/// （再起動直後の全件再生でウォーターマーク直前の窓を正しく復元するため）。
/// `record.rowId > watermarkRowId` になった時点から、窓に基づく計上を再開する。
///
/// ## セッションをまたいで距離を積算しない
/// 新しい位置の [GeoPosition.trackingSessionId] が [_window] の最後の点と異なる
/// 場合、候補の窓は新しい位置だけから始める（`RewardPolicy.classify` 自体も
/// `splitByTrackingSession` でセッションをまたぐ区間を作らないため二重の
/// 安全策だが、[_window] を素直にセッション単位に保つことで窓の意味が
/// 分かりやすくなる）。
///
/// ## 失敗時の挙動（`TerrainYieldAccrualCoordinator` と同じ方針）
/// [ledger.applyAccrual] が例外を投げた場合、その例外は [accrue] の呼び出し元
/// （`TerrainYieldPipeline`）へそのまま伝播する。**内部状態
/// （[_window]・[_remainderMillimeters]・[_points]・[_watermarkRowId]・
/// 直近の診断用フィールド）のいずれも更新されない**（更新は正常終了した場合に
/// のみ到達するコードパスにある。`TerrainYieldAccrualCoordinator` クラスdoc
/// 「失敗時の挙動」と同じ設計）。**[_window] を候補窓で先に書き換えてしまうと、
/// 失敗した区間の終点がそのまま「直前の点」として残り、次回のリトライ時に
/// 失敗した区間そのものが計算対象から抜け落ちてしまう**（区間 A→B の計上に
/// 失敗したのに [_window] の末尾が B になっていると、次に C が来たとき
/// B→C の区間しか見えず、A→B 分の距離が失われる）。これを避けるため、
/// 候補窓の構築は同期的な純粋計算として行い、[_window] への反映は
/// [ledger.applyAccrual] の成功後にのみ行う。
///
/// ## 歩数判定オプトアウト設定（Issue #135）との配線
/// 本 Issue（#143）は「Issue #126（`RewardPolicy` の付与倍率）・Issue #135
/// （歩数判定オプトアウト）が実際に効く最初の実装」と位置づけられている
/// （Issue #143 本文）。地形産出（Issue #138）は時間ベースで `RewardPolicy` を
/// 一切使わないため配線の対象にならなかったが、本クラスは `RewardPolicy` を
/// 直接使うため、[rewardSettings] を渡すことで設定を反映できるようにした。
///
/// [rewardSettings] を渡した場合、[initialize] で
/// `rewardSettings.isStepCheckDisabled()` を1回読み、
/// `rewardPolicyFor(stepCheckDisabled: ...)`（`packages/location`）で
/// [rewardPolicy] を組み立て直す。**設定は起動時に1回だけ読み、以後
/// [accrue] のたびには読み直さない**（設定タブでスイッチを変更した場合、
/// 反映されるのは次回アプリ起動から。MVPでの割り切りとして明記する）。
/// [rewardPolicy] を明示的に渡した場合（主にテスト用途）は [rewardSettings] より
/// 優先する。どちらも渡さない場合は既定の `RewardPolicy()`
/// （`useStepCheck: true`）のまま。
class OpeningPointAccrualCoordinator {
  OpeningPointAccrualCoordinator({
    required this.ledger,
    RewardPolicy? rewardPolicy,
    this.rewardSettings,
    this.cap = openingPointStockCap,
  })  : _explicitRewardPolicy = rewardPolicy,
        rewardPolicy = rewardPolicy ?? RewardPolicy(),
        _maxWindowDuration = _computeMaxWindowDuration(rewardPolicy ?? RewardPolicy());

  final OpeningPointLedgerStore ledger;

  /// 歩数判定オプトアウト設定（Issue #135）の読み出し元。渡された場合、
  /// [initialize] で [rewardPolicy] へ反映する（クラスdoc「歩数判定オプトアウト
  /// 設定との配線」参照）。
  final RewardSettingsStore? rewardSettings;

  /// コンストラクタで明示的に渡された [RewardPolicy]（主にテスト用途）。
  /// 非nullの場合、[rewardSettings] より優先し [initialize] での再構築を行わない。
  final RewardPolicy? _explicitRewardPolicy;

  /// 実際の判定に使う [RewardPolicy]。[rewardSettings] が渡されていれば
  /// [initialize] 完了後に設定を反映した値へ差し替わる。
  RewardPolicy rewardPolicy;

  /// 開放ポイントのストック上限（既定 [openingPointStockCap]）。テストで
  /// 上限到達を再現しやすくするため差し替え可能にしてある。
  final int cap;

  Duration _maxWindowDuration;

  int _watermarkRowId = 0;
  int _remainderMillimeters = 0;
  int _points = 0;
  List<GeoPosition> _window = const [];
  bool _initialized = false;

  double? _lastSegmentDistanceMeters;
  double? _lastAppliedMultiplier;
  RewardSegmentReason? _lastReason;

  /// 現在の開放ポイント所持数。デバッグ表示用。
  int get points => _points;

  /// 現在の端数〔ミリメートル〕。デバッグ表示用。
  int get remainderMillimeters => _remainderMillimeters;

  /// 現在のウォーターマーク（最後に計上した行id）。デバッグ表示用。
  int get watermarkRowId => _watermarkRowId;

  /// 直近で計上に使われた区間の移動距離〔m〕（未計上ならnull）。デバッグ表示用。
  double? get lastSegmentDistanceMeters => _lastSegmentDistanceMeters;

  /// 直近で計上に使われた区間の付与倍率（未計上ならnull）。デバッグ表示用。
  double? get lastAppliedMultiplier => _lastAppliedMultiplier;

  /// 直近の区間の [RewardSegmentReason]（未計上ならnull）。デバッグ表示用。
  RewardSegmentReason? get lastReason => _lastReason;

  /// [ledger] から直近の状態（ウォーターマーク・端数・所持ポイント数）を読み込み、
  /// [rewardSettings] が渡されていれば歩数判定オプトアウト設定を [rewardPolicy] へ
  /// 反映する（クラスdoc「歩数判定オプトアウト設定との配線」参照）。
  /// [accrue] を呼ぶ前に必ず1度呼ぶこと（`TerrainYieldPipeline.start` から呼ぶ）。
  Future<void> initialize() async {
    final snapshot = await ledger.readSnapshot();
    _watermarkRowId = snapshot.watermarkRowId;
    _remainderMillimeters = snapshot.remainderMillimeters;
    _points = snapshot.points;

    final settings = rewardSettings;
    if (_explicitRewardPolicy == null && settings != null) {
      final disabled = await settings.isStepCheckDisabled();
      rewardPolicy = rewardPolicyFor(stepCheckDisabled: disabled);
      _maxWindowDuration = _computeMaxWindowDuration(rewardPolicy);
    }

    _initialized = true;
  }

  /// [record] を1件処理する。
  Future<void> accrue(LocationPointRecord record) async {
    assert(_initialized, 'initialize() を先に呼ぶこと');

    final candidateWindow = _buildCandidateWindow(record.position);

    if (record.rowId <= _watermarkRowId) {
      // 既に計上済み（起動時の全件再生）。窓の文脈だけ復元し、書き込みは行わない
      // （クラスdoc「ウォーターマークの方式」参照）。ここには失敗しうる非同期処理が
      // 無いため、候補窓をそのまま確定してよい。
      _window = candidateWindow;
      return;
    }

    var grantedPoints = 0;
    var newRemainderMillimeters = _remainderMillimeters;
    double? segmentDistanceMeters;
    double? segmentMultiplier;
    RewardSegmentReason? segmentReason;

    if (candidateWindow.length >= 2) {
      final segments = rewardPolicy.classify(candidateWindow);
      // candidateWindow は必ず同一セッションのみを含むため（クラスdoc「セッションを
      // またいで距離を積算しない」参照）、classify は candidateWindow.length - 1 件の
      // 区間を返す。最後の区間が「今回追加した点」に対応する。
      final segment = segments.last;
      segmentDistanceMeters = segment.distanceMeters;
      segmentMultiplier = segment.multiplier;
      segmentReason = segment.reason;

      final accrual = computeOpeningPointAccrual(
        distanceMeters: segment.distanceMeters,
        rewardMultiplier: segment.multiplier,
        currentPoints: _points,
        previousRemainderMillimeters: _remainderMillimeters,
        cap: cap,
      );
      grantedPoints = accrual.grantedPoints;
      newRemainderMillimeters = accrual.remainderMillimeters;
    }

    // ポイントの加算・端数・ウォーターマークの更新を1トランザクションで書く
    // （ledger 側の保証）。ここで例外が投げられた場合、以降の内部状態の更新
    // （[_window] のコミットを含む）は一切行わない（クラスdoc「失敗時の挙動」参照）。
    await ledger.applyAccrual(
      grantedPoints: grantedPoints,
      remainderMillimeters: newRemainderMillimeters,
      watermarkRowId: record.rowId,
    );

    // ここに到達するのは applyAccrual が成功した場合のみ。
    _window = candidateWindow;
    _remainderMillimeters = newRemainderMillimeters;
    _points += grantedPoints;
    _watermarkRowId = record.rowId;
    if (segmentDistanceMeters != null) {
      _lastSegmentDistanceMeters = segmentDistanceMeters;
      _lastAppliedMultiplier = segmentMultiplier;
      _lastReason = segmentReason;
    }
  }

  /// 現在の [_window] と [position] から、[_maxWindowDuration] 以内に
  /// 切り詰めた候補の窓を作る（[_window] 自体は変更しない・純粋な計算）。
  /// セッションが変わっていれば [position] だけから始める
  /// （クラスdoc「セッションをまたいで距離を積算しない」参照）。
  List<GeoPosition> _buildCandidateWindow(GeoPosition position) {
    final sameSession =
        _window.isNotEmpty && _window.last.trackingSessionId == position.trackingSessionId;
    final base = sameSession ? _window : const <GeoPosition>[];
    final candidate = [...base, position];
    return _trimmed(candidate);
  }

  /// [window] の末尾から見て [_maxWindowDuration] を超えて古い点を先頭から除く
  /// （少なくとも2点は残す。クラスdoc「なぜ窓を持つ必要があるか」参照）。
  List<GeoPosition> _trimmed(List<GeoPosition> window) {
    if (window.length <= 2) return window;
    final latestTimestamp = window.last.timestamp;
    var start = 0;
    while (window.length - start > 2 &&
        latestTimestamp.difference(window[start].timestamp) > _maxWindowDuration) {
      start++;
    }
    return start == 0 ? window : window.sublist(start);
  }
}

/// [policy] が内部で使う2つの時間窓（速度平滑化・歩数突合）のうち長い方を返す。
/// [OpeningPointAccrualCoordinator] が保持すべき履歴の長さを決めるために使う。
Duration _computeMaxWindowDuration(RewardPolicy policy) {
  final speedWindow = policy.speedFilter.smoothingWindow;
  final stepWindow = policy.stepWindow;
  return speedWindow > stepWindow ? speedWindow : stepWindow;
}
