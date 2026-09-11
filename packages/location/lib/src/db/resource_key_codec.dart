import 'package:terra_town_core/terra_town_core.dart';

/// `inventory` テーブル（[GameDatabase.inventories]）の `resourceKey`（生の文字列。
/// `game_database.dart` のクラスdoc「`core` の `Resource` 型に依存しない理由」参照）と
/// `core` の [Resource] enum を相互変換するための小さなヘルパー（Issue #138）。
///
/// キーは常に [Resource.name] を使う（`resourceKey` のドキュメントが想定する
/// 「`core` 側 enum が定まった際の `.name`」をそのまま採用）。
String resourceKeyOf(Resource resource) => resource.name;

/// [key] に対応する [Resource] を返す。対応する値が無い場合（未知のキー・
/// データ破損等）は null を返す（呼び出し側は「不明な資材は無視する」という
/// 罰しない側の方針で扱うこと。`RewardSettingsRepository` の「解釈不能な値は
/// 罰しない側に倒す」と同じ考え方）。
Resource? resourceFromKey(String key) {
  for (final resource in Resource.values) {
    if (resource.name == key) return resource;
  }
  return null;
}
