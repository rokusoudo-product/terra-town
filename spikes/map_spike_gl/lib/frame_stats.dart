// SchedulerBinding.instance.addTimingsCallback を使った簡易フレーム計測。
// research.md §4 / plan.md §8 の fps・ジャンクフレーム数の検証用。
//
// 計測方法の注意（正直な限界の明記）:
// - ジャンクの判定閾値は 16.67ms（60Hz想定の1フレーム予算）を単純に超えたかどうかで判定する。
//   実機のリフレッシュレート（90Hz/120Hz等）を動的に取得して閾値を可変にする、といった
//   厳密な実装はしていない。あくまで「動くか動かないか」の一次スクリーニング用。
//
// 【2026-09-09 修正・Issue #24 実機セッションで発覚した不具合への対応】
// 従来の fps は「収集期間中に観測されたフレーム数 / 収集期間の実時間（秒）」の単純平均
// （`naiveFps`。本ファイルに残してある）だった。この定義は「手動パン・ズームfps計測」
// （代表が開始→操作→停止の順にボタンを押す方式）では破綻する。SchedulerBinding は
// 実際に描画が起きたフレームしかコールバックを呼ばないため、指を止めている間はフレームが
// 1枚も来ない。したがって「収集期間の実時間」の中に無操作区間が混ざると、その区間が
// まるごと「フレームが生成されなかった=遅い」として fps を押し下げてしまい、
// 「描画が遅い」のか「単に操作していなかった」のかを区別できなくなる
// （実測例: 22.0秒間でframes=716・avgFrame=11.5ms・jank率7.1%なのに naiveFps は32.5にしかならない。
// avgFrameから逆算すると実際は約87fps相当で動いており、716×11.5ms≒8.2秒分しか
// 実際には描画されておらず、残り約14秒は無操作だったと読める）。
//
// 対策として、フレームの発生間隔（`FramePhase.vsyncStart` のタイムスタンプの差）を見て、
// 間隔が `activeGapThresholdMs` 以下＝「連続して描画が起きていた（操作中）」区間だけを
// 積算し、その区間の時間で割った `activeFps` を判定用の指標として追加した。
// 間隔がそれを超える箇所は「無操作（アイドル）」区間とみなし、`activeFps` の分母・分子
// いずれからも除外する。`naiveFps` は「操作していない時間も含む参考値」として残し、
// 判定には使わない（画面・ログ双方で `activeFps` が判定用、`naiveFps` が参考値であることを
// 明示する）。
// - `activeGapThresholdMs`（既定200ms）は「60fpsの1フレーム予算16.67msの10倍以上」かつ
//   「人がパン・ズーム操作を数百ms止めた」とは考えにくい程度の値として選んだ経験的な閾値。
//   実機のタッチ操作の連続性を厳密にモデル化したものではない。
// - フレームが0〜1枚しか無い場合は区間（gap）自体が存在しないため `activeFps` は
//   算出不能とし 0 を返す（`naiveFps` も参考として確認できる）。

import 'dart:developer' as developer;
import 'dart:ui' show FramePhase;
import 'package:flutter/scheduler.dart';

class FrameStatsResult {
  final int frameCount;
  final int jankFrameCount;
  final double elapsedMs;

  /// 判定に使う指標。実際に描画が連続して発生していた区間（アイドル区間を除く）だけを
  /// 母数にした fps。手動パン・ズームfps計測の PASS/FAIL 判定はこちらを使う。
  final double activeFps;

  /// 参考値。「収集期間の実時間 / 総フレーム数」の従来どおりの単純平均で、
  /// 操作していない時間（フレームが1枚も来ない区間）も分母に含む。判定には使わない。
  final double naiveFps;

  /// activeFps の算出に使った「連続描画中」とみなした時間の合計（ms）。
  final double activeElapsedMs;

  /// アイドル（無操作）とみなして activeFps の計算から除外したフレーム間隔の本数。
  final int idleGapCount;

  final double avgFrameMs;
  final double maxFrameMs;

  const FrameStatsResult({
    required this.frameCount,
    required this.jankFrameCount,
    required this.elapsedMs,
    required this.activeFps,
    required this.naiveFps,
    required this.activeElapsedMs,
    required this.idleGapCount,
    required this.avgFrameMs,
    required this.maxFrameMs,
  });

  static const double jankThresholdMs = 16.67;

  /// フレーム間隔がこれを超えたら「無操作（アイドル）」とみなし activeFps の計算から除外する。
  /// 詳細は本ファイル冒頭のコメント参照。
  static const double activeGapThresholdMs = 200.0;

  String get summary =>
      'frames=$frameCount jank=$jankFrameCount '
      '(${frameCount == 0 ? 0 : (jankFrameCount * 100 / frameCount).toStringAsFixed(1)}%) '
      'activeFps=${activeFps.toStringAsFixed(1)}(判定用) '
      'naiveFps=${naiveFps.toStringAsFixed(1)}(参考・無操作区間含む) '
      'avgFrame=${avgFrameMs.toStringAsFixed(1)}ms maxFrame=${maxFrameMs.toStringAsFixed(1)}ms '
      'active=${activeElapsedMs.toStringAsFixed(0)}ms/${elapsedMs.toStringAsFixed(0)}ms(idleGap=$idleGapCount)';
}

