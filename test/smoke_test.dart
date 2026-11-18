import 'package:flutter_test/flutter_test.dart';

import 'package:andika/app/app.dart';

void main() {
  testWidgets('L\'application démarre et affiche son nom', (tester) async {
    await tester.pumpWidget(const AndikaApp());
    await tester.pump();
    // Sans Android (test sur ordinateur), l'initialisation échoue : le nom et l'erreur s'affichent.
    expect(find.text('Andika'), findsOneWidget);
  });
}
