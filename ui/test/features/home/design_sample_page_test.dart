import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:egeon_deck/features/home/presentation/page/design_sample_page.dart';
import 'package:egeon_deck/theme/egeon_theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Theme;

void main() {
  testWidgets('a amostra monta sob o EgeonTheme e entrega context.eg', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late EgeonColors seen;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Theme(
          data: EgeonTheme.dark(),
          child: Builder(
            builder: (context) {
              seen = context.eg;
              return const DesignSamplePage();
            },
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(seen.accent, EgeonColors.dark.accent);
    expect(find.text('Painel de vidro'), findsOneWidget);
    expect(find.textContaining('⠋'), findsOneWidget);
  });

  // Os botões carregando giram sem parar: pump com tempo, não pumpAndSettle.
  testWidgets('a galeria abre menu e diálogo (a página tem o seu Overlay)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Theme(data: EgeonTheme.dark(), child: const DesignSamplePage()),
      ),
    );
    await tester.tap(find.text('Menu'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Renomear'), findsOneWidget);
    await tester.tapAt(const Offset(1100, 3900));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Diálogo'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Limpar o contexto?'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
