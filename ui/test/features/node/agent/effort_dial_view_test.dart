import 'package:egeon_deck/features/node/agent/domain/entities/effort_dial_view.dart';
import 'package:egeon_deck/features/node/agent/presentation/widgets/effort_dial.dart';
import 'package:egeon_deck/theme/app_theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// O seletor de esforço do Swift (`EffortDialTests`), do lado da UI: a regra
/// (auto, "…", nível fora da lista) é do core e tem os testes dela em Rust; aqui
/// fica o que a UI desenha com o estado que o core manda e o gesto que devolve.
const levels = ['low', 'medium', 'high', 'xhigh', 'max'];
const tint = Color(0xFFBF5AF2);

class DialGestures {
  final moves = <int>[];
  var toggles = 0;
}

Future<DialGestures> pumpDial(WidgetTester tester, EffortDialView view) async {
  final gestures = DialGestures();
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      textStyle: AppTheme.textStyle,
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
      home: Align(
        alignment: Alignment.topLeft,
        child: EffortDial(
          view: view,
          tint: tint,
          onMove: gestures.moves.add,
          onToggleAuto: () => gestures.toggles++,
          onSettle: () {},
        ),
      ),
    ),
  );
  return gestures;
}

/// O que o slider desenhou: a marca e se está em auto (apagado).
({int index, bool auto, bool enabled}) slider(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byKey(const ValueKey('effort-slider')),
      matching: find.byType(CustomPaint),
    ),
  );
  final painter = paint.painter! as EffortSliderPainter;
  return (index: painter.index, auto: painter.auto, enabled: painter.enabled);
}

String label(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('effort-label'))).data!;

Color? labelColor(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('effort-label')))
    .style!
    .color;

/// A pílula "auto" está acesa quando tem fundo.
bool pillLit(WidgetTester tester) {
  final box = tester.widget<Container>(
    find.descendant(
      of: find.byKey(const ValueKey('effort-auto')),
      matching: find.byType(Container),
    ),
  );
  return (box.decoration! as BoxDecoration).color != null;
}

/// O x do centro da marca [index], na janela, para clicar nela.
Offset markCenter(WidgetTester tester, int index) {
  final rect = tester.getRect(find.byKey(const ValueKey('effort-slider')));
  const inset = 6.0;
  final span = EffortDial.sliderWidth - 2 * inset;
  return Offset(
    rect.left + inset + span * index / (levels.length - 1),
    rect.center.dy,
  );
}

