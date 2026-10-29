import 'package:flutter_test/flutter_test.dart';
import 'package:product_inventory/main.dart';
import 'package:product_inventory/screen/authenticate/sign_in.dart';

void main() {
  testWidgets('app bootstraps to the sign-in screen for signed-out users',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.byType(SignIn), findsOneWidget);
  });
}
