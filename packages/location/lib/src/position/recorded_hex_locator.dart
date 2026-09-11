import 'package:terra_town_core/terra_town_core.dart';

/// [HexLocator]（`packages/core/lib/src/disclosure/hex_locator.dart`・Issue #101）の
/// 本番実装（Issue #108）。
///
/// ## これが最終形である（Issue #107・#108 の経緯）
/// 以前（Issue #115）は本パッケージが `h3_flutter` を使い、Dart 側で緯度経度→H3の
/// 変換を行う `H3HexLocator` を暫定実装として持っていた（Issue #107・2026-09-10
/// 代表決定「位置トラッキング基盤〔Issue #10〕に着手するまでの暫定」）。
///
/// 位置記録 foreground service（T046〜T048）の実装（Issue #123）に伴い、Kotlin 側
/// （`app/android/app/src/main/kotlin/jp/rokusoudo/terra_town/location/H3HexIndexer.kt`）
/// が記録時点で H3 インデックスを確定し、`location_point.hex_id` に保存する形になった
/// （Issue #108）。Dart 側（本クラス）は、Pigeon 経由で受け取った
/// [GeoPosition.hexId]（`NativePositionProvider` が `LocationPointMessage.hexId` を
/// そのまま写したもの）を**返すだけ**であり、変換ロジック自体は一切持たない。
/// `specs/001-mvp/plan.md` §2「位置記録の保存を Kotlin 側からローカルDBへ直接書き込む
/// 形で実装し、Dart は読むだけにする」がヘクスIDについても文字どおり成立した状態。
///
/// `h3_flutter`／`h3_dart` への依存は本 Issue で撤去済み（`pubspec.yaml`・
/// `packages/location/lib/terra_town_location.dart` 参照）。`packages/core` は
/// 元から H3 実装を持ち込んでいない（`tools/check_import_direction.sh` で検証）。
///
/// ## [position].hexId が null の場合は [StateError]（fail-loud・重要な設計判断）
/// [GeoPosition.hexId] は既定値 `null` のフィールドである（テスト・
/// `FakePositionProvider` 等、位置記録を経由しない `GeoPosition` 生成箇所を壊さない
/// ため）。しかし [DisclosureService] に実際に渡ってくる位置が
/// [NativePositionProvider] 経由（＝記録を経由済み）である以上、その時点で
/// [GeoPosition.hexId] が `null` であることは「配線のバグ」を意味する
/// （記録を経由していない位置がそのまま開示判定に渡っている、という状態）。
/// これを黙って握りつぶす（例えば `HexId(0)` のような意味のある値に見える
/// ダミー値を返す）と、「開示が静かに壊れる」という本プロジェクトが繰り返し
/// 避けてきた失敗様式になるため、明確なメッセージの [StateError] を投げる。
class RecordedHexLocator implements HexLocator {
  const RecordedHexLocator();

  @override
  HexId locate(GeoPosition position) {
    final hexId = position.hexId;
    if (hexId == null) {
      throw StateError(
        'GeoPosition.hexId が null です（緯度: ${position.latitude}, '
        '経度: ${position.longitude}）。RecordedHexLocator は記録済み（Kotlin側で '
        'hex_id を確定済み）の GeoPosition のみを受け取る想定であり、これは '
        '記録を経由していない位置が開示判定に渡っている配線バグの可能性が高い '
        '（RecordedHexLocator のクラスdoc参照）。',
      );
    }
    return hexId;
  }
}
