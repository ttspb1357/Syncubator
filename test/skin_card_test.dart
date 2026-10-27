import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:syncubator/providers/skin_provider.dart';
import 'package:syncubator/widgets/skin_card.dart';

// Demo mode (USE_MOCK_DATA defaults to true): SkinService returns a 36.x degC reading.
void main() {
  testWidgets('Skin card shows the temperature and the alarm state', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SkinProvider(),
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SkinCard()))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Skin Temperature'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^36\.\d$')), findsOneWidget);
    expect(find.text('Alarms: OFF'), findsOneWidget);

    // stop the card's polling timer before the test ends
    await tester.pumpWidget(const SizedBox());
  });
}
