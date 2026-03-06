import 'package:flutter_test/flutter_test.dart';
import 'package:interequi/main.dart';

void main() {
  testWidgets('Intervaller app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const IntervallerApp());

    // Verify that we are on the main screen.
    expect(find.text('My Training Plans'), findsOneWidget);
  });
}
