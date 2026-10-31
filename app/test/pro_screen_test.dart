import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/screens/pro_screen.dart';
import 'package:homeplay/services/licence.dart';
import 'package:homeplay/services/pro.dart';

void main() {
  testWidgets('during the free month the screen tells the days left and the price', (tester) async {
    final pro = Pro.forTest()..status.value = const ProStatus(enforced: true, trialLeft: 12, price: '9,99 €');
    await tester.pumpWidget(MaterialApp(home: ProScreen(pro: pro)));
    expect(find.text('Pro free for 12 more days'), findsOneWidget);
    expect(find.text('Photo backup'), findsOneWidget);
    expect(find.text('Buy for 9,99 €'), findsOneWidget);
    expect(find.text('I bought it before: restore'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Pro feature after the free month: what to do, and it opens once bought', (tester) async {
    final pro = Pro.forTest()..status.value = const ProStatus(enforced: true, trialLeft: 0, price: '9,99 €');
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await Navigator.push<bool>(
              context, MaterialPageRoute(builder: (_) => ProScreen(feature: ProFeature.share, pro: pro))),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('The free month of Pro is over'), findsOneWidget);
    expect(find.textContaining('Sharing with friends is part of OwnMedia Pro'), findsOneWidget);
    pro.status.value = const ProStatus(enforced: true, bought: true, trialLeft: 0, price: '9,99 €');
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('without Google Play the button says so', (tester) async {
    final pro = Pro.forTest()..status.value = const ProStatus(enforced: true, trialLeft: 0);
    await tester.pumpWidget(MaterialApp(home: ProScreen(pro: pro)));
    expect(find.text('Google Play is not available'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });
}
