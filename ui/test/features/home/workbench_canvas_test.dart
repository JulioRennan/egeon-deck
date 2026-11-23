import 'package:egeon_deck/core/domain/entities/workbench.dart';
import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';
import 'package:egeon_deck/features/canvas/presentation/cubit/canvas_cubit.dart';
import 'package:egeon_deck/features/canvas/presentation/widgets/canvas_surface.dart';
import 'package:egeon_deck/features/node/agent/presentation/widgets/agent_accessory.dart';
import 'package:egeon_deck/features/node/terminal/presentation/widgets/terminal_body.dart';
import 'package:egeon_deck/features/node/web/presentation/widgets/web_body.dart';
import 'package:egeon_deck/features/canvas/domain/entities/edge_link.dart';
import 'package:egeon_deck/features/canvas/domain/repository/canvas_repository.dart';

import '../../support/in_memory_canvas_repository.dart';

import 'package:egeon_deck/features/home/presentation/widgets/workbench_canvas.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_agent_repository.dart';
import '../../support/fake_terminal_repository.dart';
import '../../support/fake_web_surface.dart';
import '../../support/in_memory_queue_repository.dart';
import '../../support/in_memory_web_repository.dart';
import '../../support/fake_workbench_repository.dart';
import '../../support/inject_fakes.dart';
import '../../support/eg_host.dart';

const bench = Workbench(id: 'b1', name: 'deck', path: '~/deck');
const link = EdgeLink(a: 'claude', b: 'sh1', aToB: false, bToA: true);

/// O canvas leva o tema do design system (a grade e a barra o leem).
Widget overlayHost(Widget child, {Size size = const Size(1000, 800)}) =>
    egHost(child, size: size, fill: true);

