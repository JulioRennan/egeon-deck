import 'package:egeon_deck/commons/widgets/count_seal.dart';
import 'package:egeon_deck/core/domain/entities/activity_summary.dart';
import 'package:egeon_deck/features/sidebar/domain/entities/sidebar_bench.dart';
import 'package:egeon_deck/features/sidebar/domain/entities/sidebar_tree.dart';
import 'package:egeon_deck/features/sidebar/domain/repository/sidebar_repository.dart';
import 'package:egeon_deck/features/sidebar/presentation/cubit/sidebar_cubit.dart';
import 'package:egeon_deck/features/sidebar/presentation/page/sidebar_page.dart';
import 'package:egeon_deck/features/sidebar/presentation/widgets/sidebar_panel.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_sidebar_repository.dart';
import '../../support/hand_cursor.dart';
import '../../support/overlay_host.dart';
import '../../support/sidebar_fixtures.dart';

class Calls {
  final log = <String>[];

  SidebarCommands get commands => SidebarCommands(
    onToggleCollapse: () => log.add('collapse'),
    onCreateWorkspace: () => log.add('novo-workspace'),
    onCreateBench: () => log.add('nova-bancada'),
    onCreateBenchFromWorktree: () => log.add('nova-worktree'),
    onCreateBenchIn: (p) => log.add('nova-em:${p.id}'),
    onCreateBenchFromWorktreeIn: (p) => log.add('worktree-em:${p.id}'),
    onEditWorkspace: (ws) => log.add('editar-ws:${ws.id}'),
    onCreateProject: (ws) => log.add('novo-projeto:${ws.id}'),
    onRemoveWorkspace: (ws) => log.add('remover-ws:${ws.id}'),
    onRemoveProject: (ws, p) => log.add('remover-projeto:${ws.id}/${p.id}'),
    onRename: (b) => log.add('renomear:${b.id}'),
    onDuplicateAsWorktree: (b) => log.add('duplicar:${b.id}'),
    onEditRules: (b) => log.add('regras:${b.id}'),
    onRecolor: (b) => log.add('cor:${b.id}:${b.color}'),
    onClear: (b) => log.add('limpar:${b.id}'),
    onRemove: (b) => log.add('remover:${b.id}'),
  );
}

Future<void> mount(
  WidgetTester tester,
  FakeSidebarRepository repository,
  Calls calls, {
  SidebarTree? tree,
  bool compact = false,
}) async {
  await tester.pumpWidget(
    overlayHost(
      RepositoryProvider<SidebarRepository>.value(
        value: repository,
        child: SidebarPage(
          cubit: createSidebarCubit(repository),
          commands: calls.commands,
          compact: compact,
        ),
      ),
      size: const Size(308, 900),
    ),
  );
  repository.push(tree ?? sampleTree());
  await tester.pump();
  await tester.pump();
}

Future<void> rightClick(WidgetTester tester, Finder finder) async {
  await tester.tapAt(tester.getCenter(finder), buttons: kSecondaryButton);
  await tester.pump();
}

