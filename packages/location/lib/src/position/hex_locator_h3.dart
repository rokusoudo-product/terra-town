import 'package:h3_flutter/h3_flutter.dart' as h3lib;
import 'package:terra_town_core/terra_town_core.dart';

/// [HexLocator]（`packages/core/lib/src/disclosure/hex_locator.dart`・Issue #101）の
/// H3（Uber H3 v4世代）による実装（Issue #115）。
///
/// ## これは暫定実装である（最重要・Issue #107・2026-09-10 代表決定）
/// 緯度経度→ヘクスIDの変換場所は、当面は本クラスのとおり Dart 側（`packages/location/`）で
/// `h3_flutter` を使って実装する。しかし最終形は `specs/001-mvp/plan.md` §2 の
/// 「位置記録の保存を Kotlin 側からローカルDBへ直接書き込む形で実装し、Dart は読むだけに
/// する」という方針であり、**位置記録基盤（tasks.md T046〜T049・Issue #10）に着手する
/// 時点で、この変換ロジックは Kotlin 側（案B）へ寄せる**（追跡: Issue #108・`future`）。
/// Issue #10・#9（GPS偽装対策）が `future` で設計未確定のため、それまでの先行実装として
/// 本クラスを置いている。恒久的な実装場所の決定ではない点に注意すること。
///
/// ## `core` に H3 依存を持ち込まない理由
/// `docs/terrain.md` §4.3・[HexLocator] のクラスdocのとおり、緯度経度→ヘクスIDの
/// 変換ロジックそのものは `core` に置かない（GPS_ARCHITECTURE 準拠）。本クラスは
/// `packages/location/` 側にのみ存在し、`packages/core` は本クラスの存在を知らない
/// （`core` は [HexId] という結果の値オブジェクトだけを扱う）。
///
/// ## 解像度は11で固定（`docs/terrain.md` §3.1・§4.2 代表決定・2026-09-08 Issue #38）
/// `tools/pack-builder/config.py` の `H3_RESOLUTION`（パック生成側）と必ず一致させる
/// こと。解像度が食い違うと、同じ緯度経度でも生成側と実行側で異なる `hex_id` になり、
/// パックの `hex_terrain` を引けなくなる（開示が静かに機能しなくなる。Issue #115 本文）。
///
/// ## `h3-py` との一致は実測で検証済み（コードコメントではなくテストが正）
/// `docs/terrain.md` §4 の「H3は決定論的アルゴリズムであり言語が違っても同じ値になる」
/// という記述は仕様上の主張であり、本プロジェクトで実際に突き合わせた実測ではなかった
/// （Issue #115・Issue #107 代表決定コメントで明記）。本クラスは
/// `test/position/hex_locator_h3_test.dart` で、`tools/pack-builder` の `h3-py` 4.5.0
/// が実際に出す値との突き合わせにより検証されている（生成手順は同テストファイルの
/// 先頭コメント・`tools/pack-builder/generate_hex_locator_fixture.py` を参照）。
///
/// ## `hex_id` が 2^53 を超える点について
/// H3 index の実測最大値は 626,833,456,793,083,903（`specs/001-mvp/research.md` §8.4）
/// であり、JSON の安全整数上限（2^53-1 ≒ 9.007×10^15）を大きく超える。
/// `h3_flutter`（`h3_common`）の `H3Index` は `BigInt` 型で返るため、[HexId.value]
/// （Dart の `int`。64bit）へ変換する際に [BigInt.toInt] を使うが、H3 index は
/// 仕様上常に2^63未満（reservedビットが常に0。`docs/terrain.md` §4.4・research.md §8.4
/// で実測確認済み）であるため、64bit符号付き整数の範囲を超えることはなく、
/// この変換で精度が失われることはない。本 Issue のスコープでは JSON や
/// プラットフォームチャネルを経由させないため、丸めのリスクはそもそも発生しない。
class H3HexLocator implements HexLocator {
  const H3HexLocator();

  /// H3 の解像度。`docs/terrain.md` §3.1・§4.2 の代表決定により11で固定。
  ///
  /// `tools/pack-builder/config.py` の `H3_RESOLUTION` と必ず一致させること。
  static const int resolution = 11;

  /// `h3_flutter` のネイティブ実装ハンドル。
  ///
  /// `H3Factory().load()` はダイナミックライブラリのロード等のコストを伴うため、
  /// インスタンス毎ではなくクラス全体で1回だけロードして共有する。
  static final h3lib.H3 _h3 = const h3lib.H3Factory().load();

  @override
  HexId locate(GeoPosition position) {
    final h3lib.H3Index index = _h3.geoToCell(
      h3lib.GeoCoord(lat: position.latitude, lon: position.longitude),
      resolution,
    );
    return HexId(index.toInt());
  }
}
