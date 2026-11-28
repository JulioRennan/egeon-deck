import 'package:egeon_deck/commons/widgets/eg/spinner.dart';
import 'package:egeon_deck/core/adapters/injector.dart';
import 'package:egeon_deck/core/domain/entities/activity_summary.dart';
import 'package:egeon_deck/features/sidebar/domain/entities/sidebar_bench.dart';
import 'package:egeon_deck/features/sidebar/domain/entities/sidebar_tree.dart';
import 'package:egeon_deck/features/sidebar/domain/repository/sidebar_repository.dart'
    show MoveLanding;
import 'package:egeon_deck/features/sidebar/presentation/cubit/sidebar_cubit.dart';
import 'package:egeon_deck/features/sidebar/presentation/page/sidebar_page.dart';
import 'package:egeon_deck/features/sidebar/presentation/widgets/sidebar_commands.dart';
import 'package:egeon_deck/features/sidebar/presentation/widgets/sidebar_header.dart';
import 'package:egeon_deck/features/usage/domain/entities/usage_view.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';
import '../../support/fake_sidebar_repository.dart';
import '../../support/fake_usage_repository.dart';
import '../../support/hand_cursor.dart';
import '../../support/inject_fakes.dart';
import '../../support/sidebar_fixtures.dart';

class Calls {
  final log = <String>[];

  SidebarCommands get commands => SidebarCommands(
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
    onSaveAsTemplate: (b) => log.add('template:${b.id}'),
    onCopyPath: (p) => log.add('copiar:${p.path}'),
  );
}

