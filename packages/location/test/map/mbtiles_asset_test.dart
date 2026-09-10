import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveBundledMbtilesPath', () {
    test(
      'アセットが存在しない場合は PackAssetMissingException を送出する'
      '（本パッケージ自身の pubspec は "assets/pack/tiles.mbtiles" を宣言していないため、'
      '実際に存在しないアセットキーで再現できる。Issue #85「生成物はコミットしない」'
      '方針により、bundle_region_pack.sh 未実行の環境で実際に起きる状態と同じ）',
      () async {
        expect(
          () => resolveBundledMbtilesPath(assetKey: 'assets/pack/tiles.mbtiles'),
          throwsA(isA<PackAssetMissingException>()),
        );
      },
    );

    test('PackAssetMissingException はアセットキーを保持する', () async {
      try {
        await resolveBundledMbtilesPath(assetKey: 'assets/pack/tiles.mbtiles');
        fail('例外が送出されるはず');
      } on PackAssetMissingException catch (e) {
        expect(e.assetKey, 'assets/pack/tiles.mbtiles');
        expect(e.toString(), contains('assets/pack/tiles.mbtiles'));
      }
    });

    test('アセットが存在する場合、指定ディレクトリへ内容をそのままコピーしパスを返す', () async {
      const fakeAssetKey = 'fake/tiles.mbtiles';
      final fakeBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
        final requestedKey = utf8.decode(message!.buffer.asUint8List());
        if (requestedKey == fakeAssetKey) {
          return ByteData.sublistView(fakeBytes);
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMessageHandler('flutter/assets', null);
      });

      final tempDir = await Directory.systemTemp.createTemp(
        'mbtiles_asset_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final path = await resolveBundledMbtilesPath(
        assetKey: fakeAssetKey,
        fileName: 'copied.mbtiles',
        resolveTargetDirectory: () async => tempDir,
      );

      expect(path, '${tempDir.path}${Platform.pathSeparator}copied.mbtiles');
      final copied = await File(path).readAsBytes();
      expect(copied, fakeBytes);
    });

    test('2回目の呼び出しでも同じ内容を返す（既にコピー済みの場合は再コピーしない）', () async {
      const fakeAssetKey = 'fake/tiles2.mbtiles';
      final fakeBytes = Uint8List.fromList([9, 8, 7]);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
        final requestedKey = utf8.decode(message!.buffer.asUint8List());
        if (requestedKey == fakeAssetKey) {
          return ByteData.sublistView(fakeBytes);
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMessageHandler('flutter/assets', null);
      });

      final tempDir = await Directory.systemTemp.createTemp(
        'mbtiles_asset_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final firstPath = await resolveBundledMbtilesPath(
        assetKey: fakeAssetKey,
        fileName: 'copied2.mbtiles',
        resolveTargetDirectory: () async => tempDir,
      );
      final secondPath = await resolveBundledMbtilesPath(
        assetKey: fakeAssetKey,
        fileName: 'copied2.mbtiles',
        resolveTargetDirectory: () async => tempDir,
      );

      expect(secondPath, firstPath);
      expect(await File(secondPath).readAsBytes(), fakeBytes);
    });
  });
}
