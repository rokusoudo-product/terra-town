import 'package:terra_town_location/terra_town_location.dart';

/// 同梱地域パック（`region_pack.sqlite`）のアセットキー・解決関数（Issue #105・#137）。
///
/// `app/pubspec.yaml` の `flutter.assets`（`assets/pack/`）で宣言済み
/// （`map_screen.dart` の `MapScreen.mbtilesAssetKey` と対）。
///
/// [resolveBundledMbtilesPath] は名前に反して「Flutter アセットバンドルの
/// 読み取り専用ファイルを、書き込み可能な実ファイルパスへ一度だけコピーする」
/// という汎用処理である（`mbtiles_asset.dart` の docstring 参照。MBTiles 専用の
/// ロジックはその後段の `mbtiles://` URL 組み立てのほうにあり、コピー処理自体は
/// ファイル形式に依存しない）。`RegionPackConnection.open` も `sqlite3` の
/// 読み取り専用オープンに実ファイルシステム上のパスを要求するため、同じ関数を
/// そのまま再利用する。
///
/// 【1箇所に集約した理由（Issue #137）】以前は `FogOfWarDebugPanel` が独自に
/// 定義していたが、`map_screen.dart`（本番の地図画面）も同じ地域パックを
/// 読み込む必要が生じた（Issue #137・fog of war の実データ配線）ため、
/// 二重定義を避けてここへ集約した。
const String regionPackAssetKey = 'assets/pack/region_pack.sqlite';

/// 実アセットから解決する既定実装。
Future<String> defaultResolveRegionPackPath() => resolveBundledMbtilesPath(
      assetKey: regionPackAssetKey,
      fileName: 'region_pack.sqlite',
    );
