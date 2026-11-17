import 'package:egeon_deck/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('o app abre', (tester) async {
    await tester.pumpWidget(const EgeonDeckApp());
    expect(find.byType(WidgetsApp), findsOneWidget);
  });
}
