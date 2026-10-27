import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:syncubator/providers/alarm_provider.dart';
import 'package:syncubator/widgets/sos_button.dart';

// Runs in demo mode (USE_MOCK_DATA defaults to true), where the SOS is kept
// locally by AlarmService, so this exercises the widgets and provider
// without a Pi.
Widget _app() => ChangeNotifierProvider(
      create: (_) => AlarmProvider(),
      child: const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SosBanner(),
              Center(child: SosHeaderButton()),
            ],
          ),
        ),
      ),
    );

Future<void> _hold(WidgetTester tester, Finder f, Duration d) async {
  final g = await tester.startGesture(tester.getCenter(f));
  // Step frame by frame: the hold animation starts timing on its first frame.
  await tester.pump();
  for (var t = 0; t < d.inMilliseconds; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await g.up();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('a short tap does not raise SOS, it explains the hold', (tester) async {
    await tester.pumpWidget(_app());
    await _hold(tester, find.text('SOS'), const Duration(milliseconds: 300));
    expect(find.text('SOS: help needed at the incubator'), findsNothing);
    expect(find.text('Hold SOS for 2 seconds to call for help.'), findsOneWidget);
  });

  testWidgets('holding 2 s raises SOS, holding cancel clears it', (tester) async {
    await tester.pumpWidget(_app());
    await _hold(tester, find.text('SOS'), const Duration(milliseconds: 2100));
    expect(find.text('SOS: help needed at the incubator'), findsOneWidget);
    expect(find.text('SENT'), findsOneWidget);

    // Releasing cancel early keeps the SOS on.
    await _hold(tester, find.text('Hold to cancel'), const Duration(milliseconds: 500));
    expect(find.text('SOS: help needed at the incubator'), findsOneWidget);

    await _hold(tester, find.text('Hold to cancel'), const Duration(milliseconds: 2100));
    expect(find.text('SOS: help needed at the incubator'), findsNothing);
    expect(find.text('SOS'), findsOneWidget);
  });
}
