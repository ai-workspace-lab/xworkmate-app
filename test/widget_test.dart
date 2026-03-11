import 'package:flutter_test/flutter_test.dart';

import 'package:xworkmate/app/app.dart';

void main() {
  testWidgets('renders XWorkmate shell', (WidgetTester tester) async {
    await tester.pumpWidget(const XWorkmateApp());

    expect(find.text('Assistant'), findsWidgets);
    expect(
      find.text('Connect a gateway to start chatting and running tasks.'),
      findsOneWidget,
    );
  });
}
