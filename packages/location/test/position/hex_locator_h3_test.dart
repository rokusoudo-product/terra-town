import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// `H3HexLocator`（Issue #115）が `h3-py` 4.5.0 と実測で一致することを検証するテスト。
///
/// ## なぜこのテストが必要か
/// `docs/terrain.md` §4 は「H3 は決定論的アルゴリズムであり、言語が違っても同じ緯度経度・
/// 同じ解像度から同じ値が得られる」としているが、これは仕様上の主張であって、
/// 本プロジェクトで Dart 側と Python 側を実際に突き合わせた実測ではなかった
/// （Issue #115・Issue #107 2026-09-10 代表決定コメント）。一致しない場合、パックの
/// `hex_terrain` を引けず開示が全く機能しなくなる（しかも例外が出ず静かに壊れる）ため、
/// 一致を機械的に検証する。
///
/// ## 検証データの生成手順（再現方法）
/// `fixtures/h3_py_reference.json` は `tools/pack-builder/generate_hex_locator_fixture.py`
/// （`h3-py` 4.5.0・解像度11。バージョンは `tools/pack-builder/requirements.txt` で固定）
/// が生成した固定フィクスチャである。再生成する場合:
///
/// ```bash
/// cd tools/pack-builder
/// ./.venv/bin/python generate_hex_locator_fixture.py \
///     --out ../../packages/location/test/position/fixtures/h3_py_reference.json
/// ```
///
/// 座標は (1) 対象エリア（狭山湖周辺・パック生成に使っている bbox）内から固定シードの
/// 疑似乱数で抽出した30点、(2) 全球の座標（赤道・南半球・高緯度・日付変更線付近など）7点、
/// の計37点。詳細は生成スクリプト自身のdocstringを参照。
///
/// `hex_id` は JSON の安全整数上限（2^53-1）を超えうるため、フィクスチャ上は10進の
/// **文字列**として保持している（数値として書き出すと精度が壊れる可能性があるため）。
/// 本テストは [BigInt.parse] で読み、[H3HexLocator.locate] が返す [HexId.value]（Dart の
/// `int`）と [BigInt] のまま比較することで、往復のどこでも精度を落とさない。
///
/// ## ⚠️ 既知の制約: 本テストの h3-py 突き合わせ部分は `flutter test` では実行できない
/// `h3_flutter` は **FFI プラグイン**であり、ネイティブライブラリ（Android/Linuxでは
/// `libh3.so`）は `flutter build`（CMake によるネイティブビルド）を経由して初めて
/// 生成・同梱される。`flutter test` はホストの Dart VM 上でテストを実行するだけで、
/// プラグインのネイティブビルドを一切行わないため、通常の開発環境・CI環境では
/// ネイティブライブラリが存在せず `H3Factory().load()` がロードに失敗する
/// （`h3_flutter` 自身の上流テスト（`festelo/h3_dart` の `tests.yml`）も
/// `flutter test` ではなく `integration_test`（実機/エミュレータ、または
/// ビルド済みデスクトップアプリ）に対してのみ動作確認しており、単体テストとしての
/// `flutter test` では検証していない）。
///
/// 本 Issue（#115）の実装セッションでは、この制約により
/// **h3-py との一致は実機/CIのいずれでも未実行**（下記 `skip` 参照）。
/// PR 本文に詳細と代表判断が必要な選択肢を記載している。
void main() {
  // 上記の制約をコードでも機械的に検知する: 実際に `H3HexLocator.locate` を
  // 1回呼び出してみて、ネイティブライブラリのロードに失敗する場合は
  // 該当テストを `skip` にする（`flutter test` を静かに失敗させたまま
  // CI を壊す・あるいは「常にfailなので無視してよい」という運用の劣化を防ぐため、
  // skip 理由に制約の説明を必ず含める。Issue #50・#58と同じ「静かに壊れるガード」を
  // 作らないための対応）。ネイティブライブラリが提供される環境（実機ビルド後の
  // integration_test 等）では自動的にこの skip が外れ、テストが実行される。
  String? h3LoadError;
  try {
    const H3HexLocator().locate(
      GeoPosition(latitude: 0, longitude: 0, timestamp: DateTime.now()),
    );
  } catch (e) {
    h3LoadError = e.toString();
  }
  final Object skipIfH3Unavailable = h3LoadError == null
      ? false
      : 'h3_flutter(FFIプラグイン)のネイティブライブラリを読み込めないため未実行: '
            '$h3LoadError / flutter test はプラグインのネイティブビルドを経由しない '
            '既知の制約（本ファイル先頭のdocコメント参照）。h3-pyとの一致は未検証のまま。';

  late List<dynamic> fixtureRows;

  setUpAll(() {
    final fixtureFile = File('test/position/fixtures/h3_py_reference.json');
    fixtureRows = jsonDecode(fixtureFile.readAsStringSync()) as List<dynamic>;
  });

  test('フィクスチャが空でないこと（テスト自体が無効化されていないことの確認）', () {
    expect(fixtureRows, isNotEmpty);
    expect(fixtureRows.length, greaterThanOrEqualTo(30));
  });

  test('H3HexLocator は h3-py 4.5.0（解像度11）と全点で一致する', () {
    const locator = H3HexLocator();
    final mismatches = <String>[];

    for (final entry in fixtureRows) {
      final row = entry as Map<String, dynamic>;
      final lat = (row['lat'] as num).toDouble();
      final lon = (row['lon'] as num).toDouble();
      final expected = BigInt.parse(row['hex_id'] as String);

      final actual = locator.locate(
        GeoPosition(
          latitude: lat,
          longitude: lon,
          timestamp: DateTime.utc(2026, 9, 11),
        ),
      );

      if (BigInt.from(actual.value) != expected) {
        mismatches.add(
          'lat=$lat lon=$lon: h3-py=$expected dart(h3_flutter)=${actual.value}',
        );
      }
    }

    expect(
      mismatches,
      isEmpty,
      reason:
          'h3-py との不一致が見つかりました（一致しない場合、開示が機能しません）: '
          '${mismatches.join('; ')}',
    );
  }, skip: skipIfH3Unavailable);

  test(
    '同一ヘクス内の異なる緯度経度からは同一の HexId が返る（HexLocator の契約）',
    () {
      const locator = H3HexLocator();
      final row = fixtureRows.first as Map<String, dynamic>;
      final lat = (row['lat'] as num).toDouble();
      final lon = (row['lon'] as num).toDouble();

      final first = locator.locate(
        GeoPosition(latitude: lat, longitude: lon, timestamp: DateTime.now()),
      );
      // 解像度11の平均対辺は約48〜50m（docs/terrain.md §3.1）。1e-6度（緯度換算で
      // 約0.11m）ずらす程度ではヘクス境界をまたがないことがほとんどであり、
      // 「同一ヘクス内の別座標からは同一HexIdが返る」ことの素朴な確認になる
      // （境界ぎりぎりの座標を選んでいないため、稀に別ヘクスになる可能性はゼロでは
      // ないが、[HexLocator] の契約自体はフィクスチャ全点一致テストで検証済み）。
      final second = locator.locate(
        GeoPosition(
          latitude: lat + 0.000001,
          longitude: lon,
          timestamp: DateTime.now(),
        ),
      );

      expect(second, first);
    },
    skip: skipIfH3Unavailable,
  );

  test(
    '2^53(JSON安全整数の上限)を超えるhex_idでも精度を落とさず扱える'
    '（注: これは BigInt<->int の往復のみの確認であり、h3_flutter(FFI)は経由しない。'
    'h3-pyとの実測比較は上記2テストで行っている）',
    () {
      // research.md §8.4 の実測最大値。2^53-1(9,007,199,254,740,991)を大きく超える。
      const measuredMaxHexId = 626833456793083903;
      expect(measuredMaxHexId, greaterThan(9007199254740991));

      // フィクスチャ中の実際の値（h3-py が返した値）でも同様に2^53を超えることを確認し、
      // 本テストが「たまたま小さい値だけで一致していた」という誤検証でないことを保証する。
      final anyExceeds53Bit = fixtureRows
          .map((e) => BigInt.parse((e as Map<String, dynamic>)['hex_id'] as String))
          .any((v) => v > BigInt.from(9007199254740991));
      expect(
        anyExceeds53Bit,
        isTrue,
        reason: 'フィクスチャの hex_id が全て2^53未満では、大きい値の往復精度を検証できない',
      );

      // BigInt -> Dart int(64bit) の往復で精度が壊れないこと自体の確認
      // （H3HexLocator.locate 内部で行っている変換と同じ経路）。
      final big = BigInt.from(measuredMaxHexId);
      expect(big.toInt(), measuredMaxHexId);
      expect(HexId(big.toInt()).value, measuredMaxHexId);
    },
  );
}
