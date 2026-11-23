import 'package:egeon_deck/features/node/agent/domain/entities/model_choice.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/effort_dial_view.dart';
import 'package:egeon_deck/commons/widgets/eg/segmented_control.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_agent_repository.dart';
import 'agent_strip_test.dart' show effortLabel, open, pumpStrip, withDial;

/// O seletor de esforço do Swift (`EffortDialTests`), do lado da UI: a regra
/// (auto, "…", nível fora da lista) é do core e tem os testes dela em Rust; aqui
/// fica o que a UI desenha com o estado que o core manda e o gesto que devolve,
/// agora no menu de esforço do cabeçalho do agente.
const levels = ['low', 'medium', 'high', 'xhigh', 'max'];

/// O que o menu de esforço mostra: a marca, se está em auto (barra apagada e
/// "Automático" marcado).
({int index, bool auto}) menu(WidgetTester tester) {
  final control = tester.widget<SegmentedControl<int>>(
    find.byType(SegmentedControl<int>),
  );
  final dimmed = tester
      .widget<Opacity>(
        find
            .ancestor(
              of: find.byType(SegmentedControl<int>),
              matching: find.byType(Opacity),
            )
            .first,
      )
      .opacity;
  return (index: control.value, auto: dimmed < 1);
}

/// "Automático" está marcado quando a linha desenha o check.
bool autoChecked(WidgetTester tester) => find
    .descendant(
      of: find.byKey(const ValueKey('effort-auto')),
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'EgIcon',
      ),
    )
    .evaluate()
    .isNotEmpty;