void main() {
  group('o limite da ligação', () {
    test(
      'vazio é sem limite; número vale; lixo não vale; menos de 1 vira 1',
      () {
        expect(parseEdgeLimit(''), (valid: true, limit: null));
        expect(parseEdgeLimit('   '), (valid: true, limit: null));
        expect(parseEdgeLimit('3'), (valid: true, limit: 3));
        expect(parseEdgeLimit(' 5 '), (valid: true, limit: 5));
        expect(parseEdgeLimit('0'), (valid: true, limit: 1));
        expect(parseEdgeLimit('-4'), (valid: true, limit: 1));
        expect(parseEdgeLimit('muitos').valid, isFalse);
        expect(parseEdgeLimit('2,5').valid, isFalse);
      },
    );

    test('o título diz o sentido da ligação', () {
      expect(edgeTitle(link), 'sh1 → claude');
      expect(
        edgeTitle(const EdgeLink(a: 'a', b: 'b', aToB: true, bToA: false)),
        'a → b',
      );
      expect(
        edgeTitle(const EdgeLink(a: 'a', b: 'b', aToB: true, bToA: true)),
        'a ↔ b',
      );
    });
  });

  Future<(InMemoryCanvasRepository, BuildContext)> mount(
    WidgetTester tester,
  ) async {
    final repository = InMemoryCanvasRepository();
    injectFakes(canvas: repository);
    late BuildContext context;
    await tester.pumpWidget(
      overlayHost(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    return (repository, context);
  }

  Future<CanvasSnapshot> snapshot(
    WidgetTester tester,
    CanvasRepository repository,
  ) async => (await tester.runAsync(() => repository.watch('b1').first))!;

  testWidgets('o diálogo do limite abre com o valor de hoje e grava o novo', (
    tester,
  ) async {
    final (repository, context) = await mount(tester);
    editEdgeLimit(context, 'b1', link);
    await tester.pump();
    expect(find.text('sh1 → claude'), findsOneWidget);
    expect(find.textContaining('Vazio = sem limite.'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    tester.testTextInput.enterText('7');
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    await tester.pump();

    final links = (await snapshot(tester, repository)).links;
    expect(links.single.maxSends, 7);
  });

  testWidgets('apagar o número tira o limite; lixo não muda nada', (
    tester,
  ) async {
    final (repository, context) = await mount(tester);
    editEdgeLimit(context, 'b1', link);
    await tester.pump();
    tester.testTextInput.enterText('');
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    await tester.pump();
    expect((await snapshot(tester, repository)).links.single.maxSends, isNull);

    editEdgeLimit(context, 'b1', link);
    await tester.pump();
    tester.testTextInput.enterText('abc');
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    await tester.pump();
    expect((await snapshot(tester, repository)).links.single.maxSends, isNull);
  });

  test('o aviso de remover depende do tipo do nó', () {
    CanvasCard card(NodeKind kind) => CanvasCard(
      id: 'x',
      kind: kind,
      frame: const Rect.fromLTWH(0, 0, 10, 10),
    );
    expect(
      removalWarning(card(NodeKind.shell)),
      contains('terminal é encerrado'),
    );
    expect(
      removalWarning(card(NodeKind.agent)),
      contains('terminal é encerrado'),
    );
    expect(removalWarning(card(NodeKind.queue)), contains('tarefas da fila'));
    expect(removalWarning(card(NodeKind.web)), contains('perfil'));
  });

  testWidgets('fechar um nó pergunta antes e só então remove', (tester) async {
    final (repository, context) = await mount(tester);
    final card = (await snapshot(tester, repository)).cards.first;

    confirmRemoveNode(context, bench, card);
    await tester.pump();
    expect(
      find.text('Remover "${card.title}" do bancada deck?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    await tester.pump();
    expect(
      (await snapshot(tester, repository)).cards.map((c) => c.id),
      contains(card.id),
    );

    confirmRemoveNode(context, bench, card);
    await tester.pump();
    await tester.tap(find.text('Remover'));
    await tester.pump();
    await tester.pump();
    expect(
      (await snapshot(tester, repository)).cards.map((c) => c.id),
      isNot(contains(card.id)),
    );
  });

  group('os corpos de cada tipo de nó', () {
    /// Registra os falsos do canvas e devolve as bancadas de cada repositório
    /// de agente pedido.
    final agents = <FakeAgentRepository>[];

    List<String> injectCanvas({FakeWorkbenchRepository? workbenches}) {
      final benches = <String>[];
      agents.clear();
      injectFakes(
        workbenches: workbenches,
        canvas: InMemoryCanvasRepository(),
        terminals: FakeTerminalRepository(),
        agent: (workbenchId) {
          benches.add(workbenchId);
          if (agents.isEmpty) agents.add(FakeAgentRepository());
          return agents.first;
        },
        queue: (_) => InMemoryQueueRepository(),
        web: (_) => InMemoryWebRepository(),
        createWebController: (profile, _) => FakeWebSurface(profile),
      );
      return benches;
    }

    Future<void> mountCanvas(
      WidgetTester tester,
      Workbench shown, {
      FakeWorkbenchRepository? workbenches,
    }) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      injectCanvas(workbenches: workbenches);
      await tester.pumpWidget(
        overlayHost(WorkbenchCanvas(bench: shown), size: const Size(1400, 900)),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('os nós de cada bancada falam pelos repositórios dela', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final benches = injectCanvas();
      final shown = ValueNotifier(bench);
      await tester.pumpWidget(
        overlayHost(
          ValueListenableBuilder(
            valueListenable: shown,
            builder: (_, value, _) => WorkbenchCanvas(bench: value),
          ),
          size: const Size(1400, 900),
        ),
      );
      await tester.pump();
      expect(benches.toSet(), {'b1'});

      shown.value = const Workbench(id: 'b2', name: 'outra', path: '~/o');
      await tester.pump();
      await tester.pump();
      expect(benches.toSet(), {'b1', 'b2'});
      expect(benches.last, 'b2');
    });

    testWidgets(
      'o inset da barra flutuante chega ao canvas e acompanha a barra',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        injectCanvas();
        final inset = ValueNotifier(300.0);
        await tester.pumpWidget(
          overlayHost(
            ValueListenableBuilder(
              valueListenable: inset,
              builder: (_, value, _) =>
                  WorkbenchCanvas(bench: bench, sidebarInset: value),
            ),
            size: const Size(1400, 900),
          ),
        );
        await tester.pump();
        await tester.pump();
        double left() => tester
            .element(find.byType(CanvasSurface))
            .read<CanvasCubit>()
            .visibleInsets
            .left;
        expect(left(), 300);

        inset.value = 100;
        await tester.pump();
        expect(left(), 100, reason: 'recolher a barra muda o enquadramento');
      },
    );

    testWidgets('limpar a conversa do agente pergunta antes', (tester) async {
      await mountCanvas(tester, bench);
      await tester.tap(find.byKey(const ValueKey('agent-clear')));
      await tester.pump();
      expect(find.text('Limpar o contexto de claude?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      expect(agents.single.cleared, 0, reason: 'cancelar não limpa');

      await tester.tap(find.byKey(const ValueKey('agent-clear')));
      await tester.pump();
      await tester.tap(find.text('Limpar'));
      await tester.pump();
      await tester.pump();
      expect(agents.single.cleared, 1);
    });

    testWidgets('worktree de um terminal: o formulário dele reaponta só ele', (
      tester,
    ) async {
      final workbenches = FakeWorkbenchRepository();
      await mountCanvas(tester, bench, workbenches: workbenches);
      final button = find.descendant(
        of: find.byKey(const ValueKey('card-sh1')),
        matching: find.byKey(const ValueKey('card-worktree')),
      );
      await tester.tap(button);
      await tester.pump();
      await tester.pump();
      expect(find.text('Worktree para "sh1"'), findsOneWidget);
      expect(find.textContaining('sai de ~/projeto'), findsOneWidget);
      expect(workbenches.log, contains('worktree_info:b1/sh1'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(workbenches.planned, contains('main-2'));

      await tester.tap(find.text('Abrir'));
      await tester.pump();
      await tester.pump();
      expect(workbenches.log.where((e) => e.startsWith('worktree:')), [
        'worktree:b1/sh1:main-2:new_workbench:{}',
      ]);
    });

    testWidgets('só terminal abre pasta: web e fila não ganham worktree', (
      tester,
    ) async {
      await mountCanvas(tester, bench);
      expect(
        find.byKey(const ValueKey('card-worktree')),
        findsNWidgets(2),
        reason: 'o shell e o agente da bancada de exemplo',
      );
    });

    testWidgets('terminal, fila e web ganham o corpo certo', (tester) async {
      await mountCanvas(tester, bench);
      expect(find.byType(TerminalBody), findsWidgets);
      expect(find.byType(WebBody), findsOneWidget);
      expect(find.byType(AgentAccessory), findsOneWidget);
    });
  });
}
