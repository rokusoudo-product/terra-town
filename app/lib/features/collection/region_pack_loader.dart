import 'dart:async';

import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../map/region_pack_asset.dart';

/// [CollectionScreen] が名所の総数（カテゴリ集計の分母）を得るための
/// 地域パック読み込み関数の型（T075）。
///
/// `MapScreen.resolveMbtilesPath`（`map_screen.dart`）と同じ「本番は既定実装、
/// テストはフェイクに差し替える」方式のテストフック。widget テストでは
/// [RegionPackConnection.forTesting] で組み立てた `RegionPack` を返す関数を渡し、
/// 実アセット・`path_provider` の実プラットフォーム実装に触れずに検証する。
typedef LoadRegionPack = Future<RegionPack> Function();

/// 既定実装: 同梱の `region_pack.sqlite`（`region_pack_asset.dart`）を読み取り
/// 専用で開き、[RegionPack] として読み込む。
///
/// ## `map_screen.dart` の接続とは別に、都度開いて閉じる（設計上の判断）
/// `MapScreen`（`_DisclosureAwareMapViewState`）は自分の `RegionPackConnection`
/// をウィジェットのライフサイクルに合わせて開閉している。図鑑タブは地図タブと
/// 独立して開閉されうる（`RootScaffold` がタブ切替のたびに新しい
/// `CollectionScreen` を作る）ため、その接続を共有することはできない
/// （map_screen.dart はこのIssueの変更禁止対象でもある）。
///
/// 地域パックは読み取り専用ファイルであり、複数の読み取り専用接続を同時に
/// 開いても競合しない（`RegionPackConnection` クラスdoc「書き込みを構造的に
/// 防ぐ方法」参照）。[RegionPackRepository.load] は読み込んだデータを
/// すべてメモリ上の Map/List にコピーする同期処理のため、読み込みが終わり
/// 次第すぐに接続を閉じてよい。
Future<RegionPack> defaultLoadRegionPack() async {
  final path = await defaultResolveRegionPackPath();
  final connection = RegionPackConnection.open(path);
  try {
    return RegionPackRepository.load(connection);
  } finally {
    unawaited(connection.close());
  }
}