void main() {
  testWidgets('testStartsOnTheCurrentLevel: a marca fica no nível que o core '
      'mandou; sem escolha, é o padrão (auto, sem texto)', (tester) async {
    await pumpDial(
      tester,
      const EffortDialView(
        levels: levels,
        markIndex: 2,
        auto: false,
        label: 'high',
      ),
    );
    expect(slider(tester).index, 2);
    expect(label(tester), 'high');
    expect(pillLit(tester), isFalse);

    await pumpDial(
      tester,
      const EffortDialView(levels: levels, markIndex: 0, label: ''),
    );
    await tester.pump();
    expect(label(tester), '');
    expect(slider(tester).auto, isTrue, reason: 'None é o padrão: auto');
    expect(pillLit(tester), isTrue);
  });

  testWidgets('testKeepsAnUnknownCurrentLevel: o nível fora da lista aparece '
      'como o core escreveu', (tester) async {
    await pumpDial(
      tester,
      const EffortDialView(
        levels: levels,
        markIndex: 4,
        auto: false,
        label: 'ultra',
      ),
    );
    expect(label(tester), 'ultra');
    expect(slider(tester).index, 4);
  });

  testWidgets('testAutoShowsTheModelLevelDimmedAndLitPill: em auto a barra '
      'mostra o nível do modelo apagado e a pílula acesa; fixo não é auto', (
    tester,
  ) async {
    await pumpDial(
      tester,
      const EffortDialView(levels: levels, markIndex: 2, label: 'high'),
    );
    expect(slider(tester), (index: 2, auto: true, enabled: true));
    expect(pillLit(tester), isTrue);
    final dimmed = labelColor(tester)!;

    await pumpDial(
      tester,
      const EffortDialView(
        levels: levels,
        markIndex: 2,
        auto: false,
        label: 'high',
      ),
    );
    await tester.pump();
    expect(slider(tester).auto, isFalse);
    expect(pillLit(tester), isFalse);
    expect(
      labelColor(tester)!.a,
      greaterThan(dimmed.a),
      reason: 'fixo é mais claro que auto',
    );
  });

  testWidgets('testTogglingAutoOffKeepsTheLevelTheModelWasUsing: a pílula '
      'devolve a intenção; o core responde com o nível mantido, "…" até '
      'assentar', (tester) async {
    final gestures = await pumpDial(
      tester,
      const EffortDialView(levels: levels, markIndex: 2, label: 'high'),
    );
    await tester.tap(find.byKey(const ValueKey('effort-auto')));
    expect(gestures.toggles, 1);
    expect(gestures.moves, isEmpty, reason: 'a UI não escolhe o nível');

    // O que o core manda em seguida: auto desligado, mesmo nível, por assentar.
    await pumpDial(
      tester,
      const EffortDialView(
        levels: levels,
        markIndex: 2,
        auto: false,
        pending: true,
        label: 'high…',
      ),
    );
    await tester.pump();
    expect(label(tester), 'high…');
    expect(labelColor(tester), tint, reason: 'por assentar, a cor do agente');
    expect(slider(tester), (index: 2, auto: false, enabled: true));
    expect(pillLit(tester), isFalse);
  });

  testWidgets('testTogglingAutoOffWithoutKnownLevelPicksTheMiddle: a marca '
      'vai para onde o core mandou, sem a UI escolher o meio', (tester) async {
    final gestures = await pumpDial(
      tester,
      const EffortDialView(levels: levels, markIndex: 0, label: ''),
    );
    await tester.tap(find.byKey(const ValueKey('effort-auto')));
    expect(gestures.toggles, 1);

    await pumpDial(
      tester,
      const EffortDialView(
        levels: levels,
        markIndex: 2,
        auto: false,
        pending: true,
        label: 'high…',
      ),
    );
    await tester.pump();
    expect(slider(tester).index, 2, reason: 'o do meio de cinco, do core');
    expect(label(tester), 'high…');
  });

  testWidgets('testTogglingAutoOnFromALevel: ligar o auto devolve a intenção; '
      'o core manda a marca do modelo, pílula acesa e "…"', (tester) async {
    final gestures = await pumpDial(
      tester,
      const EffortDialView(
        levels: levels,
        markIndex: 4,
        auto: false,
        label: 'max',
      ),
    );
    await tester.tap(find.byKey(const ValueKey('effort-auto')));
    expect(gestures.toggles, 1);

    await pumpDial(
      tester,
      const EffortDialView(
        levels: levels,
        markIndex: 1,
        pending: true,
        label: 'medium…',
      ),
    );
    await tester.pump();
    expect(slider(tester), (index: 1, auto: true, enabled: true));
    expect(pillLit(tester), isTrue);
    expect(label(tester), 'medium…');
  });

  testWidgets('testTouchingTheSliderLeavesAuto: tocar na barra em auto manda '
      'a marca tocada, mesmo a que já estava', (tester) async {
    final gestures = await pumpDial(
      tester,
      const EffortDialView(levels: levels, markIndex: 2, label: 'high'),
    );
    final gesture = await tester.startGesture(markCenter(tester, 2));
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
    expect(gestures.moves, [2]);

    await pumpDial(
      tester,
      const EffortDialView(
        levels: levels,
        markIndex: 2,
        auto: false,
        label: 'high',
      ),
    );
    await tester.pump();
    expect(slider(tester).auto, isFalse, reason: 'o core tirou do auto');
    expect(pillLit(tester), isFalse);
  });

  testWidgets('testNoEffortModelHasNoAutoPill: sem níveis a barra desliga, '
      'não há pílula e tocar não manda nada', (tester) async {
    final gestures = await pumpDial(
      tester,
      const EffortDialView(label: 'sem esforço'),
    );
    expect(label(tester), 'sem esforço');
    expect(find.byKey(const ValueKey('effort-auto')), findsNothing);
    expect(slider(tester).enabled, isFalse);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('effort-slider'))),
    );
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
    expect(gestures.moves, isEmpty);
  });
}
