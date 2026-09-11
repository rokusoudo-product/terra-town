import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart' show hexIdToFeatureId;

/// 復元1回分の結果（tasks.md T060・Issue #102 受け入れ基準「復元したヘクス数と
/// 所要時間の記録」）。
class RestoreStats {
  const RestoreStats({required this.hexCount, required this.elapsedMs});

  /// 復元したヘクス数。
  final int hexCount;

  /// 復元にかかった時間〔ミリ秒〕（[repository.findAll] の読み出しから、
  /// 全ヘクスの [reveal] 呼び出しが完了するまでの合計）。
  final int elapsedMs;

  @override
  String toString() =>
      'RestoreStats(hexCount: $hexCount, elapsedMs: $elapsedMs)';
}

/// [repository] に保存済みの開示済みヘクスを [known] へ読み込み、[reveal] で
/// 地図の霧を解除する（tasks.md T060・Issue #102）。
///
/// ## 呼び出しどころ（アプリ再起動後・`setStyle` 後の両方をカバーする経路）
/// `map_screen.dart` の `MapView.onFogLayerReady` から呼ぶ。`onFogLayerReady` は
/// 起動時の初回ソース構築後に発火するだけでなく、（MVPでは実際には発生しないが
/// 経路として用意する）将来 `setStyle` が呼ばれ `onStyleLoadedCallback` が
/// 再度発火した場合にも同様に発火する（`map_view.dart` の
/// `_addRegionPackLayers` 参照）。同じ本関数を両方の入口から呼ぶことで、
/// 「復元経路を1つに保つ」（`fog_of_war_layer.dart` クラスdoc「開示状態の正は
/// 永続ストレージである」参照）という設計を実現する。
///
/// ## 順序が重要（advisor 指摘）
/// [known] への追加は**霧の解除（[reveal]）を待たずに全件終える**
/// （下記実装参照）。呼び出し側（`DisclosureCoordinator.start`）は、本関数が
/// 返した**後**に位置ストリームの購読を開始すること。順序を誤ると、まだ [known]
/// に登録されていない既知のヘクスへ実機の移動で再度到達した際に
/// `DisclosureService.recordPosition` が「新規開示」と誤認しうる
/// （`DisclosedHexRepository.save` は `insertOrIgnore` のため実際の上書きは
/// 起きないが、無駄な処理は避けるべき）。
///
/// ## 復元コストについて（Issue #102 受け入れ基準・判断の記録）
/// `maplibre_gl`（`maplibre_gl_platform_interface.dart` 330〜344行目）には
/// 複数の feature-state をまとめて設定するバッチ API が無く、`setFeatureState` は
/// 1件ずつしか呼べない。そのため [reveal] の呼び出し自体（＝ platform channel の
/// 往復）がヘクス数ぶん発生することは、既存 API の範囲では避けられない
/// （PR本文に判断として明記）。
///
/// 本関数はこれを完全には解消できないが、[chunkSize] 件ずつ [Future.wait] で
/// **並行に**投げることで、Dart 側の `await` を直列にする場合と比べて
/// 体感の待ち時間を短縮する（各呼び出しは異なる `featureId` に対する独立した
/// 操作であり、競合状態は無い）。無制限に並行投げるとプラットフォームチャンネルに
/// 未処理のメッセージが積み上がるため、[chunkSize]（既定500）で区切る。
Future<RestoreStats> restoreDisclosedHexes({
  required Repository<DisclosedHex, HexId> repository,
  required DisclosedHexSet known,
  required Future<void> Function(int featureId) reveal,
  int chunkSize = 500,
}) async {
  final stopwatch = Stopwatch()..start();

  final rows = await repository.findAll();
  for (final row in rows) {
    known.add(row.hexId);
  }

  for (var i = 0; i < rows.length; i += chunkSize) {
    final chunk = rows.skip(i).take(chunkSize);
    await Future.wait([
      for (final row in chunk) reveal(hexIdToFeatureId(row.hexId.value)),
    ]);
  }

  stopwatch.stop();
  final stats = RestoreStats(
    hexCount: rows.length,
    elapsedMs: stopwatch.elapsedMilliseconds,
  );
  _log(
    '開示済みヘクスの復元が完了しました: ヘクス数=${stats.hexCount} '
    '所要時間=${stats.elapsedMs}ms（chunkSize=$chunkSize）',
  );
  return stats;
}

void _log(String message) {
  developer.log(message, name: 'terra_town.disclosure_restore');
  debugPrint('[terra_town.disclosure_restore] $message');
}