/// 収集区間を明示的に開始・終了できるフレーム計測器。
class FrameStatsCollector {
  final List<FrameTiming> _timings = [];
  void Function(List<FrameTiming>)? _callback;
  DateTime? _startedAt;
  DateTime? _stoppedAt;

  bool get isCollecting => _callback != null;

  void start() {
    if (_callback != null) return;
    _timings.clear();
    _startedAt = DateTime.now();
    _stoppedAt = null;
    _callback = (timings) => _timings.addAll(timings);
    SchedulerBinding.instance.addTimingsCallback(_callback!);
    developer.log('FrameStatsCollector: started', name: 'map_spike_gl');
  }

  FrameStatsResult stop() {
    _stoppedAt = DateTime.now();
    if (_callback != null) {
      SchedulerBinding.instance.removeTimingsCallback(_callback!);
      _callback = null;
    }
    final double elapsedMs = (_startedAt == null || _stoppedAt == null)
        ? 0
        : _stoppedAt!.difference(_startedAt!).inMicroseconds / 1000.0;

    if (_timings.isEmpty || elapsedMs <= 0) {
      final result = FrameStatsResult(
        frameCount: _timings.length,
        jankFrameCount: 0,
        elapsedMs: elapsedMs,
        activeFps: 0,
        naiveFps: 0,
        activeElapsedMs: 0,
        idleGapCount: 0,
        avgFrameMs: 0,
        maxFrameMs: 0,
      );
      developer.log('FrameStatsCollector: stopped (${result.summary})',
          name: 'map_spike_gl');
      return result;
    }

    final List<double> frameMs = _timings
        .map((t) => t.totalSpan.inMicroseconds / 1000.0)
        .toList(growable: false);
    final int jank =
        frameMs.where((ms) => ms > FrameStatsResult.jankThresholdMs).length;
    final double avg = frameMs.reduce((a, b) => a + b) / frameMs.length;
    final double maxMs = frameMs.reduce((a, b) => a > b ? a : b);
    // 参考値。従来どおりの単純平均（無操作区間も分母に含む）。判定には使わない
    // （本ファイル冒頭のコメント参照）。
    final double naiveFps = _timings.length / (elapsedMs / 1000.0);

    // 判定用の activeFps: フレームの発生間隔（vsyncStart の差）を見て、
    // activeGapThresholdMs 以下の「連続して描画が起きていた」区間だけを積算する。
    final List<int> startUs = _timings
        .map((t) => t.timestampInMicroseconds(FramePhase.vsyncStart))
        .toList(growable: false);
    double activeMs = 0;
    int activeGapCount = 0;
    int idleGapCount = 0;
    for (int i = 1; i < startUs.length; i++) {
      final double gapMs = (startUs[i] - startUs[i - 1]) / 1000.0;
      if (gapMs <= FrameStatsResult.activeGapThresholdMs) {
        activeMs += gapMs;
        activeGapCount++;
      } else {
        idleGapCount++;
      }
    }
    // フレームが1枚しかない（間隔が0本）場合は activeFps を算出できないため0とする。
    final double activeFps =
        activeMs > 0 ? activeGapCount / (activeMs / 1000.0) : 0;

    final result = FrameStatsResult(
      frameCount: _timings.length,
      jankFrameCount: jank,
      elapsedMs: elapsedMs,
      activeFps: activeFps,
      naiveFps: naiveFps,
      activeElapsedMs: activeMs,
      idleGapCount: idleGapCount,
      avgFrameMs: avg,
      maxFrameMs: maxMs,
    );
    developer.log('FrameStatsCollector: stopped (${result.summary})',
        name: 'map_spike_gl');
    return result;
  }
}

/// ミリ秒のリストから min/median/max/avg を計算する（更新レイテンシ計測A用）。
class DurationStats {
  final double minMs;
  final double medianMs;
  final double maxMs;
  final double avgMs;
  final int sampleCount;

  const DurationStats({
    required this.minMs,
    required this.medianMs,
    required this.maxMs,
    required this.avgMs,
    required this.sampleCount,
  });

  factory DurationStats.fromMs(List<double> valuesMs) {
    if (valuesMs.isEmpty) {
      return const DurationStats(
          minMs: 0, medianMs: 0, maxMs: 0, avgMs: 0, sampleCount: 0);
    }
    final sorted = [...valuesMs]..sort();
    final double median = sorted.length.isOdd
        ? sorted[sorted.length ~/ 2]
        : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2.0;
    final double avg = sorted.reduce((a, b) => a + b) / sorted.length;
    return DurationStats(
      minMs: sorted.first,
      medianMs: median,
      maxMs: sorted.last,
      avgMs: avg,
      sampleCount: sorted.length,
    );
  }

  String get summary =>
      'min=${minMs.toStringAsFixed(1)}ms median=${medianMs.toStringAsFixed(1)}ms '
      'max=${maxMs.toStringAsFixed(1)}ms avg=${avgMs.toStringAsFixed(1)}ms (n=$sampleCount)';
}
