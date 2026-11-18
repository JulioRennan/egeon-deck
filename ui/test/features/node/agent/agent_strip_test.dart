import 'package:egeon_deck/features/node/agent/domain/entities/agent_status.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/effort_dial_view.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/model_choice.dart';
import 'package:egeon_deck/features/node/agent/presentation/widgets/agent_accessory.dart';
import 'package:egeon_deck/features/node/agent/presentation/widgets/effort_dial.dart';
import 'package:egeon_deck/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_agent_repository.dart';
import '../../../support/inject_fakes.dart';

Future<FakeAgentRepository> pumpStrip(
  WidgetTester tester, {
  FakeAgentRepository? repository,
  void Function(VoidCallback)? onRequestClear,
}) async {
  final repo = repository ?? FakeAgentRepository();
  injectFakes(agent: (_) => repo);
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

String label(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('effort-label'))).data!;

/// O estado que o core mandaria com o seletor numa certa situação.
AgentStatus withDial(EffortDialView dial) => AgentStatus(
  modelTitle: FakeAgentRepository.sample.modelTitle,
  models: FakeAgentRepository.sample.models,
  offersModel: true,
  dial: dial,
  ultracode: FakeAgentRepository.sample.ultracode,
  context: FakeAgentRepository.sample.context,
);

const levels = ['low', 'medium', 'high', 'xhigh', 'max'];

