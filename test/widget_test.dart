// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:StoveMonitorApp/main.dart';

void main() {
  testWidgets('Stove monitor app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const StoveMonitorApp());

    // Verify that our app shows the correct title.
    expect(find.text('Stove Monitor'), findsOneWidget);
    expect(find.text('Ready to check stove status'), findsOneWidget);
    expect(find.text('Check Stove Status'), findsOneWidget);
  });
}
