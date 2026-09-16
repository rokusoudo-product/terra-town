import 'package:flutter/foundation.dart';
import 'package:terra_town_core/terra_town_core.dart';

/// 「今どの建物を建てようとしているか」というタブ横断の選択状態（Issue #192・T089）。
///
/// ## タブ切り替えをまたいで状態を持ち回す理由
/// 建設タブ（[BuildScreen]）で建物を選ぶと、地図タブに切り替わって建てられる
/// マスを選ぶ（Issue #192 本文「建設の流れ」）。`RootScaffold`（`main.dart`）は
/// タブ本体を `switch (_selectedIndex)` で毎回別ウィジェットに差し替えており
/// （`IndexedStack` ではない）、地図タブへ切り替わるたびに `MapScreen` の
/// State は作り直される。そのため「選んだ建物」は `MapScreen` 自身の State では
/// 保持できず、`RootScaffold` が持つ本コントローラのように**タブ切り替えを
/// またいで生き続けるオブジェクト**に置く必要がある
/// （`_gameDatabase`・各種 Repository と同じ扱い）。
///
/// 本クラスは `ValueNotifier` として `MapScreen` に渡され、地図タブ側は
/// [value] の変化（`addListener`）でハイライト表示・タップの振り分けを
/// 切り替える。
class BuildSelectionController extends ValueNotifier<BuildingType?> {
  BuildSelectionController() : super(null);

  /// 建設する建物を選ぶ（建設タブ「建てる場所を選ぶ」ボタンから呼ぶ）。
  void select(BuildingType buildingType) => value = buildingType;

  /// 選択状態を終える（地図タブの「やめる」・建築成功後に呼ぶ）。
  void clear() => value = null;
}
