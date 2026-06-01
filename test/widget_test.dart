import 'package:flutter_test/flutter_test.dart';
import 'package:trestle_builder/main.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TrestleBuilderApp());
    expect(find.byType(TrestleBuilderApp), findsOneWidget);
  });
}
