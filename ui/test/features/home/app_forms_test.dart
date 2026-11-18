import 'package:egeon_deck/core/adapters/path_picker.dart';
import 'package:egeon_deck/features/home/presentation/forms/app_forms.dart';
import 'package:egeon_deck/features/workbench/domain/entities/bench_template.dart';
import 'package:egeon_deck/features/workbench/domain/entities/worktree_info.dart';
import 'package:egeon_deck/features/workbench/domain/entities/worktree_plan.dart';
import 'package:egeon_deck/features/home/presentation/forms/form_request.dart';
import 'package:egeon_deck/features/workbench/domain/entities/removal_plan.dart';
import 'package:egeon_deck/features/workbench/domain/repository/workbench_repository.dart';
import 'package:egeon_deck/features/workspace/domain/repository/workspace_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_path_picker.dart';
import '../../support/fake_workbench_repository.dart';
import '../../support/fake_workspace_repository.dart';
import '../../support/overlay_host.dart';

class Forms {
  final bench = FakeWorkbenchRepository();
  final workspace = FakeWorkspaceRepository();
  final picker = FakePathPicker();
  late BuildContext context;

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    overlayHost(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<WorkbenchRepository>.value(value: bench),
          RepositoryProvider<WorkspaceRepository>.value(value: workspace),
          RepositoryProvider<PathPicker>.value(value: picker),
        ],
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    ),
  );

  Future<void> ask(WidgetTester tester, FormRequest request) async {
    handleForm(context, request);
    await tester.pump();
    await tester.pump();
  }
}

Future<Forms> mount(WidgetTester tester) async {
  final forms = Forms();
  await forms.mount(tester);
  return forms;
}

