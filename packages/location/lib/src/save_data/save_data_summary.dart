/// 読み込み前の確認ダイアログ（Issue #180 決定事項4）が表示する要約。
///
/// 「ファイルを検証してから確認ダイアログを出す」の"検証結果"に相当する。
/// [SaveDataTransferService.parseSummary]（`save_data_transfer_service.dart`）が
/// ファイルの構造検証に成功した後に組み立てて返す。
class SaveDataSummary {
  const SaveDataSummary({
    required this.exportedAt,
    required this.disclosedHexCount,
    required this.openingPoints,
    required this.collectionCount,
  });

  /// ファイルの `exported_at`（書き出し日時）。
  final DateTime exportedAt;

  /// `tables.disclosed_hex` の件数（開示済みヘクス数）。
  final int disclosedHexCount;

  /// `tables.settings` に保存されている開放ポイント所持数
  /// （`OpeningPointLedger.pointsKey` = `opening_point.points`）。行が無ければ0。
  final int openingPoints;

  /// `tables.collection` の件数（名所の収集数）。
  final int collectionCount;
}
