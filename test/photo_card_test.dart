import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:syncubator/providers/photo_provider.dart';
import 'package:syncubator/widgets/photo_card.dart';

// Demo mode (USE_MOCK_DATA defaults to true): PhotoService keeps the state locally.
void main() {
  testWidgets('Phototherapy button switches the light on and off', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PhotoProvider(),
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PhotoCard()))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('OFF'), findsOneWidget);
    expect(find.text('TURN ON'), findsOneWidget);

    await tester.tap(find.text('TURN ON'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ON'), findsOneWidget);
    expect(find.text('TURN OFF'), findsOneWidget);

    await tester.tap(find.text('TURN OFF'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('OFF'), findsOneWidget);

    // stop the card's polling timer before the test ends
    await tester.pumpWidget(const SizedBox());
  });
}
