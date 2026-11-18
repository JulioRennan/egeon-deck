import 'package:egeon_deck/core/domain/entities/workbench.dart';
import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_probe.dart';
import 'package:egeon_deck/features/canvas/presentation/cubit/canvas_commands.dart';
import 'package:egeon_deck/features/canvas/presentation/cubit/canvas_cubit.dart';
import 'package:egeon_deck/features/canvas/presentation/widgets/canvas_surface.dart';
import 'package:egeon_deck/features/home/domain/repository/node_repositories.dart';
import 'package:egeon_deck/features/node/web/presentation/cubit/web_capture_registry.dart';
import 'package:egeon_deck/features/node/agent/presentation/widgets/agent_accessory.dart';
import 'package:egeon_deck/features/node/terminal/domain/repository/terminal_repository.dart';
import 'package:egeon_deck/features/node/terminal/presentation/widgets/terminal_body.dart';
import 'package:egeon_deck/features/node/web/presentation/widgets/web_body.dart';
import 'package:egeon_deck/features/canvas/domain/entities/edge_link.dart';
import 'package:egeon_deck/features/canvas/domain/repository/canvas_repository.dart';

import '../../support/in_memory_canvas_repository.dart';

import 'package:egeon_deck/features/home/presentation/widgets/workbench_canvas.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_node_repositories.dart';
import '../../support/fake_terminal_repository.dart';
import '../../support/overlay_host.dart';

const bench = Workbench(id: 'b1', name: 'deck', path: '~/deck');
const link = EdgeLink(a: 'claude', b: 'sh1', aToB: false, bToA: true);

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
    late BuildContext context;
    await tester.pumpWidget(
      overlayHost(
        RepositoryProvider<CanvasRepository>.value(
          value: repository,
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
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
    Future<FakeNodeRepositories> mountCanvas(
      WidgetTester tester,
      Workbench shown,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final nodes = FakeNodeRepositories();
      await tester.pumpWidget(
        overlayHost(
          MultiRepositoryProvider(
            providers: [
              RepositoryProvider<CanvasRepository>.value(
                value: InMemoryCanvasRepository(),
              ),
              RepositoryProvider<TerminalRepository>.value(
                value: FakeTerminalRepository(),
              ),
              RepositoryProvider<NodeRepositories>.value(value: nodes),
              RepositoryProvider<CanvasProbeRegistry>.value(
                value: CanvasProbeRegistry(),
              ),
              RepositoryProvider<CanvasCommands>.value(value: CanvasCommands()),
              RepositoryProvider<WebCaptureRegistry>.value(
                value: WebCaptureRegistry(),
              ),
            ],
            child: WorkbenchCanvas(bench: shown),
          ),
          size: const Size(1400, 900),
        ),
      );
      await tester.pump();
      await tester.pump();
      return nodes;
    }

    testWidgets('cada bancada na tela ganha o seu conjunto de repositórios', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final nodes = FakeNodeRepositories();
      final shown = ValueNotifier(bench);
      await tester.pumpWidget(
        overlayHost(
          MultiRepositoryProvider(
            providers: [
              RepositoryProvider<CanvasRepository>.value(
                value: InMemoryCanvasRepository(),
              ),
              RepositoryProvider<TerminalRepository>.value(
                value: FakeTerminalRepository(),
              ),
              RepositoryProvider<NodeRepositories>.value(value: nodes),
              RepositoryProvider<CanvasProbeRegistry>.value(
                value: CanvasProbeRegistry(),
              ),
              RepositoryProvider<CanvasCommands>.value(value: CanvasCommands()),
              RepositoryProvider<WebCaptureRegistry>.value(
                value: WebCaptureRegistry(),
              ),
            ],
            child: ValueListenableBuilder(
              valueListenable: shown,
              builder: (_, value, _) => WorkbenchCanvas(bench: value),
            ),
          ),
          size: const Size(1400, 900),
        ),
      );
      await tester.pump();
      expect(nodes.benches, ['b1']);

      shown.value = const Workbench(id: 'b2', name: 'outra', path: '~/o');
      await tester.pump();
      await tester.pump();
      expect(nodes.benches, ['b1', 'b2']);
    });

    testWidgets(
      'o inset da barra flutuante chega ao canvas e acompanha a barra',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final inset = ValueNotifier(300.0);
        await tester.pumpWidget(
          overlayHost(
            MultiRepositoryProvider(
              providers: [
                RepositoryProvider<CanvasRepository>.value(
                  value: InMemoryCanvasRepository(),
                ),
                RepositoryProvider<TerminalRepository>.value(
                  value: FakeTerminalRepository(),
                ),
                RepositoryProvider<NodeRepositories>.value(
                  value: FakeNodeRepositories(),
                ),
                RepositoryProvider<CanvasProbeRegistry>.value(
                  value: CanvasProbeRegistry(),
                ),
                RepositoryProvider<CanvasCommands>.value(
                  value: CanvasCommands(),
                ),
                RepositoryProvider<WebCaptureRegistry>.value(
                  value: WebCaptureRegistry(),
                ),
              ],
              child: ValueListenableBuilder(
                valueListenable: inset,
                builder: (_, value, _) =>
                    WorkbenchCanvas(bench: bench, sidebarInset: value),
              ),
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

    testWidgets('terminal, fila e web ganham o corpo certo', (tester) async {
      await mountCanvas(tester, bench);
      expect(find.byType(TerminalBody), findsWidgets);
      expect(find.byType(WebBody), findsOneWidget);
      expect(find.byType(AgentAccessory), findsOneWidget);
    });
  });
}
