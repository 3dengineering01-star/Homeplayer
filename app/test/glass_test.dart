import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/services/appearance.dart';
import 'package:homeplay/widgets/glass.dart';

void main() {
  Future<void> pump(WidgetTester tester, Appearance look, VoidCallback onTap) => tester.pumpWidget(MaterialApp(
        theme: look.theme(dark: false),
        home: Scaffold(
          body: BackdropGroup(
            child: Center(child: GlassPane(onTap: onTap, child: const SizedBox(width: 200, height: 80, child: Text('Pane')))),
          ),
        ),
      ));

  testWidgets('with glass the pane blurs what is behind it, without it is a plain card; both take taps', (tester) async {
    var taps = 0;
    await pump(tester, const Appearance(), () => taps++);
    expect(find.byType(BackdropFilter), findsOneWidget);
    await tester.tap(find.text('Pane'));
    expect(taps, 1);

    await pump(tester, const Appearance(glass: false), () => taps++);
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.tap(find.text('Pane'));
    expect(taps, 2);
    expect(tester.takeException(), isNull);
  });
}
