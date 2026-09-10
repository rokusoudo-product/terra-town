import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 同梱 MBTiles アセット（[assetKey]）が Flutter アセットバンドルに存在しない場合に
/// 送出する例外。
///
/// 【背景・tasks.md T055 / Issue #99】地域パックの生成物（`app/assets/pack/tiles.mbtiles`）
/// はリポジトリにコミットしない方針（Issue #85）のため、
/// `tools/pack-builder/bundle_region_pack.sh` を実行していない環境ではアセットが
/// 存在せず、[rootBundle] からの読込が失敗する。呼び出し側（`app`）がこの状態を
/// 「エラー」として画面に出せるよう、判別可能な型に変換して送出する
/// （`MapScreen` の4状態のうちエラー状態。DESIGN.md「マップ（ホーム）」の
/// ローディング=地域パック読込、の失敗系として扱う）。
class PackAssetMissingException implements Exception {
  const PackAssetMissingException(this.assetKey);

  /// 見つからなかったアセットキー（例: `assets/pack/tiles.mbtiles`）。
  final String assetKey;

  @override
  String toString() =>
      'PackAssetMissingException: アセット "$assetKey" が見つかりません'
      '（tools/pack-builder/bundle_region_pack.sh が未実行の可能性があります）';
}

/// Flutter アセットバンドル内の MBTiles ファイル（[assetKey]）を、書き込み可能な
/// ローカルファイルシステム上のパスとして用意し、そのパスを返す。
///
/// 【コピーが必要な理由】MapLibre のローカル MBTiles 読込（`mbtiles://` 方式。
/// research.md §6.2 で実機成立を確認済み）は実ファイルシステム上のパスを要求するが、
/// Flutter のアセットバンドルは読み取り専用の仮想ファイルシステムであり、
/// そのままではパスを渡せない。そのため一度だけ書き込み可能な領域へコピーする。
///
/// 【コピー先に systemTemp・キャッシュ領域を使わない理由】OS がいつ内容を消去しても
/// よい領域であり、地図を開くたびに消えている可能性がある。本パッケージは
/// 既に `GameDatabase`/`RegionPackConnection` のファイルパス解決で `path_provider`
/// を使用しており、アプリ専有かつ永続的な領域（既定は
/// [getApplicationSupportDirectory]）を使う方針を踏襲する。
///
/// 既に同一バイト数のファイルがコピー先に存在する場合は再コピーしない
/// （毎回のマップ画面表示のたびに数百KB〜のファイルI/Oが走らないようにするため）。
///
/// [resolveTargetDirectory] はテスト時にコピー先を差し替えるためのフック
/// （既定は [getApplicationSupportDirectory]。`path_provider` のプラットフォーム
/// チャンネルはテスト環境では使えないため、テストでは一時ディレクトリ等を注入する）。
Future<String> resolveBundledMbtilesPath({
  required String assetKey,
  String fileName = 'tiles.mbtiles',
  Future<Directory> Function() resolveTargetDirectory =
      getApplicationSupportDirectory,
}) async {
  final ByteData data;
  try {
    data = await rootBundle.load(assetKey);
  } catch (_) {
    throw PackAssetMissingException(assetKey);
  }

  final bytes = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  final targetDirectory = await resolveTargetDirectory();
  final file = File(p.join(targetDirectory.path, fileName));

  final alreadyUpToDate =
      await file.exists() && (await file.length()) == bytes.length;
  if (!alreadyUpToDate) {
    await targetDirectory.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }
  return file.path;
}