void main() {
  testWidgets('a cor escolhida na grade vai ao core', (tester) async {
    final f = await mount(tester);
    await f.ask(tester, const RecolorBench('b1', 'deck', current: 'sand'));
    expect(find.text('Cor da bancada'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('swatch-teal')));
    await tester.pump();
    await tester.pump();
    expect(f.bench.log, ['cor:b1:teal']);
  });

  testWidgets('fechar a grade sem escolher não manda nada', (tester) async {
    final f = await mount(tester);
    await f.ask(tester, const RecolorBench('b1', 'deck'));
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    await tester.pump();
    expect(f.bench.log, isEmpty);
  });

  testWidgets('renomear avisa do endereço e só manda se o nome mudou', (
    tester,
  ) async {
    final f = await mount(tester);
    await f.ask(tester, const RenameBench('b1', 'deck'));
    expect(
      find.textContaining('primeira parte do endereço de dispatch'),
      findsOneWidget,
    );
    tester.testTextInput.enterText('deck');
    await tester.pump();
    await tester.tap(find.text('Renomear'));
    await tester.pump();
    await tester.pump();
    expect(f.bench.log, isEmpty, reason: 'mesmo nome: nada a fazer');

    await f.ask(tester, const RenameBench('b1', 'deck'));
    tester.testTextInput.enterText('nexus');
    await tester.pump();
    await tester.tap(find.text('Renomear'));
    await tester.pump();
    await tester.pump();
    expect(f.bench.log, ['renomear:b1:nexus']);
  });

  testWidgets('limpar pergunta antes e diz quantos agentes serão atingidos', (
    tester,
  ) async {
    final f = await mount(tester);
    f.bench.agents = 3;
    await f.ask(tester, const ClearBench('b1', 'deck'));
    expect(find.text('Limpar a bancada "deck"?'), findsOneWidget);
    expect(find.textContaining('em 3 agentes'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    await tester.pump();
    expect(f.bench.log, ['agentes:b1'], reason: 'cancelou: não limpou');

    await f.ask(tester, const ClearBench('b1', 'deck'));
    await tester.tap(find.text('Limpar'));
    await tester.pump();
    await tester.pump();
    expect(f.bench.log.last, 'limpar:b1');
  });

  testWidgets('com um agente só, o texto fica no singular', (tester) async {
    final f = await mount(tester);
    f.bench.agents = 1;
    await f.ask(tester, const ClearBench('b1', 'deck'));
    expect(find.textContaining('em 1 agente —'), findsOneWidget);
  });

  testWidgets('remover bancada viva avisa dos terminais', (tester) async {
    final f = await mount(tester);
    f.bench.plan = const RemovalPlan(live: true);
    await f.ask(tester, const RemoveBench('b1', 'deck'));
    expect(find.text('Remover a bancada "deck"?'), findsOneWidget);
    expect(find.text('Os terminais abertos são encerrados.'), findsOneWidget);
    expect(find.byKey(const ValueKey('option-box')), findsNothing);
    await tester.tap(find.text('Remover'));
    await tester.pump();
    await tester.pump();
    expect(f.bench.log.last, 'remover:b1:false');
  });

  testWidgets('com worktrees só dela, oferece apagá-las do disco', (
    tester,
  ) async {
    final f = await mount(tester);
    f.bench.plan = const RemovalPlan(worktrees: 2);
    await f.ask(tester, const RemoveBench('b1', 'deck'));
    expect(find.text('A bancada sai da lista.'), findsOneWidget);
    expect(find.text('Também apagar as 2 worktrees do disco'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('option-box')));
    await tester.pump();
    await tester.tap(find.text('Remover'));
    await tester.pump();
    await tester.pump();
    expect(f.bench.log.last, 'remover:b1:true');
  });

  testWidgets('cancelar a remoção não remove nada', (tester) async {
    final f = await mount(tester);
    f.bench.plan = const RemovalPlan(worktrees: 1);
    await f.ask(tester, const RemoveBench('b1', 'deck'));
    expect(find.text('Também apagar a worktree do disco'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    await tester.pump();
    expect(f.bench.log, ['plano:b1']);
  });

  testWidgets('a recusa do core aparece com o motivo dele', (tester) async {
    final f = await mount(tester);
    f.bench.refuse = 'A bancada não foi removida: a worktree tem mudanças.';
    await f.ask(tester, const RemoveBench('b1', 'deck'));
    expect(find.text('Não foi possível'), findsOneWidget);
    expect(find.textContaining('a worktree tem mudanças'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(find.text('Não foi possível'), findsNothing);
  });

  testWidgets('as regras abrem com o texto de hoje e salvam o novo', (
    tester,
  ) async {
    final f = await mount(tester);
    f.bench.currentRules = 'peça antes de commitar';
    await f.ask(tester, const EditBenchRules('b1', 'deck'));
    expect(find.text('Regras — deck'), findsOneWidget);
    expect(find.text('peça antes de commitar'), findsOneWidget);

    tester.testTextInput.enterText('rode os testes\numa coisa por vez');
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    await tester.pump();
    expect(f.bench.log, [
      'regras?:b1',
      'regras:b1:rode os testes\numa coisa por vez',
    ]);
  });

  testWidgets('regras iguais às de hoje não mandam nada', (tester) async {
    final f = await mount(tester);
    f.bench.currentRules = 'peça antes de commitar';
    await f.ask(tester, const EditBenchRules('b1', 'deck'));
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    await tester.pump();
    expect(f.bench.log, ['regras?:b1']);
  });

  testWidgets(
    'remover workspace: o core checa, o usuário confirma, o core remove',
    (tester) async {
      final f = await mount(tester);
      await f.ask(tester, const RemoveWorkspace('w1', 'Duck'));
      expect(f.workspace.log, ['checar-remover-ws:w1']);
      expect(find.text('Remover o workspace "Duck"?'), findsOneWidget);
      expect(
        find.text('Só a organização some; nenhuma pasta é tocada.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Remover'));
      await tester.pump();
      await tester.pump();
      expect(f.workspace.log, ['checar-remover-ws:w1', 'remover-ws:w1']);
    },
  );

  testWidgets('workspace com bancadas: a recusa vem antes da confirmação', (
    tester,
  ) async {
    final f = await mount(tester);
    f.workspace.refuse = '"Duck" ainda tem 2 bancada(s). Remova-as antes.';
    await f.ask(tester, const RemoveWorkspace('w1', 'Duck'));
    expect(find.textContaining('ainda tem 2 bancada(s)'), findsOneWidget);
    expect(find.text('Remover o workspace "Duck"?'), findsNothing);
    expect(f.workspace.log, isEmpty);
  });

  testWidgets('tirar projeto confirma dizendo que a pasta não é tocada', (
    tester,
  ) async {
    final f = await mount(tester);
    await f.ask(
      tester,
      const RemoveProject(
        workspaceId: 'w1',
        workspaceName: 'Duck',
        projectId: 'p1',
        projectName: 'egeon',
        projectPath: '~/code/egeon',
      ),
    );
    expect(find.text('Tirar "egeon" de "Duck"?'), findsOneWidget);
    expect(find.text('A pasta ~/code/egeon não é tocada.'), findsOneWidget);
    await tester.tap(find.text('Tirar'));
    await tester.pump();
    await tester.pump();
    expect(f.workspace.log.last, 'remover-projeto:w1/p1');
  });

  group('bancada nova', () {
    testWidgets('sem projeto escolhe a pasta, nomeia e usa o template', (
      tester,
    ) async {
      final f = await mount(tester);
      f.picker.nextFolder = '/Users/eu/code/nexus-backend';
      f.bench.templateList = const [
        BenchTemplate(name: 'dupla', nodes: 2, view: 'chat'),
      ];
      await f.ask(tester, const NewBench());

      expect(f.bench.log, ['templates']);
      expect(find.text('Nova bancada'), findsOneWidget);
      expect(find.text('Começar vazia'), findsOneWidget);
      expect(find.text('dupla · 2 nós'), findsOneWidget);

      await tester.tap(find.text('dupla · 2 nós'));
      await tester.pump();
      await tester.tap(find.text('Criar'));
      await tester.pump();
      await tester.pump();
      expect(
        f.bench.log.last,
        'criar:/Users/eu/code/nexus-backend:nexus-backend::dupla',
      );
    });

    testWidgets(
      'dentro de um projeto usa a pasta dele e deixa o template vazio',
      (tester) async {
        final f = await mount(tester);
        await f.ask(
          tester,
          const NewBench(projectId: 'p1', path: '~/code/api'),
        );
        expect(f.picker.asked, isEmpty, reason: 'a pasta já é a do projeto');
        tester.testTextInput.enterText('minha');
        await tester.pump();
        await tester.tap(find.text('Criar'));
        await tester.pump();
        await tester.pump();
        expect(f.bench.log.last, 'criar:~/code/api:minha:p1:');
      },
    );

    testWidgets('cancelar a pasta ou o formulário não cria nada', (
      tester,
    ) async {
      final f = await mount(tester);
      await f.ask(tester, const NewBench());
      expect(
        f.bench.log,
        isEmpty,
        reason: 'sem pasta nem pergunta os templates',
      );
      f.picker.nextFolder = '/x/y';
      await f.ask(tester, const NewBench());
      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      await tester.pump();
      expect(f.bench.log.where((e) => e.startsWith('criar')), isEmpty);
    });

    testWidgets('a recusa do core aparece com o texto dele', (tester) async {
      final f = await mount(tester);
      f.bench.refuse = 'pasta sem acesso';
      await f.ask(tester, const NewBench(path: '~/x'));
      expect(find.text('pasta sem acesso'), findsOneWidget);
    });
  });

  group('worktree da bancada', () {
    WorktreeInfo info() => const WorktreeInfo(
      summary: 'nexus-backend · main · limpo · 2 worktrees',
      suggestedBranch: 'main-2',
      nodes: [
        NodeWorktree(
          node: 'back',
          branch: 'fix/api',
          state: NodeWorktreeState.ownWorktree,
        ),
        NodeWorktree(node: 'claude', state: NodeWorktreeState.followsWorkbench),
        NodeWorktree(node: 'docs', state: NodeWorktreeState.noRepo),
      ],
    );

    testWidgets(
      'abre com resumo, branch sugerida, veredito e uma linha por terminal',
      (tester) async {
        final f = await mount(tester);
        f.bench.info = info();
        await f.ask(tester, const DuplicateBench('b1', 'deck'));
        await tester.pump();

        expect(find.text('Worktree de deck'), findsOneWidget);
        expect(find.textContaining('2 worktrees'), findsOneWidget);
        expect(find.text('main-2'), findsWidgets);
        expect(f.bench.planned, ['main-2']);
        expect(find.byKey(const ValueKey('worktree-folder')), findsOneWidget);
        expect(find.byKey(const ValueKey('node-back')), findsOneWidget);
        expect(find.byKey(const ValueKey('node-claude')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('node-docs-norepo')),
          findsOneWidget,
          reason: 'fora de repositório não se edita',
        );
      },
    );

    testWidgets('o veredito acompanha a branch e só a última resposta vale', (
      tester,
    ) async {
      final f = await mount(tester);
      f.bench.info = info();
      f.bench.plans['feature/x'] = const WorktreePlan(
        verdict: WorktreeVerdict.followRemote,
        folder: '~/wt/feature-x',
        message: 'segue origin/feature/x',
      );
      await f.ask(tester, const DuplicateBench('b1', 'deck'));
      await tester.pump();

      tester.testTextInput.enterText('feature/x');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('segue origin/feature/x'), findsOneWidget);
      expect(find.text('~/wt/feature-x'), findsOneWidget);
      expect(f.bench.planned.last, 'feature/x');
    });

    testWidgets('abrir manda branch, destino e as branches dos terminais', (
      tester,
    ) async {
      final f = await mount(tester);
      f.bench.info = info();
      await f.ask(tester, const DuplicateBench('b1', 'deck'));
      await tester.pump();

      tester.testTextInput.enterText('feature/y');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('destination-move')));
      await tester.pump();
      await tester.tap(find.text('Abrir'));
      await tester.pump();
      await tester.pump();

      expect(
        f.bench.log.last,
        'worktree:b1:feature/y:move_current:{back: fix/api}',
        reason: 'só o terminal com branch própria vai no mapa; docs fica fora',
      );
    });

    testWidgets('sem branch o botão não abre; cancelar não manda nada', (
      tester,
    ) async {
      final f = await mount(tester);
      f.bench.info = info();
      await f.ask(tester, const DuplicateBench('b1', 'deck'));
      await tester.pump();
      tester.testTextInput.enterText('   ');
      await tester.pump();
      await tester.tap(find.text('Abrir'));
      await tester.pump();
      expect(
        find.text('Worktree de deck'),
        findsOneWidget,
        reason: 'ainda aberta',
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      await tester.pump();
      expect(f.bench.log.where((e) => e.startsWith('worktree:')), isEmpty);
    });
  });
}
