package jp.rokusoudo.terra_town.location

/**
 * `h3_py_reference.json`（`tools/pack-builder/generate_hex_locator_fixture.py` が
 * h3-py 4.5.0・解像度11で生成）を読むための最小限のフィクスチャローダー（Issue #108）。
 *
 * ## なぜ JSON ライブラリを使わず手書きで読むか（判断・PR本文にも記載）
 * `org.json`（`JSONArray`/`JSONObject`）は Android フレームワークにバンドルされている
 * クラスであり、AGP の JVM 単体テストが使うモック版 `android.jar` では未実装
 * （呼ぶと例外を投げる）。JVM から使える実体を持つ `org.json` は別の Maven 座標
 * （`org.json:json`）で配布されているが、Android の `org.json` パッケージと完全に
 * 同じパッケージ名のクラスを提供するため、テストクラスパス上での優先順位次第で
 * 意図しない方（モック版）が解決されるリスクがある。本フィクスチャは
 * `{"lat": <number>, "lon": <number>, "hex_id": "<digits>"}` の配列という**固定かつ
 * 単純な形式**（生成スクリプト自身が出力するもので人手編集されない）であるため、
 * 依存を増やすよりも正規表現による手書きパーサで十分と判断した。
 */
object HexFixture {
    data class Row(val lat: Double, val lon: Double, val hexId: Long)

    private val ROW_REGEX =
        Regex(
            "\"lat\":\\s*(-?[0-9]+(?:\\.[0-9]+)?),\\s*" +
                "\"lon\":\\s*(-?[0-9]+(?:\\.[0-9]+)?),\\s*" +
                "\"hex_id\":\\s*\"([0-9]+)\"",
        )

    /**
     * クラスパスリソース [resourceName]（既定 `h3_py_reference.json`。
     * `src/test/resources/` 配下）を読み、全行をパースして返す。
     */
    fun load(resourceName: String = "h3_py_reference.json"): List<Row> {
        val classLoader =
            requireNotNull(HexFixture::class.java.classLoader) { "クラスローダーを取得できませんでした" }
        val stream =
            requireNotNull(classLoader.getResourceAsStream(resourceName)) {
                "テストリソース $resourceName が見つかりません " +
                    "(app/android/app/src/test/resources/ 配下にあるか確認してください)"
            }
        val text = stream.bufferedReader(Charsets.UTF_8).use { it.readText() }

        val rows =
            ROW_REGEX.findAll(text).map { match ->
                val (latText, lonText, hexIdText) = match.destructured
                Row(lat = latText.toDouble(), lon = lonText.toDouble(), hexId = hexIdText.toLong())
            }.toList()

        check(rows.isNotEmpty()) { "フィクスチャ $resourceName から1件もパースできませんでした" }
        return rows
    }
}