void main() {
  testWidgets('mostra modelo, esforço como o core mandou, contexto e limpar', (
    tester,
  ) async {
    await pumpStrip(tester);
    expect(find.text('Opus 5.5'), findsOneWidget);
    expect(label(tester), 'medium');
    expect(find.text('18%'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-clear')), findsOneWidget);
    expect(find.byKey(const ValueKey('ultracode')), findsOneWidget);
  });

  testWidgets('o texto e a marca vêm do core: a UI não calcula "…"', (
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
    expect(label(tester), 'max…');
  });

  testWidgets(
    'modelo sem esforço: o core manda sem níveis e o seletor se desliga',
    (tester) async {
      final repo = await pumpStrip(tester);
      repo.push(withDial(const EffortDialView(label: 'sem esforço')));
      await tester.pump();
      await tester.pump();
      expect(label(tester), 'sem esforço');
      expect(find.byKey(const ValueKey('effort-auto')), findsNothing);
      final slider = tester.getCenter(
        find.byKey(const ValueKey('effort-slider')),
      );
      final gesture = await tester.startGesture(slider);
      await gesture.up();
      expect(repo.choices, isEmpty);
    },
  );

  testWidgets(
    'clicar numa marca devolve a intenção; assentar só depois da pausa',
    (tester) async {
      final repo = await pumpStrip(tester);
      final rect = tester.getRect(find.byKey(const ValueKey('effort-slider')));

      final gesture = await tester.startGesture(
        Offset(rect.right - 7, rect.center.dy),
      );
      await gesture.up();
      await tester.pump();
      expect((repo.choices.single as EffortMove).index, 4);

      // O core responde com a escolha por assentar; só então a UI conta o tempo.
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
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo.choices.whereType<EffortSettle>(), isEmpty);
      await tester.pump(const Duration(milliseconds: 600));
      expect(repo.choices.whereType<EffortSettle>(), hasLength(1));
    },
  );

  testWidgets('sem nada por assentar, a pausa não manda nada', (tester) async {
    final repo = await pumpStrip(tester);
    final rect = tester.getRect(find.byKey(const ValueKey('effort-slider')));
    final gesture = await tester.startGesture(
      Offset(rect.left + 7, rect.center.dy),
    );
    await gesture.up();
    // O core nunca marcou pendente (escolheu o que já valia).
    await tester.pump(const Duration(seconds: 2));
    expect(repo.choices.whereType<EffortSettle>(), isEmpty);
  });

  testWidgets('segurando o botão, a escolha não assenta', (tester) async {
    final repo = await pumpStrip(tester);
    repo.push(
      withDial(
        const EffortDialView(
          levels: levels,
          markIndex: 0,
          auto: false,
          pending: true,
          label: 'low…',
        ),
      ),
    );
    await tester.pump();
    final rect = tester.getRect(find.byKey(const ValueKey('effort-slider')));
    final gesture = await tester.startGesture(
      Offset(rect.left + 7, rect.center.dy),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(
      repo.choices.whereType<EffortSettle>(),
      isEmpty,
      reason: 'reiniciar no meio do arrasto mataria o slider',
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.choices.whereType<EffortSettle>(), hasLength(1));
  });

  testWidgets('"auto" devolve a intenção de alternar', (tester) async {
    final repo = await pumpStrip(tester);
    await tester.tap(find.byKey(const ValueKey('effort-auto')));
    await tester.pump();
    expect(repo.choices.single, isA<EffortToggleAuto>());
  });

  testWidgets('rolar sobre o slider manda a marca vizinha', (tester) async {
    final repo = await pumpStrip(tester);
    final center = tester.getCenter(
      find.byKey(const ValueKey('effort-slider')),
    );
    final mouse = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(mouse.hover(center));
    // 14 pontos de trackpad para cima = um nível acima da marca que o core
    // mostra (1): a UI não guarda marca própria.
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -14)));
    await tester.pump();
    expect(repo.choices.whereType<EffortMove>().map((m) => m.index), [2]);

    repo.push(
      withDial(
        const EffortDialView(
          levels: levels,
          markIndex: 2,
          auto: false,
          pending: true,
          label: 'high…',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -14)));
    await tester.pump();
    expect(repo.choices.whereType<EffortMove>().map((m) => m.index), [2, 3]);
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

  testWidgets('o modelo escolhido sai do menu', (tester) async {
    final repo = await pumpStrip(tester);
    await tester.tap(find.byKey(const ValueKey('model-picker')));
    await tester.pump();
    expect(find.text('Sonnet 5.5'), findsOneWidget);
    expect(find.text('padrão do CLI'), findsOneWidget);
    await tester.tap(find.text('Sonnet 5.5'));
    await tester.pump();
    expect((repo.choices.single as ModelPick).model, 'claude-sonnet-5-5');
  });

  testWidgets('ultracode e limpar passam pelo core; limpar pede confirmação', (
    tester,
  ) async {
    VoidCallback? confirm;
    final repo = await pumpStrip(tester, onRequestClear: (c) => confirm = c);
    await tester.tap(find.byKey(const ValueKey('ultracode')));
    await tester.pump();
    expect((repo.choices.single as UltracodePick).on, isTrue);

    await tester.tap(find.byKey(const ValueKey('agent-clear')));
    await tester.pump();
    expect(repo.cleared, 0, reason: 'a casca ainda não confirmou');
    confirm!();
    expect(repo.cleared, 1);
  });

  testWidgets('mão em tudo que responde a clique', (tester) async {
    await pumpStrip(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    for (final key in [
      'model-picker',
      'effort-auto',
      'effort-slider',
      'ultracode',
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

  testWidgets('o EffortDial isolado só desenha e devolve gestos', (
    tester,
  ) async {
    final moves = <int>[];
    var settles = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: EffortDial(
            view: const EffortDialView(
              levels: ['low', 'high'],
              markIndex: 0,
              auto: false,
              pending: true,
              label: 'low…',
            ),
            settleDelay: const Duration(milliseconds: 50),
            onMove: moves.add,
            onToggleAuto: () {},
            onSettle: () => settles++,
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byKey(const ValueKey('effort-slider')));
    final g = await tester.startGesture(Offset(rect.right - 7, rect.center.dy));
    await g.up();
    await tester.pump(const Duration(milliseconds: 60));
    expect(moves, [1]);
    expect(settles, 1);
  });
}
