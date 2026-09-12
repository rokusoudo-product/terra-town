import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// 地形産出（受動・時間ベース）の二重計上防止ロジック本体（Issue #138・T068）。
///
/// [TerrainYieldLedgerStore]（`packages/location`）への永続化と、
/// `computeTerrainYieldAccrual`（`packages/core`）による決定論的な計算とを
/// つなぎ、「同一セッション内の連続する2点の差分だけを積算し、セッションを
/// またがない」「二重計上を防ぐ」というルールを実現する。
///
/// ## ウォーターマークの方式（Issue #138 本文の設計要件）
/// ウォーターマークは「最後に計上した位置記録の行id」（[LocationPointRecord.rowId]）。
/// **セッションIDと単調時刻の組をウォーターマークにしない**（そのセッションの行が
/// 無ければ永久に計上が止まる危険があるため）。
///
/// [NativePositionProvider] は起動のたびに記録の先頭（`sinceRowId = 0`）から
/// 全件を再生する。本クラスはこの全件再生を前提に、次の方法で
/// 「ウォーターマークの行を、再起動後の最初の区間の始点（直前の点＝prev）として
/// 復元する」を実現する:
///
/// - [accrue] は呼ばれるたびに、渡された [LocationPointRecord] が現在の
///   ウォーターマーク（[watermarkRowId]）より新しい行かどうかを確認する。
/// - 新しくなければ（`rowId <= watermarkRowId`）**計上は一切行わない**
///   （ウォーターマークより新しい行が無ければ何も起きない・受け入れ基準(c)）。
///   ただし [_previous] は必ず今回の記録に更新する。これにより、再生が進んで
///   `rowId == watermarkRowId` の行に到達した瞬間、[_previous] がその行の
///   [GeoPosition] になり、**次の（`rowId > watermarkRowId` の）行が来たときに
///   正しい区間（直前の計上済みの点 → 新しい点）として扱われる**
///   （settings に別途セッションID・単調時刻を保存する必要が無い）。
/// - 新しければ、[_previous] と同一 [GeoPosition.trackingSessionId] の場合のみ
///   経過時間（単調時計の差分）を計算し（異なるセッション・[_previous] が無い
///   場合は経過時間0として扱う＝セッションをまたいで積算しない）、
///   `computeTerrainYieldAccrual` へ渡す。結果を [ledger.applyAccrual] で
///   **1トランザクション**として永続化してからウォーターマーク・端数の
///   内部状態を更新する。
///
/// ## 失敗時の挙動（受け入れ基準(d)）
/// [ledger.applyAccrual] が例外を投げた場合、その例外は [accrue] の呼び出し元
/// （`TerrainYieldPipeline`）へそのまま伝播する。**[_previous]・[watermarkRowId]・
/// [remainderMicros] のいずれも更新されない**（`_previous = record;` は
/// 正常終了した場合にのみ到達するコードパスにある）。そのため次に [accrue] が
/// 呼ばれたときも古い [_previous] が使われ、失敗した区間・その後の区間を
/// あわせて正しく計上し直せる（失われない）。
class TerrainYieldAccrualCoordinator {
  TerrainYieldAccrualCoordinator({required this.ledger});

  final TerrainYieldLedgerStore ledger;

  int _watermarkRowId = 0;
  Map<Resource, int> _remainderMicros = const {};
  LocationPointRecord? _previous;
  bool _initialized = false;

  /// 現在のウォーターマーク（最後に計上した行id）。デバッグ表示用。
  int get watermarkRowId => _watermarkRowId;

  /// 現在の端数〔マイクロ秒〕。デバッグ表示用。
  Map<Resource, int> get remainderMicros => Map.unmodifiable(_remainderMicros);

  /// [ledger] から直近の状態（ウォーターマーク・端数）を読み込む。
  /// [accrue] を呼ぶ前に必ず1度呼ぶこと（`TerrainYieldPipeline.start` から呼ぶ）。
  Future<void> initialize() async {
    final snapshot = await ledger.readSnapshot();
    _watermarkRowId = snapshot.watermarkRowId;
    _remainderMicros = Map.of(snapshot.remainderMicros);
    _initialized = true;
  }

  /// [record] を1件処理する。[hexCountByTerrain] は**この記録の位置がまだ
  /// 開示されていない時点**の、開示済みヘクスの地形分類ごとの件数
  /// （区間開始時点のスナップショット。呼び出し側 `TerrainYieldPipeline` が
  /// この順序を保証する）。
  Future<void> accrue(
    LocationPointRecord record,
    Map<TerrainType, int> hexCountByTerrain,
  ) async {
    assert(_initialized, 'initialize() を先に呼ぶこと');

    if (record.rowId > _watermarkRowId) {
      final previous = _previous;
      final sameSession = previous != null &&
          previous.position.trackingSessionId == record.position.trackingSessionId;

      var elapsedMicroseconds = 0;
      if (sameSession) {
        elapsedMicroseconds = record.position.timestamp
            .difference(previous.position.timestamp)
            .inMicroseconds;
        if (elapsedMicroseconds < 0) {
          // 単調時計が前提のため通常発生しないが、防御的に0へクランプする
          // （端末・センサーの異常値でマイナスの産出が起きないようにするため）。
          _log(
            '経過時間が負になりました（単調時計の前提が崩れている可能性）。'
            '0として扱います: rowId=${record.rowId} elapsed=$elapsedMicroseconds',
          );
          elapsedMicroseconds = 0;
        }
      }

      final accrual = computeTerrainYieldAccrual(
        hexCountByTerrain: hexCountByTerrain,
        elapsedMicroseconds: elapsedMicroseconds,
        previousRemainderMicros: _remainderMicros,
      );

      // 資材の加算・端数・ウォーターマークの更新を1トランザクションで書く
      // （ledger 側の保証。ここで例外が投げられた場合、以降の内部状態の
      // 更新〔_remainderMicros・_watermarkRowId・_previous〕は一切行わない）。
      await ledger.applyAccrual(
        grantedAmounts: accrual.granted,
        remainderMicros: accrual.remainderMicros,
        watermarkRowId: record.rowId,
      );

      _remainderMicros = accrual.remainderMicros;
      _watermarkRowId = record.rowId;
    }

    _previous = record;
  }

  void _log(String message) {
    developer.log(message, name: 'terra_town.terrain_yield_accrual');
    debugPrint('[terra_town.terrain_yield_accrual] $message');
  }
}