Future<void> close(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> send(
  WidgetTester tester,
  FakeAgentRepository repo,
  EffortDialView dial,
) async {
  repo.push(withDial(dial));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('testStartsOnTheCurrentLevel: a marca fica no nível que o core '
      'mandou; sem escolha, é o padrão (auto, sem texto)', (tester) async {
    final repo = await pumpStrip(tester);
    await send(
      tester,
      repo,
      const EffortDialView(
        levels: levels,
        markIndex: 2,
        auto: false,
        label: 'high',
      ),
    );
    expect(effortLabel(tester), 'alto');
    await open(tester, 'effort-picker');
    expect(menu(tester), (index: 2, auto: false));
    expect(autoChecked(tester), isFalse);
    await close(tester);

    await send(
      tester,
      repo,
      const EffortDialView(levels: levels, markIndex: 0, label: ''),
    );
    expect(effortLabel(tester), '—', reason: 'sem texto do core, o traço');
    await open(tester, 'effort-picker');
    expect(menu(tester).auto, isTrue, reason: 'None é o padrão: auto');
    expect(autoChecked(tester), isTrue);
  });

  testWidgets('testKeepsAnUnknownCurrentLevel: o nível fora da lista aparece '
      'como o core escreveu', (tester) async {
    final repo = await pumpStrip(tester);
    await send(
      tester,
      repo,
      const EffortDialView(
        levels: levels,
        markIndex: 4,
        auto: false,
        label: 'ultra',
      ),
    );
    expect(effortLabel(tester), 'ultra');
    await open(tester, 'effort-picker');
    expect(menu(tester).index, 4);
  });

  testWidgets('testAutoShowsTheModelLevelDimmedAndLitPill: em auto a barra '
      'mostra o nível do modelo apagado e o Automático marcado; fixo não é '
      'auto', (tester) async {
    final repo = await pumpStrip(tester);
    await send(
      tester,
      repo,
      const EffortDialView(levels: levels, markIndex: 2, label: 'high'),
    );
    await open(tester, 'effort-picker');
    expect(menu(tester), (index: 2, auto: true));
    expect(autoChecked(tester), isTrue);
    await close(tester);

    await send(
      tester,
      repo,
      const EffortDialView(
        levels: levels,
        markIndex: 2,
        auto: false,
        label: 'high',
      ),
    );
    await open(tester, 'effort-picker');
    expect(menu(tester).auto, isFalse);
    expect(autoChecked(tester), isFalse);
  });

  testWidgets('testTogglingAutoOffKeepsTheLevelTheModelWasUsing: o '
      '"Automático" devolve a intenção; o core responde com o nível mantido, '
      '"…" até assentar', (tester) async {
    final repo = await pumpStrip(tester);
    await send(
      tester,
      repo,
      const EffortDialView(levels: levels, markIndex: 2, label: 'high'),
    );
    await open(tester, 'effort-picker');
    await tester.tap(find.byKey(const ValueKey('effort-auto')));
    await tester.pump();
    expect(repo.choices.whereType<EffortToggleAuto>(), hasLength(1));
    expect(
      repo.choices.whereType<EffortMove>(),
      isEmpty,
      reason: 'a UI não escolhe o nível',
    );
    await tester.pump(const Duration(milliseconds: 300));

    await send(
      tester,
      repo,
      const EffortDialView(
        levels: levels,
        markIndex: 2,
        auto: false,
        pending: true,
        label: 'high…',
      ),
    );
    expect(effortLabel(tester), 'alto…');
    await open(tester, 'effort-picker');
    expect(menu(tester), (index: 2, auto: false));
    expect(autoChecked(tester), isFalse);
  });

  testWidgets('testTogglingAutoOffWithoutKnownLevelPicksTheMiddle: a marca '
      'vai para onde o core mandou, sem a UI escolher o meio', (tester) async {
    final repo = await pumpStrip(tester);
    await send(
      tester,
      repo,
      const EffortDialView(levels: levels, markIndex: 0, label: ''),
    );
    await open(tester, 'effort-picker');
    await tester.tap(find.byKey(const ValueKey('effort-auto')));
    await tester.pump();
    expect(repo.choices.whereType<EffortToggleAuto>(), hasLength(1));
    await tester.pump(const Duration(milliseconds: 300));

    await send(
      tester,
      repo,
      const EffortDialView(
        levels: levels,
        markIndex: 2,
        auto: false,
        pending: true,
        label: 'high…',
      ),
    );
    await open(tester, 'effort-picker');
    expect(menu(tester).index, 2, reason: 'o do meio de cinco, do core');
    expect(effortLabel(tester), 'alto…');
  });

  testWidgets('testTogglingAutoOnFromALevel: ligar o auto devolve a intenção; '
      'o core manda a marca do modelo, Automático marcado e "…"', (
    tester,
  ) async {
    final repo = await pumpStrip(tester);
    await send(
      tester,
      repo,
      const EffortDialView(
        levels: levels,
        markIndex: 4,
        auto: false,
        label: 'max',
      ),
    );
    await open(tester, 'effort-picker');
    await tester.tap(find.byKey(const ValueKey('effort-auto')));
    await tester.pump();
    expect(repo.choices.whereType<EffortToggleAuto>(), hasLength(1));
    await tester.pump(const Duration(milliseconds: 300));

    await send(
      tester,
      repo,
      const EffortDialView(
        levels: levels,
        markIndex: 1,
        pending: true,
        label: 'medium…',
      ),
    );
    await open(tester, 'effort-picker');
    expect(menu(tester), (index: 1, auto: true));
    expect(autoChecked(tester), isTrue);
    expect(effortLabel(tester), 'médio…');
  });

  testWidgets('testTouchingTheSliderLeavesAuto: tocar na barra em auto manda '
      'a marca tocada, mesmo a que já estava', (tester) async {
    final repo = await pumpStrip(tester);
    await send(
      tester,
      repo,
      const EffortDialView(levels: levels, markIndex: 2, label: 'high'),
    );
    await open(tester, 'effort-picker');
    await tester.tap(find.text('alto').last);
    await tester.pump();
    expect(repo.choices.whereType<EffortMove>().map((m) => m.index), [2]);
    expect(repo.choices.whereType<EffortSettle>(), hasLength(1));
    await tester.pump(const Duration(milliseconds: 300));

    await send(
      tester,
      repo,
      const EffortDialView(
        levels: levels,
        markIndex: 2,
        auto: false,
        label: 'high',
      ),
    );
    await open(tester, 'effort-picker');
    expect(menu(tester).auto, isFalse, reason: 'o core tirou do auto');
    expect(autoChecked(tester), isFalse);
  });

  testWidgets('testNoEffortModelHasNoAutoPill: sem níveis o seletor desliga, '
      'não há "Automático" e tocar não manda nada', (tester) async {
    final repo = await pumpStrip(tester);
    await send(tester, repo, const EffortDialView(label: 'sem esforço'));
    expect(effortLabel(tester), 'sem esforço');
    await tester.tap(find.byKey(const ValueKey('effort-picker')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('effort-auto')), findsNothing);
    expect(find.byType(SegmentedControl<int>), findsNothing);
    expect(repo.choices, isEmpty);
  });
}
