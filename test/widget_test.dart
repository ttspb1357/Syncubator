// This is a basic Flutter widget test for the Syncubator app.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:syncubator/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SyncubatorApp());
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // Verify that the home screen is displayed by checking for the main title.
    expect(find.text('Syncubator'), findsOneWidget);
    expect(find.text('Where Care Meets Innovation'), findsOneWidget);

    // Verify that baby information is displayed.
    expect(find.text('Baby A'), findsOneWidget);
    expect(find.text('NICU-001'), findsOneWidget);

    // Verify that the bottom navigation bar is present.
    expect(find.byType(NavigationBar), findsOneWidget);
    
    // Verify that 'Home' and 'Monitoring' are navigation destinations.
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Monitoring'), findsWidgets);
  });
}
