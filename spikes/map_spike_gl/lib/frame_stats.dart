// SchedulerBinding.instance.addTimingsCallback を使った簡易フレーム計測。
// research.md §4 / plan.md §8 の fps・ジャンクフレーム数の検証用。
//
// 計測方法の注意（正直な限界の明記）:
// - ジャンクの判定閾値は 16.67ms（60Hz想定の1フレーム予算）を単純に超えたかどうかで判定する。
//   実機のリフレッシュレート（90Hz/120Hz等）を動的に取得して閾値を可変にする、といった
//   厳密な実装はしていない。あくまで「動くか動かないか」の一次スクリーニング用。
// - fps は「収集期間中に観測されたフレーム数 / 収集期間の実時間（秒）」の単純平均。
//   フレームごとの totalSpan の平均から逆算する方式ではない。

import 'dart:developer' as developer;
import 'package:flutter/scheduler.dart';

class FrameStatsResult {
  final int frameCount;
  final int jankFrameCount;
  final double elapsedMs;
  final double fps;
  final double avgFrameMs;
  final double maxFrameMs;

  const FrameStatsResult({
    required this.frameCount,
    required this.jankFrameCount,
    required this.elapsedMs,
    required this.fps,
    required this.avgFrameMs,
    required this.maxFrameMs,
  });

  static const double jankThresholdMs = 16.67;

  String get summary =>
      'frames=$frameCount jank=$jankFrameCount '
      '(${frameCount == 0 ? 0 : (jankFrameCount * 100 / frameCount).toStringAsFixed(1)}%) '
      'fps=${fps.toStringAsFixed(1)} avgFrame=${avgFrameMs.toStringAsFixed(1)}ms '
      'maxFrame=${maxFrameMs.toStringAsFixed(1)}ms';
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
        fps: 0,
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
    final double fps = _timings.length / (elapsedMs / 1000.0);

    final result = FrameStatsResult(
      frameCount: _timings.length,
      jankFrameCount: jank,
      elapsedMs: elapsedMs,
      fps: fps,
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
