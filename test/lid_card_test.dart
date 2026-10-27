import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:syncubator/providers/lid_provider.dart';
import 'package:syncubator/widgets/lid_card.dart';

// Demo mode (USE_MOCK_DATA defaults to true): the lid state is kept locally
// by LidService, so this exercises the rule "Open is locked until Close".
Widget _app() => ChangeNotifierProvider(
      create: (_) => LidProvider(),
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: LidCard()))),
    );

bool _enabled(WidgetTester tester, String label) {
  final b = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, label));
  return b.onPressed != null;
}

void main() {
  testWidgets('Open then Close follows the lock rule', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('CLOSED'), findsOneWidget);
    expect(_enabled(tester, 'OPEN'), isTrue);

    await tester.tap(find.text('OPEN'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('OPENING'), findsOneWidget);
    expect(_enabled(tester, 'OPEN'), isFalse);
    expect(_enabled(tester, 'CLOSE'), isFalse);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('OPEN'), findsWidgets);
    expect(_enabled(tester, 'OPEN'), isFalse);   // locked until closed
    expect(_enabled(tester, 'CLOSE'), isTrue);

    await tester.tap(find.text('CLOSE'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('CLOSING'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('CLOSED'), findsOneWidget);
    expect(_enabled(tester, 'OPEN'), isTrue);    // unlocked again

    // stop the card's polling timer before the test ends
    await tester.pumpWidget(const SizedBox());
  });
}
