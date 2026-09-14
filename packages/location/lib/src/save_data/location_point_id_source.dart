import '../position/location_api.g.dart';

/// セーブデータの読み込み時、ウォーターマークの補正（Issue #180 決定事項3）に
/// 使う「読み込み先端末の現在の最大 `location_point.id`」の取得元を抽象化する。
///
/// `native_position_provider.dart` の [LocationPointsApi] と同じ理由
/// （生成された [LocationTrackingHostApi] は具象クラスであり、テストでフェイクに
/// 差し替えるには薄いインターフェースを1枚挟む方が単純なため）で用意する。
abstract interface class LocationPointIdSource {
  /// `location_point` の現在の最大 `id`。記録が1件も無ければ0
  /// （`LocationTrackingHostApi.getMaxLocationPointId` のドキュメント参照）。
  Future<int> getMaxLocationPointId();
}

/// [LocationPointIdSource] の既定実装。Pigeon が生成した
/// [LocationTrackingHostApi] へそのまま委譲するだけの薄いラッパー。
class PigeonLocationPointIdSource implements LocationPointIdSource {
  PigeonLocationPointIdSource([LocationTrackingHostApi? api])
    : _api = api ?? LocationTrackingHostApi();

  final LocationTrackingHostApi _api;

  @override
  Future<int> getMaxLocationPointId() => _api.getMaxLocationPointId();
}
