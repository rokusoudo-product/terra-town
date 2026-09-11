package jp.rokusoudo.terra_town.location

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [H3HexIndexer] が `h3-py` 4.5.0（解像度11）と実測で一致することを検証するテスト
 * （Issue #108）。
 *
 * ## なぜこのテストが必要か
 * `docs/terrain.md` §4 は「H3 は決定論的アルゴリズムであり、言語が違っても同じ緯度経度・
 * 同じ解像度から同じ値が得られる」としているが、これは仕様上の主張であり、本プロジェクトで
 * Kotlin 側と Python 側を実際に突き合わせた実測ではなかった（旧 Dart 実装
 * `H3HexLocator`・`hex_locator_h3_test.dart` は `flutter test` がプラグインのネイティブ
 * ビルドを経由しないため、この突き合わせを一度も実行できていなかった。本テストは
 * この検証が実際に実行される最初のケースになる。詳細は PR #108 本文参照）。
 *
 * 一致しない場合、パックの `hex_terrain` を引けず開示が全く機能しなくなる（しかも
 * 例外が出ず静かに壊れる）ため、一致を機械的に検証する。
 *
 * ## 検証データの生成手順（再現方法）
 * `src/test/resources/h3_py_reference.json` は
 * `tools/pack-builder/generate_hex_locator_fixture.py`（`h3-py` 4.5.0・解像度11）が
 * 生成した固定フィクスチャである。再生成する場合:
 *
 * ```bash
 * cd tools/pack-builder
 * ./.venv/bin/python generate_hex_locator_fixture.py
 * ```
 *
 * 座標は (1) 対象エリア（狭山湖周辺・パック生成に使っている bbox）内から固定シードの
 * 疑似乱数で抽出した30点、(2) 全球の座標（赤道・南半球・高緯度・日付変更線付近など）7点、
 * の計37点。詳細は生成スクリプト自身のdocstringを参照。
 */
class H3HexIndexerTest {
    @Test
    fun `フィクスチャが空でないこと（テスト自体が無効化されていないことの確認）`() {
        val rows = HexFixture.load()
        assertTrue(rows.isNotEmpty())
        assertTrue("フィクスチャは30点以上を含むはず", rows.size >= 30)
    }

    @Test
    fun `H3HexIndexer は h3-py 4_5_0（解像度11）と全点で一致する`() {
        val rows = HexFixture.load()
        val mismatches = mutableListOf<String>()

        for (row in rows) {
            val actual = H3HexIndexer.locate(row.lat, row.lon)
            if (actual != row.hexId) {
                mismatches.add("lat=${row.lat} lon=${row.lon}: h3-py=${row.hexId} kotlin(h3-java)=$actual")
            }
        }

        assertTrue(
            "h3-py との不一致が見つかりました（一致しない場合、開示が機能しません）: " +
                mismatches.joinToString("; "),
            mismatches.isEmpty(),
        )
    }

    @Test
    fun `同一ヘクス内の異なる緯度経度からは同一のH3インデックスが返る`() {
        val rows = HexFixture.load()
        val first = rows.first()

        val a = H3HexIndexer.locate(first.lat, first.lon)
        // 解像度11の平均対辺は約48〜50m（docs/terrain.md §3.1）。1e-6度
        // （緯度換算で約0.11m）ずらす程度ではヘクス境界をまたがないことがほとんど。
        val b = H3HexIndexer.locate(first.lat + 0.000001, first.lon)

        assertEquals(a, b)
    }

    @Test
    fun `H3インデックスは2^53(JSON安全整数の上限)を超えうる`() {
        // research.md §8.4 の実測最大値。2^53-1(9,007,199,254,740,991)を大きく超える。
        val measuredMaxHexId = 626833456793083903L
        assertTrue(measuredMaxHexId > 9007199254740991L)

        // フィクスチャ中の実際の値でも同様に2^53を超えることを確認し、本テストが
        // 「たまたま小さい値だけで一致していた」という誤検証でないことを保証する。
        val rows = HexFixture.load()
        val anyExceeds53Bit = rows.any { it.hexId > 9007199254740991L }
        assertTrue(
            "フィクスチャの hex_id が全て2^53未満では、大きい値の往復精度を検証できません",
            anyExceeds53Bit,
        )
    }
}
