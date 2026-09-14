// app_version.dart の kAppVersion が pubspec.yaml の version: と一致していることを
// 機械的に検証する（Issue #180・T105・`app_version.dart` docstring参照）。
//
// package_info_plus を導入しない代わりに手で転記した定数のため、更新漏れを
// このテストが検出する（「規約ではなく仕組みで守る」・tools/check_*.sh と同じ方針）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town/app_version.dart';

void main() {
  test('kAppVersionはpubspec.yamlのversion:と一致する', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml に version: が見つかりません');
    expect(kAppVersion, match!.group(1));
  });
}
