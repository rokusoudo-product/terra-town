/// `MapLibreMapController.queryRenderedFeatures` が返した地物の `id` を整数に
/// 変換する（Issue #151・2026-09-13 実機で判明した不具合への対処）。
///
/// ## なぜ数値と文字列の両方を受けるか
/// fog of war のソースは各 Feature の直下に**整数**の `id` を持たせて追加している
/// （`fog_of_war_layer.dart`・Issue #56/#100）。しかし `maplibre_gl` の Android 実装は
/// 問い合わせ結果を MapLibre の GeoJSON モデル（`org.maplibre.geojson.Feature`）の
/// `toJson()` で文字列化して Dart へ渡し（`MapLibreMapController.java` の
/// `featuresReply`）、同モデルは地物の `id` を**文字列**として保持する。そのため
/// Dart 側で `jsonDecode` した結果の `id` は `"833107801608191"` のような文字列になる。
///
/// 当初の実装は `id` が `num` の場合だけを受け付けていたため、実機では**どのヘクスを
/// タップしても黙って何も起きなかった**（2026-09-13 秘書の実機検証で発見）。
/// プラットフォームや将来の plugin 更新で数値に戻る可能性もあるため、両方を受ける。
///
/// 解釈できない値（null・小数部を持つ数値・数字以外の文字列）の場合は null を返す。
int? parseRenderedFeatureId(Object? rawId) {
  if (rawId is int) return rawId;
  if (rawId is num) {
    return rawId == rawId.truncateToDouble() ? rawId.toInt() : null;
  }
  if (rawId is String) return int.tryParse(rawId.trim());
  return null;
}