void main() {
  late FakeSidebarRepository repository;
  late Calls calls;

  setUp(() {
    repository = FakeSidebarRepository();
    calls = Calls();
  });

  testWidgets('mostra workspaces, projetos e bancadas, com as contagens', (
    tester,
  ) async {
    await mount(tester, repository, calls);

    expect(find.text('Duck'), findsOneWidget);
    expect(find.text('3 bancadas'), findsOneWidget);
    expect(find.text('Casa'), findsOneWidget);
    expect(find.text('0 bancadas'), findsOneWidget);
    expect(find.text('egeon'), findsOneWidget);
    expect(find.text('~/code/egeon'), findsOneWidget);
    expect(find.text('deck'), findsOneWidget);
    expect(find.text('nexus'), findsOneWidget);
    // O projeto guardado só aparece com a gaveta aberta.
    expect(find.text('velho'), findsNothing);
    expect(find.text('1 guardado'), findsOneWidget);
    // A pilha das órfãs mora no fim.
    expect(find.text('Sem projeto'), findsOneWidget);
    expect(find.text('solta'), findsOneWidget);
    expect(find.byType(CountSeal), findsWidgets);
  });

  testWidgets('gaveta aberta mostra os projetos guardados', (tester) async {
    await mount(tester, repository, calls, tree: sampleTree(storedOpen: true));
    expect(find.text('velho'), findsOneWidget);
    expect(find.text('antigo'), findsOneWidget);
  });

  testWidgets('workspace recolhido esconde os projetos', (tester) async {
    await mount(tester, repository, calls, tree: sampleTree(collapsed: true));
    expect(find.text('Duck'), findsOneWidget);
    expect(find.text('egeon'), findsNothing);
    expect(find.text('deck'), findsNothing);
  });

  testWidgets('a bancada do caminho que não existe avisa em vermelho', (
    tester,
  ) async {
    await mount(
      tester,
      repository,
      calls,
      tree: SidebarTree(orphans: [bench('perdida', pathExists: false)]),
    );
    expect(find.text('caminho não existe — ~/code/perdida'), findsOneWidget);
  });

  testWidgets('clicar na bancada a escolhe; no cabeçalho recolhe', (
    tester,
  ) async {
    await mount(tester, repository, calls);

    await tester.tap(find.text('nexus'));
    await tester.tap(find.text('Duck'));
    await tester.tap(find.text('egeon'));
    await tester.tap(find.text('1 guardado'));
    await tester.pump();

    expect(repository.selected, ['nexus']);
    expect(repository.toggledWorkspaces, ['w1']);
    expect(repository.toggledProjects, [('w1', 'p1')]);
    expect(repository.toggledDrawers, ['w1']);
  });

  testWidgets('projeto vazio abre a criação em vez de recolher', (
    tester,
  ) async {
    await mount(tester, repository, calls);
    await tester.tap(find.text('vazio'));
    await tester.pump();
    expect(repository.toggledProjects, isEmpty);
    expect(calls.log, ['worktree-em:p2']);
  });

  testWidgets('menu da bancada tem as sete ações do legado', (tester) async {
    await mount(tester, repository, calls);
    await rightClick(tester, find.text('nexus'));

    for (final label in [
      'Renomear…',
      'Duplicar em nova worktree…',
      'Regras da bancada…',
      'Cor da bancada…',
      'Limpar a bancada…',
      'Remover bancada…',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.text('Limpar a bancada…'));
    await tester.pump();
    expect(calls.log, ['limpar:nexus']);
    expect(
      find.text('Renomear…'),
      findsNothing,
      reason: 'o menu fecha ao escolher',
    );
  });

  testWidgets('menu do workspace e do projeto', (tester) async {
    await mount(tester, repository, calls);

    await rightClick(tester, find.text('Duck'));
    expect(find.text('Novo projeto…'), findsOneWidget);
    await tester.tap(find.text('Editar workspace…'));
    await tester.pump();

    await rightClick(tester, find.text('egeon'));
    expect(find.text('Nova bancada…'), findsOneWidget);
    await tester.tap(find.text('Guardar na gaveta'));
    await tester.pump();

    expect(calls.log, ['editar-ws:w1']);
    expect(repository.stored, [('w1', 'p1', true)]);
  });

  testWidgets('projeto guardado oferece tirar da gaveta', (tester) async {
    await mount(tester, repository, calls, tree: sampleTree(storedOpen: true));
    await rightClick(tester, find.text('velho'));
    await tester.tap(find.text('Tirar da gaveta'));
    await tester.pump();
    expect(repository.stored, [('w1', 'p3', false)]);
  });

  testWidgets('o + abre o menu de criação', (tester) async {
    await mount(tester, repository, calls);
    await tester.tap(find.text('+').first);
    await tester.pump();
    expect(find.text('Novo workspace…'), findsOneWidget);
    await tester.tap(find.text('Nova bancada a partir de worktree…'));
    await tester.pump();
    expect(calls.log, ['nova-worktree']);
  });

  testWidgets('a aba Ativas separa as últimas 24 horas das paradas', (
    tester,
  ) async {
    await mount(tester, repository, calls);
    expect(
      find.textContaining('ÚLTIMAS 24 HORAS', findRichText: true),
      findsNothing,
    );

    await tester.tap(find.text('Ativas'));
    await tester.pump();

    expect(
      find.textContaining('ÚLTIMAS 24 HORAS', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('PARADAS HÁ MAIS DE 24 HORAS', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Duck'), findsNothing, reason: 'a árvore sai de cena');
    expect(find.text('deck'), findsOneWidget);
    expect(find.text('antigo'), findsOneWidget);
  });

  testWidgets('sem nada de pé, a aba Ativas diz como abrir uma', (
    tester,
  ) async {
    await mount(
      tester,
      repository,
      calls,
      tree: SidebarTree(orphans: [bench('a')]),
    );
    await tester.tap(find.text('Ativas'));
    await tester.pump();
    expect(find.textContaining('Nenhuma bancada de pé'), findsOneWidget);
  });

  testWidgets('sem bancada nenhuma, a aba Todas ensina o +', (tester) async {
    await mount(tester, repository, calls, tree: const SidebarTree());
    expect(find.textContaining('Nenhuma bancada.'), findsOneWidget);
  });

  testWidgets('na aba Ativas a linha diz de onde a bancada vem', (
    tester,
  ) async {
    final tree = SidebarTree(
      recent: [
        bench(
          'deck',
          owner: const BenchOwner(id: 'w1', name: 'Duck'),
          project: 'egeon',
        ),
      ],
    );
    await mount(tester, repository, calls, tree: tree);
    await tester.tap(find.text('Ativas'));
    await tester.pump();
    expect(find.text('egeon'), findsOneWidget);
    expect(find.text('D'), findsOneWidget, reason: 'a pastilha do workspace');
  });

  testWidgets('recolhida ao trilho, só ficam as pastilhas e o botão', (
    tester,
  ) async {
    await mount(tester, repository, calls, compact: true);

    expect(find.text('deck'), findsNothing);
    expect(find.text('Duck'), findsNothing);
    expect(find.text('Todas'), findsNothing);
    expect(
      find.text('D'),
      findsWidgets,
      reason: 'inicial de deck e do workspace',
    );

    await tester.tap(find.text('D').first);
    await tester.pump();
    expect(repository.toggledWorkspaces, ['w1']);
  });

  testWidgets('a ordem fixa dos avisos: trabalhando, atenção, pronto', (
    tester,
  ) async {
    final tree = SidebarTree(
      orphans: [
        bench(
          'a',
          activity: const ActivitySummary(working: 2, attention: 1, done: 3),
        ),
      ],
    );
    await mount(tester, repository, calls, tree: tree);
    final text = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .firstWhere((t) => t.contains('●'));
    expect(text.replaceAll(RegExp('[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]'), 'S'), 'S2 ● ●3');
  });

  testWidgets('bancada saindo e bancada subindo se anunciam por extenso', (
    tester,
  ) async {
    final tree = SidebarTree(
      orphans: [
        bench('saindo', removing: true),
        bench('subindo', activity: const ActivitySummary(starting: 1)),
      ],
    );
    await mount(tester, repository, calls, tree: tree);
    expect(find.textContaining('removendo…'), findsOneWidget);
    expect(find.textContaining('preparando…'), findsOneWidget);
  });

  group('arrastar', () {
    Future<TestGesture> grab(WidgetTester tester, String text) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text(text)),
      );
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
      return gesture;
    }

    Rect guide(WidgetTester tester) =>
        tester.getRect(find.byKey(const ValueKey('drop-guide')));

    testWidgets('a bancada cai no fim do projeto, com guia onde vai entrar', (
      tester,
    ) async {
      await mount(tester, repository, calls);
      final nexus = tester.getRect(find.text('nexus'));
      final gesture = await grab(tester, 'deck');

      await gesture.moveTo(Offset(nexus.center.dx, nexus.bottom + 14));
      await tester.pump();
      expect(find.byKey(const ValueKey('drop-guide')), findsOneWidget);
      // A guia é um traço de 2 pontos. Como no legado, ela indexa as linhas
      // com a que está na mão ainda no lugar: descendo uma posição, fica logo
      // acima da linha que vai ficar para trás.
      expect(guide(tester).height, 2);
      expect(guide(tester).top, lessThan(nexus.center.dy));

      await gesture.up();
      await tester.pump();
      expect(repository.moves, ['bench:deck@p1/1']);
      expect(repository.selected, isEmpty, reason: 'arrastar não é clicar');
      expect(find.byKey(const ValueKey('drop-guide')), findsNothing);
    });

    testWidgets('a guia só aparece onde o core diz que cai', (tester) async {
      await mount(tester, repository, calls);
      repository.landing = (kind, item, parent, to) => null;
      final nexus = tester.getRect(find.text('nexus'));
      final gesture = await grab(tester, 'deck');
      await gesture.moveTo(Offset(nexus.center.dx, nexus.bottom + 14));
      await tester.pump();
      expect(repository.plans, isNotEmpty);
      expect(find.byKey(const ValueKey('drop-guide')), findsNothing);

      await gesture.up();
      await tester.pump();
      expect(repository.moves, isEmpty, reason: 'o core recusou o alvo');
    });

    testWidgets(
      'a guia vai onde o core diz (lands), e não onde o ponteiro está',
      (tester) async {
        await mount(tester, repository, calls);
        // O core joga o item para o começo do projeto.
        repository.landing = (kind, item, parent, to) =>
            MoveLanding(parent: parent, to: 0);
        final nexus = tester.getRect(find.text('nexus'));
        final deck = tester.getRect(find.text('deck'));
        final gesture = await grab(tester, 'nexus');
        await gesture.moveTo(Offset(nexus.center.dx, nexus.bottom + 14));
        await tester.pump();
        expect(guide(tester).top, lessThan(deck.center.dy));
        await gesture.up();
      },
    );

    testWidgets('o pedido ao core diz o tipo, o item, o pai e a posição', (
      tester,
    ) async {
      await mount(tester, repository, calls);
      final nexus = tester.getRect(find.text('nexus'));
      final gesture = await grab(tester, 'deck');
      await gesture.moveTo(Offset(nexus.center.dx, nexus.bottom + 14));
      await tester.pump();
      expect(repository.plans.last, 'workbench:deck@p1/1');
      await gesture.up();

      final lid = tester.getRect(find.text('1 guardado'));
      final drag = await grab(tester, 'vazio');
      await drag.moveTo(Offset(lid.center.dx, lid.bottom + 6));
      await tester.pump();
      expect(repository.plans.last, startsWith('store:p2@w1/'));
      await drag.up();
    });

    testWidgets('mexer sem trocar de alvo não repete a pergunta', (
      tester,
    ) async {
      await mount(tester, repository, calls);
      final nexus = tester.getRect(find.text('nexus'));
      final gesture = await grab(tester, 'deck');
      await gesture.moveTo(Offset(nexus.center.dx, nexus.bottom + 14));
      await gesture.moveBy(const Offset(3, 1));
      await gesture.moveBy(const Offset(-2, 0));
      await tester.pump();
      final same = repository.plans.where((p) => p == 'workbench:deck@p1/1');
      expect(same.length, 1);
      await gesture.up();
    });

    testWidgets('a bancada vai para um projeto vazio: guia sob o cabeçalho', (
      tester,
    ) async {
      await mount(tester, repository, calls);
      final empty = tester.getRect(find.text('vazio'));
      final gesture = await grab(tester, 'nexus');
      await gesture.moveTo(empty.center);
      await tester.pump();
      expect(find.byKey(const ValueKey('drop-guide')), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect(repository.moves, ['bench:nexus@p2/0']);
    });

    testWidgets('o projeto solto abaixo da tampa da gaveta é guardado', (
      tester,
    ) async {
      await mount(tester, repository, calls);
      final lid = tester.getRect(find.text('1 guardado'));
      final gesture = await grab(tester, 'vazio');
      await gesture.moveTo(Offset(lid.center.dx, lid.bottom + 6));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(repository.moves, ['project:p2@w1/0/true']);
    });

    testWidgets('o workspace passa pela metade do vizinho para trocar', (
      tester,
    ) async {
      await mount(tester, repository, calls);
      final casa = tester.getRect(find.text('Casa'));
      final gesture = await grab(tester, 'Duck');
      await gesture.moveTo(Offset(casa.center.dx, casa.bottom + 40));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(repository.moves, ['workspace:w1@1']);
    });

    testWidgets('a linha na mão fica esmaecida e volta ao soltar', (
      tester,
    ) async {
      await mount(tester, repository, calls);
      double opacityOf(String text) => tester
          .widget<Opacity>(
            find
                .ancestor(of: find.text(text), matching: find.byType(Opacity))
                .first,
          )
          .opacity;
      expect(opacityOf('deck'), 1);
      final gesture = await grab(tester, 'deck');
      expect(opacityOf('deck'), 0.5);
      await gesture.up();
      await tester.pump();
      expect(opacityOf('deck'), 1);
    });

    testWidgets('desistir no meio não move nada', (tester) async {
      await mount(tester, repository, calls);
      final gesture = await grab(tester, 'deck');
      await gesture.cancel();
      await tester.pump();
      expect(repository.moves, isEmpty);
      expect(find.byKey(const ValueKey('drop-guide')), findsNothing);
    });

    testWidgets('movimento abaixo do limiar continua sendo clique', (
      tester,
    ) async {
      await mount(tester, repository, calls);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('nexus')),
      );
      await gesture.moveBy(const Offset(0, 2));
      await gesture.up();
      await tester.pump();
      expect(repository.selected, ['nexus']);
      expect(repository.moves, isEmpty);
    });

    testWidgets('as órfãs não se arrastam', (tester) async {
      await mount(tester, repository, calls);
      final gesture = await grab(tester, 'solta');
      expect(find.byKey(const ValueKey('drop-guide')), findsNothing);
      await gesture.up();
      await tester.pump();
      expect(repository.moves, isEmpty);
    });
  });

  testWidgets('onde se clica, o ponteiro diz: mão em tudo da barra', (
    tester,
  ) async {
    await mount(tester, repository, calls, tree: sampleTree(storedOpen: true));
    expectHandOnEveryClickable(tester);
    await tester.tap(find.text('Ativas'));
    await tester.pump();
    expectHandOnEveryClickable(tester);
  });

  testWidgets('a página não é dona do cubit: sair da tela não o fecha', (
    tester,
  ) async {
    await mount(tester, repository, calls);
    expect(repository.watchers, 1);
    await tester.pumpWidget(const SizedBox());
    expect(repository.watchers, 1, reason: 'quem fecha é a casca');
  });
}
