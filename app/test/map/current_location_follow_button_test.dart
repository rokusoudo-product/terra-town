import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town/design/app_theme.dart';
import 'package:terra_town/map/current_location_follow_button.dart';

Widget _wrap(Widget child) {
  return MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));
}

void main() {
  // Issue #141 受け入れ基準「追従オンでカメラが現在地を追い、利用者が地図を
  // 動かすと追従が解除される。ボタンで再開できる」の UI 側。
  // DESIGN.md「色だけで情報を伝えない」に従い、アイコン・Semanticsラベルの
  // 両方でオン/オフの状態が伝わることを検証する（色の違いはテストしない）。
  testWidgets('追従オフの場合、開始を促すアイコン・ラベルを表示する', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CurrentLocationFollowButton(isFollowing: false, onPressed: () {}),
      ),
    );

    expect(find.byIcon(Icons.location_searching), findsOneWidget);
    expect(find.byIcon(Icons.my_location), findsNothing);
    expect(
      find.bySemanticsLabel('現在地に地図を合わせて追従する'),
      findsOneWidget,
    );
  });

  testWidgets('追従オンの場合、解除を促すアイコン・ラベルを表示する', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CurrentLocationFollowButton(isFollowing: true, onPressed: () {}),
      ),
    );

    expect(find.byIcon(Icons.my_location), findsOneWidget);
    expect(find.byIcon(Icons.location_searching), findsNothing);
    expect(find.bySemanticsLabel('地図の追従をオフにする'), findsOneWidget);
  });

  testWidgets('タップするとonPressedが呼ばれる', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        CurrentLocationFollowButton(
          isFollowing: false,
          onPressed: () => tapped = true,
        ),
      ),
    );

    await tester.tap(find.byType(FloatingActionButton));
    expect(tapped, isTrue);
  });
}
