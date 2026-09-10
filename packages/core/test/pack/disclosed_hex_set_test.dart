import 'dart:io';

import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

void main() {
  group('DisclosedHexSet（T035・開示ヘクス集合の圧縮表現）', () {
    test('追加したヘクスをcontainsで判定できる', () {
      final set = DisclosedHexSet();
      const hex = HexId(12345);

      expect(set.contains(hex), isFalse);
      set.add(hex);
      expect(set.contains(hex), isTrue);
      expect(set.length, 1);
    });

    test('同じヘクスの再追加は冪等（重複カウントしない）', () {
      final set = DisclosedHexSet();
      const hex = HexId(1);

      expect(set.add(hex), isTrue);
      expect(set.add(hex), isFalse);
      expect(set.length, 1);
    });

    test('addAll・toIterableで集合の内容を復元できる（順不同で一致）', () {
      final hexIds = [
        const HexId(0),
        const HexId(1),
        const HexId(65536), // 別コンテナ（上位ビットが異なる）
        const HexId(65537),
        const HexId(4503599627370496), // 2^52 付近（H3 由来の大きな値を想定）
      ];
      final set = DisclosedHexSet.from(hexIds);

      expect(set.length, hexIds.length);
      expect(set.toIterable().toSet(), hexIds.toSet());
      for (final hex in hexIds) {
        expect(set.contains(hex), isTrue);
      }
    });

    test('含まれていないヘクスはfalse', () {
      final set = DisclosedHexSet.from([const HexId(10)]);

      expect(set.contains(const HexId(11)), isFalse);
    });

    test('1コンテナ内の要素数が閾値(4096)を超えてもすべて正しく保持される（配列→ビットマップ昇格の境界）', () {
      // 下位16bitだけを変化させ、上位ビット（コンテナキー）を固定することで
      // 意図的に単一コンテナへ集中させ、内部コンテナが配列からビットマップへ
      // 昇格しても正しさが保たれることを検証する（ホワイトボックスではなく
      // 外部から観測できる contains/length/toIterable の一貫性で検証する）。
      final set = DisclosedHexSet();
      const containerCount = 5000; // 閾値(4096)を超える
      for (var low = 0; low < containerCount; low++) {
        set.add(HexId(low));
      }

      expect(set.length, containerCount);
      for (var low = 0; low < containerCount; low++) {
        expect(set.contains(HexId(low)), isTrue, reason: 'low=$low');
      }
      expect(set.contains(HexId(containerCount)), isFalse);
      expect(set.toIterable().length, containerCount);
    });

    test('空の集合はisEmpty', () {
      final set = DisclosedHexSet();
      expect(set.isEmpty, isTrue);
      expect(set.isNotEmpty, isFalse);
      set.add(const HexId(1));
      expect(set.isEmpty, isFalse);
      expect(set.isNotEmpty, isTrue);
    });

    test(
      '暫定上限30,000ヘクス（plan.md §3.5）を扱える（処理時間・メモリの実測ログ出力）',
      () {
        // 【実測についての注記（要確認事項として報告にも明記）】
        // ここで計測するのは本テスト実行環境（開発機・WSL上のDart VM、
        // dart test ランナー経由）での数値であり、plan.md §3.5 が前提とする
        // 実機（Pixel 7a 等）・Flutter/Android 実行環境での計測ではない。
        // 「core の DisclosedHexSet 単体が 30,000 要素を実用的な時間・メモリで
        // 扱えるか」の確認に限定され、地図描画（addGeoJsonSource 等）を含む
        // §3.5 の合格基準（起動時ソース構築2秒以内）そのものの計測ではない
        // （そちらは `location/`・実機側の検証事項）。
        const hexCount = 30000;

        // H3 由来の HexId は疎な52bit程度の値域に散らばる想定
        // （plan.md §14「feature_id（H3由来・52bitマスク後）」）。
        // 完全ランダムではなく、複数のコンテナ（上位ビットの塊）に分散する
        // 疑似的な分布を決定論的に生成する（シード固定・plan.md §4「乱数を使う
        // 要素はシード固定」の方針に倣う）。
        final hexIds = List<HexId>.generate(hexCount, (i) {
          final chunk = i % 37; // 37個のコンテナに分散させる
          final withinChunk = i ~/ 37;
          final value = (chunk << 20) + withinChunk * 3 + 1;
          return HexId(value);
        });

        int? rssBefore;
        try {
          rssBefore = ProcessInfo.currentRss;
        } catch (_) {
          // currentRss が使えないプラットフォームでは計測をスキップする
          // （正当性の検証には影響しない）。
        }

        final addStopwatch = Stopwatch()..start();
        final set = DisclosedHexSet.from(hexIds);
        addStopwatch.stop();

        int? rssAfter;
        try {
          rssAfter = ProcessInfo.currentRss;
        } catch (_) {}

        final containsStopwatch = Stopwatch()..start();
        for (final hex in hexIds) {
          expect(set.contains(hex), isTrue);
        }
        containsStopwatch.stop();

        expect(set.length, hexCount);
        expect(set.toIterable().length, hexCount);

        // ハード制限ではなく「実用的な時間で完了すること」の緩いガード
        // （CI 環境差でのフレーキーさを避けるため十分に余裕を持たせる。
        // plan.md §3.5 の「2秒以内」はソース構築＝地図描画を含む基準であり、
        // 本テストの基準とは別物である点に注意）。
        expect(addStopwatch.elapsedMilliseconds, lessThan(5000));
        expect(containsStopwatch.elapsedMilliseconds, lessThan(5000));

        // 実測ログ（`dart test -r expanded` 等で可視化される）。
        // 数値そのものをテストの合否条件にはしない（環境依存のため）。
        // ignore: avoid_print
        print(
          '[DisclosedHexSet 30,000件 実測ログ／開発機・Dart VM]'
          ' add: ${addStopwatch.elapsedMilliseconds}ms,'
          ' contains x$hexCount: ${containsStopwatch.elapsedMilliseconds}ms,'
          ' RSS差分: ${rssBefore != null && rssAfter != null ? '${((rssAfter - rssBefore) / 1024).round()}KB' : '計測不可（プラットフォーム非対応）'}',
        );
      },
    );
  });
}
