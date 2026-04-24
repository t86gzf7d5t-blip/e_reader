import 'package:flutter_test/flutter_test.dart';
import 'package:e_reader/main.dart';

void main() {
  testWidgets('App launches and shows home screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const EReaderApp());
    await tester.pumpAndSettle();

    expect(find.text('Storytime!'), findsOneWidget);
    expect(find.text('Start Reading'), findsOneWidget);
  });
}
