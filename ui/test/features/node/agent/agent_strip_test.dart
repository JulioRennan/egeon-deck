import 'package:egeon_deck/features/node/agent/domain/errors/agent_error.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/agent_status.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/context_reading.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/effort_dial_view.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/model_choice.dart';
import 'package:egeon_deck/features/node/agent/presentation/widgets/agent_accessory.dart';
import 'package:egeon_deck/commons/utils/effort_names.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/eg_host.dart';
import '../../../support/fake_agent_repository.dart';
import '../../../support/inject_fakes.dart';

Future<FakeAgentRepository> pumpStrip(
  WidgetTester tester, {
  FakeAgentRepository? repository,
  void Function(VoidCallback)? onRequestClear,
}) async {
  tester.view
    ..physicalSize = const Size(2000, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = repository ?? FakeAgentRepository();
  injectFakes(agent: (_) => repo);
  await tester.pumpWidget(
    egHost(
      size: const Size(2000, 800),
      SizedBox(
        width: 1900,
        height: 36,
        child: AgentAccessory(
          workbenchId: 'bancada',
          nodeId: 'claude',
          onRequestClear: onRequestClear,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return repo;
}

String effortLabel(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('effort-label'))).data!;

Future<void> open(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// O estado que o core mandaria com o seletor numa certa situação.
AgentStatus withDial(EffortDialView dial, {ContextReading? context}) =>
    AgentStatus(
      modelTitle: FakeAgentRepository.sample.modelTitle,
      models: FakeAgentRepository.sample.models,
      offersModel: true,
      dial: dial,
      ultracode: FakeAgentRepository.sample.ultracode,
      context: context ?? FakeAgentRepository.sample.context,
    );

const levels = ['low', 'medium', 'high', 'xhigh', 'max'];

void main() {
  testWidgets('mostra modelo, esforço como o core mandou, contexto e limpar', (
    tester,
  ) async {
    await pumpStrip(tester);
    expect(find.text('modelo'), findsOneWidget);
    expect(find.text('Opus 5.5'), findsOneWidget);
    expect(find.text('esforço'), findsOneWidget);
    expect(effortLabel(tester), 'médio');
    expect(find.text('contexto'), findsOneWidget);
    expect(find.text('18%'), findsOneWidget);
    expect(find.text('ultracode'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-clear')), findsOneWidget);
  });

  testWidgets('a linha tem 36 de altura e o contexto fica na ponta direita', (
    tester,
  ) async {
    await pumpStrip(tester);
    final strip = tester.getRect(find.byType(AgentAccessory));
    final chip = tester.getRect(find.byKey(const ValueKey('context-chip')));
    expect(strip.height, 36);
    expect(chip.right, lessThan(strip.right));
    expect(chip.left, greaterThan(strip.center.dx));
  });

  testWidgets('o texto do esforço vem do core: a UI não calcula "…"', (
    tester,
  ) async {
    final repo = await pumpStrip(tester);
    repo.push(
      withDial(
        const EffortDialView(
          levels: levels,
          markIndex: 4,
          auto: false,
          pending: true,
          label: 'max…',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(effortLabel(tester), 'máximo…');
  });

  testWidgets('modelo sem esforço: o seletor e o auto se desligam', (
    tester,
  ) async {
    final repo = await pumpStrip(tester);
    repo.push(withDial(const EffortDialView(label: 'sem esforço')));
    await tester.pump();
    await tester.pump();
    expect(effortLabel(tester), 'sem esforço');
    await tester.tap(find.byKey(const ValueKey('effort-picker')));
    await tester.pump();
    expect(repo.choices, isEmpty);
    expect(
      find.text('Mais esforço pensa mais antes de agir e gasta mais.'),
      findsNothing,
    );
  });

  testWidgets(
    'o esforço abre com os níveis; escolher manda a marca e assenta',
    (tester) async {
      final repo = await pumpStrip(tester);
      await open(tester, 'effort-picker');
      expect(find.text('Esforço'), findsOneWidget);
      for (final level in levels) {
        expect(find.text(effortName(level)), findsWidgets, reason: level);
      }
      expect(
        find.text('Mais esforço pensa mais antes de agir e gasta mais.'),
        findsOneWidget,
      );
      await tester.tap(find.text('máximo'));
      await tester.pump();
      expect((repo.choices.first as EffortMove).index, 4);
      expect(repo.choices.whereType<EffortSettle>(), hasLength(1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Esforço'), findsNothing, reason: 'o painel fecha');
    },
  );

  testWidgets('não há pastilha "auto" na linha: o Automático mora só no menu '
      'de esforço', (tester) async {
    final repo = await pumpStrip(tester);
    expect(find.text('auto'), findsNothing);
    expect(find.byKey(const ValueKey('effort-auto-chip')), findsNothing);
    expect(find.byKey(const ValueKey('effort-auto')), findsNothing);
    await open(tester, 'effort-picker');
    expect(find.text('Automático'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('effort-auto')));
    await tester.pump();
    expect(repo.choices.single, isA<EffortToggleAuto>());
  });

  testWidgets('o seletor de modelo aparece pelo offers_model do core, não pela '
      'lista', (tester) async {
    final repo = await pumpStrip(tester);
    expect(find.byKey(const ValueKey('model-picker')), findsOneWidget);

    // Lista cheia, mas o core diz que o CLI não escolhe modelo: sem seletor.
    repo.push(
      AgentStatus(
        modelTitle: 'padrão',
        models: FakeAgentRepository.sample.models,
        dial: FakeAgentRepository.sample.dial,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('model-picker')), findsNothing);

    // Lista vazia, mas o core oferece: o seletor aparece.
    repo.push(
      const AgentStatus(
        modelTitle: 'padrão',
        offersModel: true,
        dial: EffortDialView(levels: levels, markIndex: 1, label: 'medium'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('model-picker')), findsOneWidget);
  });

  testWidgets('o menu de modelo marca o atual, avisa que a conversa retoma', (
    tester,
  ) async {
    final repo = await pumpStrip(tester);
    await open(tester, 'model-picker');
    expect(find.text('Modelo'), findsOneWidget);
    expect(find.text('Sonnet 5.5'), findsOneWidget);
    expect(find.text('padrão do CLI'), findsOneWidget);
    expect(
      find.text('Trocar retoma a conversa no novo modelo.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Sonnet 5.5'));
    await tester.pump();
    expect((repo.choices.single as ModelPick).model, 'claude-sonnet-5-5');
  });

  testWidgets('ultracode passa pelo core', (tester) async {
    final repo = await pumpStrip(tester);
    await tester.tap(find.byKey(const ValueKey('ultracode')));
    await tester.pump();
    expect((repo.choices.single as UltracodePick).on, isTrue);
  });

  group('contexto', () {
    testWidgets('a barra é accent e vira attention a partir de 80%', (
      tester,
    ) async {
      final repo = await pumpStrip(tester);
      Color? fill() {
        final box = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byKey(const ValueKey('context-chip')),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((d) => (d.decoration as BoxDecoration).color)
            .whereType<Color>();
        return box.firstWhere(
          (c) =>
              c == EgeonColors.dark.accent || c == EgeonColors.dark.attention,
          orElse: () => const Color(0x00000000),
        );
      }

      expect(fill(), EgeonColors.dark.accent);
      repo.push(
        withDial(
          FakeAgentRepository.sample.dial,
          context: const ContextReading(used: 850000, window: 1000000),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('85%'), findsOneWidget);
      expect(fill(), EgeonColors.dark.attention);
    });

    testWidgets('o painel traz os tokens, o aviso e "Limpar contexto…"', (
      tester,
    ) async {
      VoidCallback? confirm;
      final repo = await pumpStrip(tester, onRequestClear: (c) => confirm = c);
      await open(tester, 'context-chip');
      expect(find.text('Contexto'), findsOneWidget);
      expect(find.text('170K de 1M tokens'), findsOneWidget);
      expect(find.text('Compacta sozinho perto de 90%.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('context-clear')));
      await tester.pump();
      expect(repo.cleared, 0, reason: 'a casca ainda não confirmou');
      confirm!();
      expect(repo.cleared, 1);
    });

    testWidgets('a vassoura também limpa, com confirmação', (tester) async {
      VoidCallback? confirm;
      final repo = await pumpStrip(tester, onRequestClear: (c) => confirm = c);
      await tester.tap(find.byKey(const ValueKey('agent-clear')));
      await tester.pump();
      expect(repo.cleared, 0);
      confirm!();
      expect(repo.cleared, 1);
    });

    testWidgets('sem leitura: travessão e "sem resposta"', (tester) async {
      final repo = await pumpStrip(tester);
      repo.push(
        const AgentStatus(
          modelTitle: 'padrão',
          offersModel: true,
          dial: EffortDialView(levels: levels, markIndex: 1, label: 'medium'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('context-pct')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('context-pct'))).data,
        '—',
      );
    });
  });

  testWidgets('mão em tudo que responde a clique', (tester) async {
    await pumpStrip(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    for (final key in [
      'model-picker',
      'effort-picker',
      'ultracode',
      'context-chip',
      'agent-clear',
    ]) {
      await mouse.moveTo(tester.getCenter(find.byKey(ValueKey(key))));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
        reason: '$key responde a clique',
      );
    }
  });

  test('os níveis de esforço aparecem em português; o desconhecido passa', () {
    expect(levels.map(effortName), [
      'baixo',
      'médio',
      'alto',
      'extra alto',
      'máximo',
    ]);
    expect(effortName('high…'), 'alto…');
    expect(effortName('ultra'), 'ultra');
    expect(effortName(''), '');
  });

  testWidgets(
    'estado que a UI não sabe ler: a faixa mostra o que se sabe, não fica vazia',
    (tester) async {
      final repo = FakeAgentRepository()..failure = const AgentOffline();
      await pumpStrip(tester, repository: repo);
      expect(find.text('esforço'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('agent-clear')),
        findsNothing,
        reason: 'limpar espera o core dizer que dá',
      );

      // O estado bom que vier depois substitui o provisório.
      repo
        ..failure = null
        ..push(FakeAgentRepository.sample);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('model-picker')), findsOneWidget);
    },
  );
}
