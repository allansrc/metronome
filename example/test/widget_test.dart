// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:metronome_example/main.dart';

void main() {
  testWidgets('shows progressive tempo ramp controls and preview',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Progressive tempo ramp'), findsOneWidget);
    expect(find.text('Start BPM: 80 BPM'), findsOneWidget);
    expect(find.text('Target BPM: 120 BPM'), findsOneWidget);
    expect(find.text('9 stages · 1:19 to target'), findsOneWidget);
    expect(find.text('80 BPM'), findsOneWidget);
  });
}
