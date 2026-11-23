import 'package:egeon_deck/theme/egeon_theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Theme;

/// Hospeda um componente do design system: tema Graphite acima de um
/// `Overlay` (como na casca do app, para as camadas herdarem o tema) e uma
/// janela de tamanho fixo. [reduceMotion] liga "reduzir movimento"; [fill] dá à
/// página a janela inteira (senão ela fica no canto, com a medida que pedir).
Widget egHost(
  Widget child, {
  Size size = const Size(1000, 800),
  bool reduceMotion = false,
  bool fill = false,
}) => KeyedSubtree(
  // O `Overlay` guarda o filho da primeira montagem: a chave nova faz cada
  // `pumpWidget` montar do zero.
  key: UniqueKey(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    // O que o `WidgetsApp` do app dá de graça: Tab, setas e Enter.
    child: Shortcuts(
      shortcuts: WidgetsApp.defaultShortcuts,
      child: Actions(
        actions: WidgetsApp.defaultActions,
        // O clique fora (TapRegion) precisa da superfície que o `WidgetsApp` dá.
        child: TapRegionSurface(
          child: Theme(
            data: EgeonTheme.dark(),
            child: Localizations(
              locale: const Locale('pt'),
              delegates: const [DefaultWidgetsLocalizations.delegate],
              child: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  disableAnimations: reduceMotion,
                ),
                child: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: size.width,
                          height: size.height,
                          child: fill
                              ? child
                              : Align(
                                  alignment: Alignment.topLeft,
                                  child: child,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

/// `testWidgets` com a janela do tamanho que o [egHost] declara (1000×800), para
/// os toques e as posições dos testes baterem com a tela.
void testEg(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await body(tester);
  });
}
