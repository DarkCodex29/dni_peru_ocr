import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr_example/main.dart';

void main() {
  testWidgets('Example app renders without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const DniPeruOcrExampleApp());
    expect(find.byType(DniPeruOcrExampleApp), findsOneWidget);
  });
}
