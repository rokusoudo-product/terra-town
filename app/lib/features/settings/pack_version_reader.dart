import 'dart:async';

import 'package:terra_town_location/terra_town_location.dart';

import '../../map/region_pack_asset.dart';

/// セーブデータのエクスポート（Issue #180・T105）のメタデータ `pack_version` を
/// 読み出す関数の型。`MapScreen.resolveMbtilesPath`・`LoadRegionPack`
/// （`region_pack_loader.dart`）と同じ「本番は既定実装、テストはフェイクに
/// 差し替える」方式のテストフック。
typedef ResolvePackVersion = Future<String> Function();

/// 地域パックが無い・壊れている等で `pack_version` を読み出せない場合の既定値。
const String unknownPackVersion = 'unknown';

/// 既定実装: 同梱の `region_pack.sqlite` の `pack_meta` テーブルから
/// `pack_version` の1行だけを読む。
///
/// [defaultLoadRegionPack]（`region_pack_loader.dart`）は `hex_terrain` 等
/// 全テーブルをメモリへ読み込む重い処理のため、ここでは使わない
/// （`RegionPackRepository._loadVersion` と同じクエリを直接発行するだけに留める）。
///
/// 地域パックが同梱されていない・壊れている場合でも、書き出し操作自体を
/// 止めたくないため、例外を投げず [unknownPackVersion] を返す。
Future<String> defaultResolvePackVersion() async {
  try {
    final path = await defaultResolveRegionPackPath();
    final connection = RegionPackConnection.open(path);
    try {
      final rows = connection.rawSelect(
        "SELECT value FROM pack_meta WHERE key = 'pack_version'",
      );
      if (rows.isEmpty) return unknownPackVersion;
      final value = rows.first['value'];
      return value is String ? value : unknownPackVersion;
    } finally {
      unawaited(connection.close());
    }
  } catch (_) {
    return unknownPackVersion;
  }
}
