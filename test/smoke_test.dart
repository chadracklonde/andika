import 'package:flutter_test/flutter_test.dart';

import 'package:andika/app/app.dart';

void main() {
  testWidgets('L\'application démarre et affiche son nom', (tester) async {
    await tester.pumpWidget(const AndikaApp());
    expect(find.text('Andika'), findsOneWidget);
  });
}
