import 'package:terra_town_core/terra_town_core.dart';

/// [PositionProvider] のフェイク実装（T051・Issue #101）。
///
/// plan.md §10「テスト戦略と絡む: `PositionProvider` のフェイク実装＋録画済み歩行ルートの
/// リプレイテスト（core/location分離が活きる場所）」の実証。固定の [GeoPosition] 列
/// （＝録画済み歩行ルート）を [positionUpdates] から流すだけであり、実 GPS・地図SDKには
/// 一切依存しない（`tools/check_import_direction.sh` が `test/` も走査するため、ここに
/// GPS/地図SDK 由来の import が無いこと自体が「core が GPS 型を露出していない」ことの
/// 裏付けになる）。
///
/// 元は `position_provider_test.dart` にテスト専用の内部クラスとして定義されていたが、
/// 本 Issue（#101）で `test/disclosure/disclosure_test.dart`・
/// `test/disclosure/replay_walk_test.dart` からも「録画済み歩行ルートのリプレイ」を
/// 行うために再利用する必要が生じたため、共有フィクスチャとして本ファイルへ抽出した
/// （T051 の受け入れ基準「録画済み歩行ルートをリプレイできるテスト基盤」）。
class FakePositionProvider implements PositionProvider {
  FakePositionProvider(this._recordedRoute);

  final List<GeoPosition> _recordedRoute;

  @override
  Stream<GeoPosition> get positionUpdates => Stream.fromIterable(_recordedRoute);
}