Future<SidebarCubit> mount(
  WidgetTester tester,
  FakeSidebarRepository repository,
  Calls calls, {
  SidebarTree? tree,
  FakeUsageRepository? usage,
}) async {
  tester.view.physicalSize = const Size(340, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  injectFakes(sidebar: repository, usage: usage);
  late SidebarCubit cubit;
  await tester.pumpWidget(
    egHost(
      fill: true,
      size: const Size(340, 900),
      BlocProvider(
        create: (_) => cubit = inject<SidebarCubit>(),
        child: SidebarPage(commands: calls.commands),
      ),
    ),
  );
  repository.push(tree ?? sampleTree());
  await tester.pump();
  await tester.pump();
  return cubit;
}

/// O botão pelo rótulo que ele dá ao leitor de tela (o `Semantics` do
/// controle, que existe mesmo com o botão transparente).
Finder byLabel(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

/// Abre o menu ⋯ clicando com o botão direito no texto da linha.
Future<void> rightClick(WidgetTester tester, Finder finder) async {
  await tester.tapAt(tester.getCenter(finder), buttons: kSecondaryButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> chooseMenu(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
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
    expect(find.text('deck'), findsOneWidget);
    expect(find.text('nexus'), findsOneWidget);
    // O projeto guardado só aparece com a gaveta aberta.
    expect(find.text('velho'), findsNothing);
    expect(find.text('Gaveta · 1'), findsOneWidget);
    expect(find.text('Gaveta vazia'), findsOneWidget, reason: 'a de Casa');
    // A pilha das órfãs mora no fim.
    expect(find.text('Sem projeto'), findsOneWidget);
    expect(find.text('solta'), findsOneWidget);
  });

  testWidgets('o cabeçalho conta as bancadas das duas visões', (tester) async {
    await mount(tester, repository, calls);
    expect(find.text('Todas'), findsOneWidget);
    expect(find.text('Ativas'), findsOneWidget);
    // sampleTree: 4 bancadas (3 em projeto e 1 órfã); 2 de pé.
    final header = find.byType(SidebarHeader);
    expect(
      find.descendant(of: header, matching: find.text('4')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: header, matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('a gaveta aberta mostra os projetos guardados', (tester) async {
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
    final text = tester.widget<Text>(
      find.text('caminho não existe — ~/code/perdida'),
    );
    expect(text.style!.color, EgeonColors.dark.danger);
  });

  testWidgets('clicar escolhe a bancada e recolhe os grupos', (tester) async {
    await mount(tester, repository, calls);
    await tester.tap(find.text('nexus'));
    await tester.tap(find.text('Duck'));
    await tester.tap(find.text('egeon'));
    await tester.tap(find.text('Gaveta · 1'));
    await tester.pump();

    expect(repository.selected, ['nexus']);
    expect(repository.toggledWorkspaces, ['w1']);
    expect(repository.toggledProjects, [('w1', 'p1')]);
    expect(repository.toggledDrawers, ['w1']);
  });

  testWidgets('projeto vazio cria a bancada em vez de recolher', (
    tester,
  ) async {
    await mount(tester, repository, calls);
    await tester.tap(find.text('vazio'));
    await tester.pump();
    expect(repository.toggledProjects, isEmpty);
    expect(calls.log, ['nova-em:p2']);
  });

  testWidgets('o + do projeto cria bancada ali (aparece no hover)', (
    tester,
  ) async {
    await mount(tester, repository, calls);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('egeon')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(byLabel('Nova bancada neste projeto').first);
    await tester.pump();
    expect(calls.log, ['nova-em:p1']);
    await mouse.removePointer();
  });

  testWidgets('o custo da bancada vai na ponta da linha; sem consumo, nada', (
    tester,
  ) async {
    final usage = FakeUsageRepository(
      const UsageView(pill: UsagePillView(text: 'US\$ 0,00', empty: true)),
    );
    await mount(tester, repository, calls, usage: usage);
    expect(usage.watched, isNotEmpty, reason: 'cada linha assina a sua');
    expect(find.text('US\$ 0,00'), findsNothing);

    usage.push(
      const UsageView(
        pill: UsagePillView(text: 'US\$ 1,23', tooltip: 'Consumo da bancada'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('US\$ 1,23'), findsWidgets);
  });

  group('estado da bancada', () {
    Future<void> show(WidgetTester tester, SidebarBench b) =>
        mount(tester, repository, calls, tree: SidebarTree(orphans: [b]));

    testWidgets('esperando você: ponto laranja e texto', (tester) async {
      await show(
        tester,
        bench('a', activity: const ActivitySummary(attention: 2, working: 1)),
      );
      final text = tester.widget<Text>(find.text('2 esperando você'));
      expect(text.style!.color, EgeonColors.dark.attention);
    });

    testWidgets('terminou: aparece na bancada de fora', (tester) async {
      await show(tester, bench('a', activity: const ActivitySummary(done: 1)));
      expect(find.text('1 terminou'), findsOneWidget);
    });

    testWidgets('terminou: aparece também na bancada que está na tela', (
      tester,
    ) async {
      await show(
        tester,
        bench('a', selected: true, activity: const ActivitySummary(done: 1)),
      );
      expect(find.text('1 terminou'), findsOneWidget);
      expect(find.text('Parada'), findsNothing);
    });

    testWidgets('trabalhando: spinner e a contagem', (tester) async {
      await show(
        tester,
        bench('a', activity: const ActivitySummary(working: 3)),
      );
      expect(find.text('3 em trabalho'), findsOneWidget);
      expect(find.byType(Spinner), findsOneWidget);
    });

    testWidgets('parada: ponto vazado e "Parada"', (tester) async {
      await show(tester, bench('a'));
      expect(find.text('Parada'), findsOneWidget);
    });

    testWidgets('saindo e subindo se anunciam por extenso', (tester) async {
      await mount(
        tester,
        repository,
        calls,
        tree: SidebarTree(
          orphans: [
            bench('saindo', removing: true),
            bench('subindo', activity: const ActivitySummary(starting: 1)),
          ],
        ),
      );
      expect(find.text('removendo…'), findsOneWidget);
      expect(find.text('preparando…'), findsOneWidget);
    });

    testWidgets('a selecionada leva o traço e o nome em 600 na cor dela', (
      tester,
    ) async {
      await mount(tester, repository, calls);
      final name = tester.widget<Text>(find.text('deck'));
      expect(name.style!.fontWeight, FontWeight.w600);
      expect(name.style!.color, EgeonColors.dark.idSlate);
      final other = tester.widget<Text>(find.text('nexus'));
      expect(other.style!.fontWeight, FontWeight.w500);
    });
  });

  group('menus ⋯', () {
    testWidgets('bancada: o que o app sabe fazer, com o cabeçalho', (
      tester,
    ) async {
      await mount(tester, repository, calls);
      await rightClick(tester, find.text('nexus'));

      for (final label in [
        'Abrir',
        'Renomear…',
        'Mudar cor…',
        'Salvar como template',
        'Regras da bancada…',
        'Nova bancada numa worktree',
        'Duplicar em nova worktree…',
        'Limpar bancada…',
        'Remover bancada…',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // O que o app ainda não faz não aparece.
      expect(find.text('Encerrar terminais'), findsNothing);

      await chooseMenu(tester, 'Limpar bancada…');
      expect(calls.log, ['limpar:nexus']);
      expect(find.text('Renomear…'), findsNothing, reason: 'fecha ao escolher');
    });

    testWidgets('bancada: abrir, renomear, cor, template e worktree', (
      tester,
    ) async {
      await mount(tester, repository, calls);
      for (final label in [
        'Abrir',
        'Renomear…',
        'Mudar cor…',
        'Salvar como template',
        'Nova bancada numa worktree',
        'Regras da bancada…',
        'Duplicar em nova worktree…',
        'Remover bancada…',
      ]) {
        await rightClick(tester, find.text('nexus'));
        await chooseMenu(tester, label);
      }
      expect(repository.selected, ['nexus']);
      expect(calls.log, [
        'renomear:nexus',
        'cor:nexus:pink',
        'template:nexus',
        'worktree-em:p1',
        'regras:nexus',
        'duplicar:nexus',
        'remover:nexus',
      ]);
    });

    testWidgets('o item de remover é o único em vermelho (perigo)', (
      tester,
    ) async {
      await mount(tester, repository, calls);
      await rightClick(tester, find.text('nexus'));
      final remove = tester.widget<Text>(find.text('Remover bancada…'));
      expect(remove.style!.color, EgeonColors.dark.danger);
      final rename = tester.widget<Text>(find.text('Renomear…'));
      expect(rename.style!.color, EgeonColors.dark.textPrimary);
    });

    testWidgets('workspace e projeto', (tester) async {
      await mount(tester, repository, calls);

      await rightClick(tester, find.text('Duck'));
      expect(find.text('Novo projeto…'), findsOneWidget);
      expect(find.text('Remover workspace…'), findsOneWidget);
      expect(find.text('Recolher tudo'), findsOneWidget);
      await chooseMenu(tester, 'Editar nome e foto…');

      await rightClick(tester, find.text('egeon'));
      expect(find.text('Nova bancada…'), findsOneWidget);
      expect(find.text('Abrir no Finder'), findsNothing);
      await chooseMenu(tester, 'Copiar caminho');
      await rightClick(tester, find.text('egeon'));
      await chooseMenu(tester, 'Guardar na gaveta');

      expect(calls.log, ['editar-ws:w1', 'copiar:~/code/egeon']);
      expect(repository.stored, [('w1', 'p1', true)]);
    });

    testWidgets('"Recolher tudo" fecha cada projeto aberto, pelo comando de '
        'um só', (tester) async {
      await mount(tester, repository, calls);
      await rightClick(tester, find.text('Duck'));
      await chooseMenu(tester, 'Recolher tudo');
      expect(repository.toggledProjects, [('w1', 'p1'), ('w1', 'p3')]);
      expect(
        repository.toggledProjects.any((t) => t.$2 == 'p2'),
        isFalse,
        reason: 'o vazio não tem o que recolher',
      );
    });

    testWidgets('"Recolher tudo" fica desabilitado sem projeto aberto', (
      tester,
    ) async {
      await mount(
        tester,
        repository,
        calls,
        tree: SidebarTree(
          workspaces: [
            SidebarWorkspace(
              id: 'w1',
              name: 'Duck',
              projects: [
                SidebarProject(
                  id: 'p1',
                  name: 'egeon',
                  path: '~/code/egeon',
                  collapsed: true,
                  benches: [bench('deck')],
                ),
              ],
            ),
          ],
        ),
      );
      await rightClick(tester, find.text('Duck'));
      await tester.tap(find.text('Recolher tudo'));
      await tester.pump();
      expect(repository.toggledProjects, isEmpty);
    });

    testWidgets('projeto guardado oferece tirar da gaveta', (tester) async {
      await mount(
        tester,
        repository,
        calls,
        tree: sampleTree(storedOpen: true),
      );
      await rightClick(tester, find.text('velho'));
      await chooseMenu(tester, 'Tirar da gaveta');
      expect(repository.stored, [('w1', 'p3', false)]);
    });

    testWidgets('o ⋯ aparece no hover e abre o mesmo menu', (tester) async {
      await mount(tester, repository, calls);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Duck')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(byLabel('Mais ações').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Novo projeto…'), findsOneWidget);
      await mouse.removePointer();
    });

    testWidgets('"Novo" abre o menu de criação', (tester) async {
      await mount(tester, repository, calls);
      await tester.tap(find.bySemanticsLabel('Novo'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Novo workspace…'), findsOneWidget);
      await chooseMenu(tester, 'Nova bancada a partir de worktree…');
      expect(calls.log, ['nova-worktree']);
    });
  });

  group('visão Ativas', () {
    testWidgets('separa as últimas 24 horas das paradas', (tester) async {
      await mount(tester, repository, calls);
      expect(
        find.textContaining('Últimas 24 horas', findRichText: true),
        findsNothing,
      );

      await tester.tap(find.text('Ativas'));
      await tester.pump();

      expect(
        find.textContaining('Últimas 24 horas', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Paradas há mais de 24 horas', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Duck'), findsNothing, reason: 'a árvore sai de cena');
      expect(find.text('deck'), findsOneWidget);
      expect(find.text('antigo'), findsOneWidget);
    });

    testWidgets('sem nada de pé, diz como abrir uma', (tester) async {
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

    testWidgets('a linha diz de onde a bancada vem', (tester) async {
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
      expect(find.text('egeon'), findsOneWidget, reason: 'o projeto');
      expect(
        find.byKey(const ValueKey('bench-origin-initial')),
        findsOneWidget,
        reason: 'a inicial do workspace',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('bench-origin-initial')))
            .data,
        'D',
      );
    });

    testWidgets('o menu da Ativas não oferece worktree no projeto', (
      tester,
    ) async {
      await mount(
        tester,
        repository,
        calls,
        tree: SidebarTree(recent: [bench('deck')]),
      );
      await tester.tap(find.text('Ativas'));
      await tester.pump();
      await rightClick(tester, find.text('deck'));
      expect(find.text('Renomear…'), findsOneWidget);
      expect(find.text('Nova bancada numa worktree'), findsNothing);
    });
  });

  testWidgets('sem bancada nenhuma, a visão Todas ensina o +', (tester) async {
    await mount(tester, repository, calls, tree: const SidebarTree());
    expect(find.textContaining('Nenhuma bancada.'), findsOneWidget);
  });

  group('filtros', () {
    Future<void> openFilters(WidgetTester tester) async {
      await tester.tap(byLabel('Filtros').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    SidebarTree attentionTree() => SidebarTree(
      workspaces: [
        SidebarWorkspace(
          id: 'w1',
          name: 'Duck',
          projects: [
            SidebarProject(
              id: 'p1',
              name: 'egeon',
              benches: [
                bench('pede', activity: const ActivitySummary(attention: 1)),
                bench('quieta'),
              ],
            ),
          ],
        ),
        const SidebarWorkspace(id: 'w2', name: 'Casa'),
      ],
    );

    testWidgets('o painel traz Mostrar, Agrupar por e Workspace', (
      tester,
    ) async {
      await mount(tester, repository, calls, tree: attentionTree());
      await openFilters(tester);
      for (final t in [
        'Mostrar',
        'Esperando você',
        'Em trabalho',
        'Terminou',
        'Paradas',
        'Agrupar por',
        'Workspace › projeto',
        'Última atividade',
        'Todos os workspaces',
      ]) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(find.textContaining('Recolher paradas'), findsNothing);
    });

    testWidgets('marcar "Esperando você" filtra a árvore; Limpar volta', (
      tester,
    ) async {
      await mount(tester, repository, calls, tree: attentionTree());
      await openFilters(tester);
      await tester.tap(find.text('Esperando você'));
      await tester.pump();
      expect(find.text('pede'), findsOneWidget);
      expect(find.text('quieta'), findsNothing);
      expect(find.text('1 filtro ligado'), findsOneWidget);

      // O resumo fica abaixo do cabeçalho e serve com o painel fechado.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Limpar'));
      await tester.pump();
      expect(find.text('quieta'), findsOneWidget);
      expect(find.text('1 filtro ligado'), findsNothing);
    });

    testWidgets('"Paradas" mostra o que não trabalha, não pede nem terminou', (
      tester,
    ) async {
      await mount(tester, repository, calls, tree: attentionTree());
      await openFilters(tester);
      await tester.tap(find.text('Paradas'));
      await tester.pump();
      expect(find.text('quieta'), findsOneWidget);
      expect(find.text('pede'), findsNothing);
    });

    testWidgets('escolher um workspace deixa só ele', (tester) async {
      await mount(tester, repository, calls, tree: attentionTree());
      await openFilters(tester);
      await tester.tap(find.text('Casa').last);
      await tester.pump();
      expect(find.text('pede'), findsNothing);
      expect(find.text('Nenhuma bancada com esses filtros.'), findsOneWidget);
    });

    testWidgets('"Última atividade" troca para a visão Ativas', (tester) async {
      await mount(tester, repository, calls);
      await openFilters(tester);
      await tester.tap(find.text('Última atividade'));
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('Últimas 24 horas', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('busca', () {
    testWidgets('abre pelo botão, filtra por bancada, projeto e workspace', (
      tester,
    ) async {
      await mount(tester, repository, calls);
      await tester.tap(find.bySemanticsLabel('Buscar bancada ou projeto'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Buscar bancada ou projeto'), findsOneWidget);

      tester.testTextInput.enterText('nex');
      await tester.pump();
      expect(find.text('nexus'), findsOneWidget);
      expect(find.text('deck'), findsNothing);
      expect(find.text('egeon'), findsOneWidget, reason: 'o projeto da achada');

      tester.testTextInput.enterText('egeon');
      await tester.pump();
      expect(find.text('deck'), findsOneWidget, reason: 'o projeto traz tudo');
      expect(find.text('nexus'), findsOneWidget);

      tester.testTextInput.enterText('duck');
      await tester.pump();
      expect(
        find.text('egeon'),
        findsOneWidget,
        reason: 'o workspace traz tudo',
      );
      expect(find.text('solta'), findsNothing);
    });

    testWidgets('sem resultado: a frase e "Limpar filtros"', (tester) async {
      await mount(tester, repository, calls);
      await tester.tap(find.bySemanticsLabel('Buscar bancada ou projeto'));
      await tester.pump();
      await tester.pump();
      tester.testTextInput.enterText('zzz');
      await tester.pump();
      expect(find.text('Nenhuma bancada com esses filtros.'), findsOneWidget);
      await tester.tap(find.text('Limpar filtros'));
      await tester.pump();
      expect(find.text('deck'), findsOneWidget);
    });

    testWidgets('Esc e o ✕ fecham a busca e limpam o filtro', (tester) async {
      await mount(tester, repository, calls);
      await tester.tap(find.bySemanticsLabel('Buscar bancada ou projeto'));
      await tester.pump();
      await tester.pump();
      tester.testTextInput.enterText('nex');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('deck'), findsOneWidget);
      expect(find.text('Buscar bancada ou projeto'), findsNothing);
    });

    testWidgets('⌘K (o pedido do cubit) abre a busca com o foco nela', (
      tester,
    ) async {
      final cubit = await mount(tester, repository, calls);
      cubit.requestFind();
      await tester.pump();
      await tester.pump();
      expect(find.text('Buscar bancada ou projeto'), findsOneWidget);
      tester.testTextInput.enterText('nex');
      await tester.pump();
      expect(find.text('deck'), findsNothing);
    });

    testWidgets('um ⌘K de antes da barra existir é atendido ao nascer', (
      tester,
    ) async {
      injectFakes(sidebar: repository);
      final cubit = inject<SidebarCubit>();
      addTearDown(cubit.close);
      cubit.requestFind();
      await tester.pumpWidget(
        egHost(
          fill: true,
          size: const Size(340, 900),
          BlocProvider.value(
            value: cubit,
            child: SidebarPage(commands: calls.commands),
          ),
        ),
      );
      repository.push(sampleTree());
      await tester.pump();
      await tester.pump();
      expect(find.text('Buscar bancada ou projeto'), findsOneWidget);
    });
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

    testWidgets('a órfã se arrasta para um projeto e ganha casa', (
      tester,
    ) async {
      await mount(tester, repository, calls);
      final nexus = tester.getRect(find.text('nexus'));
      final gesture = await grab(tester, 'solta');
      await gesture.moveTo(Offset(nexus.center.dx, nexus.bottom + 14));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(repository.moves.single, startsWith('bench:solta@p1/'));
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

      final lid = tester.getRect(find.text('Gaveta · 1'));
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
      final lid = tester.getRect(find.text('Gaveta · 1'));
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

  testWidgets('a página usa o cubit de cima: sair da tela não o fecha', (
    tester,
  ) async {
    injectFakes(sidebar: repository);
    final cubit = inject<SidebarCubit>();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      egHost(
        fill: true,
        size: const Size(340, 900),
        BlocProvider.value(
          value: cubit,
          child: SidebarPage(commands: calls.commands),
        ),
      ),
    );
    expect(repository.watchers, 1);
    await tester.pumpWidget(const SizedBox());
    expect(repository.watchers, 1, reason: 'quem fecha é a casca');
  });
}
