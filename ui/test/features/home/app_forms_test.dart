import 'package:egeon_deck/features/home/presentation/forms/app_forms.dart';
import 'package:egeon_deck/features/workbench/domain/entities/bench_template.dart';
import 'package:egeon_deck/features/workbench/domain/entities/worktree_info.dart';
import 'package:egeon_deck/features/workbench/domain/entities/worktree_plan.dart';
import 'package:egeon_deck/features/home/presentation/forms/form_request.dart';
import 'package:egeon_deck/features/workbench/domain/entities/removal_plan.dart';
import 'package:egeon_deck/features/workbench/domain/entities/template_plan.dart';
import 'package:egeon_deck/features/workspace/domain/entities/workspace_saved.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_path_picker.dart';
import '../../support/fake_workbench_repository.dart';
import '../../support/fake_workspace_repository.dart';
import '../../support/inject_fakes.dart';
import '../../support/overlay_host.dart';

class Forms {
  final bench = FakeWorkbenchRepository();
  final workspace = FakeWorkspaceRepository();
  final picker = FakePathPicker();
  late BuildContext context;

  Future<void> mount(WidgetTester tester) {
    // A janela do formulário rola dentro da tela: a de teste tem de ser alta.
    tester.view
      ..physicalSize = const Size(1000, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    injectFakes(workbenches: bench, workspaces: workspace, paths: picker);
    return tester.pumpWidget(
      overlayHost(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
  }

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

const _wtBack = RemovalWorktree(
  path: '/wt/back',
  repo: 'nexus-backend',
  branch: 'feat/login',
  owners: ['deck'],
);
const _wtFront = RemovalWorktree(
  path: '/wt/front',
  repo: 'nexus-front',
  branch: 'fix/front',
  owners: ['front'],
);
const _wtKept = RemovalWorktree(
  path: '/wt/kept',
  repo: 'nexus-api',
  branch: 'main-2',
  owners: ['api'],
  usedBy: 'outra',
);

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('a cor escolhida na grade vai ao core', (tester) async {
    final f = await mount(tester);
    await f.ask(tester, const RecolorBench('b1', 'deck', current: 'sand'));
    expect(find.text('Cor da bancada'), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Teal',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
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
    expect(
      find.text('Os terminais abertos são encerrados. Nenhuma pasta é tocada.'),
      findsOneWidget,
    );
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
    f.bench.plan = const RemovalPlan(worktrees: [_wtBack, _wtFront]);
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

  testWidgets('a lista diz o que sai e o que fica, e conta só as dela', (
    tester,
  ) async {
    final f = await mount(tester);
    f.bench.plan = const RemovalPlan(worktrees: [_wtBack, _wtKept]);
    await f.ask(tester, const RemoveBench('b1', 'deck'));
    expect(find.text('Também apagar a worktree do disco'), findsOneWidget);
    final hint = tester.widget<Text>(find.byKey(const ValueKey('option-hint')));
    expect(hint.data, contains('nexus-backend · feat/login · deck'));
    expect(
      hint.data,
      contains('nexus-api · main-2 · MANTIDA, é a bancada "outra"'),
    );
    expect(hint.data, contains('Desmarcado, as pastas ficam onde estão'));
  });

  testWidgets('sem worktree nenhuma, diz que nenhuma pasta é tocada', (
    tester,
  ) async {
    final f = await mount(tester);
    await f.ask(tester, const RemoveBench('b1', 'deck'));
    expect(
      find.text('A bancada sai da lista. Nenhuma pasta é tocada.'),
      findsOneWidget,
    );
  });

  testWidgets('só worktrees de outras bancadas: elas ficam, sem caixa', (
    tester,
  ) async {
    final f = await mount(tester);
    f.bench.plan = const RemovalPlan(worktrees: [_wtKept]);
    await f.ask(tester, const RemoveBench('b1', 'deck'));
    expect(
      find.text(
        'A bancada sai da lista. As worktrees dela são de outras bancadas e '
        'ficam.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('option-box')), findsNothing);
  });

  testWidgets('apagar com trabalho não commitado pede a 2ª confirmação', (
    tester,
  ) async {
    final f = await mount(tester);
    f.bench.plan = const RemovalPlan(worktrees: [_wtBack]);
    f.bench.losses = ['nexus-backend · feat/login', '   M src/main.rs'];
    await f.ask(tester, const RemoveBench('b1', 'deck'));
    expect(f.bench.log, ['plano:b1'], reason: 'o git status fica para depois');
    await tester.tap(find.byKey(const ValueKey('option-box')));
    await tester.pump();
    await tester.tap(find.text('Remover'));
    await settle(tester);
    expect(f.bench.log, ['plano:b1', 'perdas:b1']);
    expect(find.text('Isto apaga trabalho não commitado'), findsOneWidget);
    expect(find.textContaining('M src/main.rs'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expect(f.bench.log, [
      'plano:b1',
      'perdas:b1',
    ], reason: 'desistiu: nada removido');

    await f.ask(tester, const RemoveBench('b1', 'deck'));
    await tester.tap(find.byKey(const ValueKey('option-box')));
    await tester.pump();
    await tester.tap(find.text('Remover'));
    await settle(tester);
    await tester.tap(find.text('Apagar mesmo assim'));
    await settle(tester);
    expect(f.bench.log.last, 'remover:b1:true');
  });

  testWidgets('sem marcar a caixa não há 2ª confirmação', (tester) async {
    final f = await mount(tester);
    f.bench.plan = const RemovalPlan(worktrees: [_wtBack]);
    f.bench.losses = ['nexus-backend · feat/login'];
    await f.ask(tester, const RemoveBench('b1', 'deck'));
    await tester.tap(find.text('Remover'));
    await settle(tester);
    expect(find.text('Isto apaga trabalho não commitado'), findsNothing);
    expect(f.bench.log, [
      'plano:b1',
      'remover:b1:false',
    ], reason: 'sem conferir');
  });

  testWidgets('marcada e sem nada a perder, apaga sem 2ª confirmação', (
    tester,
  ) async {
    final f = await mount(tester);
    f.bench.plan = const RemovalPlan(worktrees: [_wtBack]);
    await f.ask(tester, const RemoveBench('b1', 'deck'));
    await tester.tap(find.byKey(const ValueKey('option-box')));
    await tester.pump();
    await tester.tap(find.text('Remover'));
    await settle(tester);
    expect(find.text('Isto apaga trabalho não commitado'), findsNothing);
    expect(f.bench.log, ['plano:b1', 'perdas:b1', 'remover:b1:true']);
  });

  testWidgets('o segundo clique em "Remover" não abre outro diálogo', (
    tester,
  ) async {
    final f = await mount(tester);
    f.bench.plan = const RemovalPlan(worktrees: [_wtBack]);
    await f.ask(tester, const RemoveBench('b1', 'deck'));
    await f.ask(tester, const RemoveBench('b1', 'deck'));
    expect(find.text('Remover a bancada "deck"?'), findsOneWidget);
    expect(f.bench.log, ['plano:b1']);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    await f.ask(tester, const RemoveBench('b1', 'deck'));
    expect(find.text('Remover a bancada "deck"?'), findsOneWidget);
  });

  testWidgets('cancelar a remoção não remove nada', (tester) async {
    final f = await mount(tester);
    f.bench.plan = const RemovalPlan(worktrees: [_wtBack]);
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
          branch: 'main-2',
          state: NodeWorktreeState.ownWorktree,
          repo: 'nexus-api',
          path: '~/code/nexus-api',
        ),
        NodeWorktree(
          node: 'claude',
          state: NodeWorktreeState.followsWorkbench,
          repo: 'nexus-backend',
          path: '~/code/nexus-backend',
          inside: true,
        ),
        NodeWorktree(
          node: 'docs',
          state: NodeWorktreeState.noRepo,
          path: '~/notas',
          exists: false,
        ),
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
          find.byKey(const ValueKey('node-docs')),
          findsNothing,
          reason: 'fora de repositório não se edita',
        );
        String detail(String node) => tester
            .widget<Text>(find.byKey(ValueKey('node-$node-detail')))
            .data!;
        expect(detail('back'), 'nexus-api · worktree própria');
        expect(detail('claude'), 'nexus-backend · vai junto com a bancada');
        expect(detail('docs'), '~/notas · esta pasta não existe');
      },
    );

    testWidgets('em branco não leva; a linha não tocada segue a bancada', (
      tester,
    ) async {
      final f = await mount(tester);
      f.bench.info = info();
      await f.ask(tester, const DuplicateBench('b1', 'deck'));
      await tester.pump();
      String detail(String node) =>
          tester.widget<Text>(find.byKey(ValueKey('node-$node-detail'))).data!;
      String row(String node) => tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(ValueKey('node-$node')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;

      await tester.enterText(find.byKey(const ValueKey('node-claude')), '');
      await tester.pump();
      expect(detail('claude'), 'nexus-backend · fica no repositório original');

      await tester.enterText(
        find.byKey(const ValueKey('worktree-branch')),
        'feature/z',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(row('back'), 'feature/z', reason: 'não tocada, acompanha');
      expect(row('claude'), '', reason: 'tocada, é sua');

      await tester.tap(find.text('Abrir'));
      await tester.pump();
      await tester.pump();
      expect(
        f.bench.log.last,
        'worktree:b1:feature/z:new_workbench:{claude: }',
        reason: 'quem segue a bancada fica de fora do mapa; o vazio não vai',
      );
    });

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
        'worktree:b1:feature/y:move_current:{}',
        reason: 'todos acompanham a bancada; docs não é git',
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

  group('bancada em worktree sem origem', () {
    testWidgets('do projeto: sem destino nem terminais, com template', (
      tester,
    ) async {
      final f = await mount(tester);
      f.bench.info = const WorktreeInfo(
        summary: 'Quando a worktree nasce…',
        suggestedBranch: 'main-2',
        repo: 'nexus-backend',
      );
      f.bench.templateList = const [BenchTemplate(name: 'dupla', nodes: 2)];
      await f.ask(
        tester,
        const NewBench(
          projectId: 'p1',
          path: '~/code/nexus-backend',
          fromWorktree: true,
        ),
      );
      await tester.pump();
      expect(f.bench.log.first, 'worktree_info:projeto=p1');
      expect(find.text('Worktree de nexus-backend'), findsOneWidget);
      expect(find.byKey(const ValueKey('destination-move')), findsNothing);
      expect(find.text('Começar vazia'), findsOneWidget);
      await tester.tap(find.text('dupla · 2 nós'));
      await tester.pump();
      await tester.tap(find.text('Abrir'));
      await settle(tester);
      expect(
        f.bench.log.last,
        'worktree:projeto=p1:main-2:new_workbench:{}:template=dupla',
      );
    });

    testWidgets('do + do topo: escolhe o repositório; cancelar não faz nada', (
      tester,
    ) async {
      final f = await mount(tester);
      await f.ask(tester, const NewBench(fromWorktree: true));
      expect(f.picker.asked, isNotEmpty);
      expect(f.bench.log, isEmpty);

      f.picker.nextFolder = '~/code/api';
      f.bench.info = const WorktreeInfo(
        summary: '',
        suggestedBranch: 'main-2',
        repo: 'api',
      );
      await f.ask(tester, const NewBench(fromWorktree: true));
      await tester.pump();
      expect(f.bench.log.first, 'worktree_info:pasta=~/code/api');
      await tester.tap(find.text('Abrir'));
      await settle(tester);
      expect(
        f.bench.log.last,
        'worktree:pasta=~/code/api:main-2:new_workbench:{}',
      );
    });

    testWidgets('pasta fora do git avisa antes de abrir o formulário', (
      tester,
    ) async {
      final f = await mount(tester);
      f.picker.nextFolder = '~/solta';
      f.bench.refuse = '~/solta não é repositório git';
      await f.ask(tester, const NewBench(fromWorktree: true));
      await tester.pump();
      expect(find.text('Não consegui ler o repositório'), findsOneWidget);
      expect(find.text('~/solta não é repositório git'), findsOneWidget);
      expect(find.text('Abrir'), findsNothing);
    });

    testWidgets('duplicar fora do git diz o nome da bancada', (tester) async {
      final f = await mount(tester);
      f.bench.refuse = '~/deck não é repositório git';
      await f.ask(tester, const DuplicateBench('b1', 'deck'));
      await tester.pump();
      expect(find.text('"deck" não é um repositório git'), findsOneWidget);
    });
  });

  group('multi-projeto', () {
    const multi = WorktreeInfo(
      summary: '',
      suggestedBranch: '',
      multi: MultiWorktree(project: 'Nexus', repos: ['api', 'web']),
    );

    testWidgets('as linhas seguem a branch até serem editadas', (tester) async {
      final f = await mount(tester);
      f.bench.info = multi;
      f.bench.templateList = const [BenchTemplate(name: 'dupla', nodes: 2)];
      await f.ask(tester, const NewBench(projectId: 'm1', fromWorktree: true));
      await tester.pump();
      expect(find.text('Worktree de Nexus'), findsOneWidget);
      expect(find.text('POR REPOSITÓRIO'), findsOneWidget);
      expect(find.text('Começar vazia'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('multi-branch')),
        'feat/x',
      );
      await tester.pump();
      final web = find.descendant(
        of: find.byKey(const ValueKey('repo-web')),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(web).controller.text, 'feat/x');
      await tester.enterText(find.byKey(const ValueKey('repo-web')), 'fix/web');
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('multi-branch')),
        'feat/y',
      );
      await tester.pump();
      expect(
        tester.widget<EditableText>(web).controller.text,
        'fix/web',
        reason: 'editada, a linha é sua',
      );
      await tester.tap(find.text('Abrir'));
      await settle(tester);
      expect(
        f.bench.log.last,
        'worktree:projeto=m1:feat/y:new_workbench:{}:repos={web: fix/web}',
      );
    });

    testWidgets('duplicar bancada multi não oferece template', (tester) async {
      final f = await mount(tester);
      f.bench.info = multi;
      await f.ask(tester, const DuplicateBench('b1', 'nexus-x'));
      await tester.pump();
      expect(find.text('Worktree de Nexus'), findsOneWidget);
      expect(find.text('Começar vazia'), findsNothing);
      expect(f.bench.log, ['worktree_info:b1'], reason: 'nem pede templates');
    });

    testWidgets('repositório que recusa vira aviso, sem derrubar a bancada', (
      tester,
    ) async {
      final f = await mount(tester);
      f.bench.info = multi;
      f.bench.failedRepos = ['web: branch inválida'];
      await f.ask(tester, const NewBench(projectId: 'm1', fromWorktree: true));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('multi-branch')), 'x');
      await tester.pump();
      await tester.tap(find.text('Abrir'));
      await settle(tester);
      expect(find.text('Algumas worktrees ficaram de fora'), findsOneWidget);
      expect(find.text('web: branch inválida'), findsOneWidget);
    });
  });

  group('workspace salvo', () {
    testWidgets('projeto com bancadas que ficou e imagem que não copiou', (
      tester,
    ) async {
      // O formulário de workspace é alto: na tela padrão do teste o botão
      // ficaria fora dela.
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = await mount(tester);
      f.workspace.saveAnswer = const WorkspaceSaved(
        refused: ['Nexus', 'api'],
        warning: 'Não consegui copiar a imagem: sem permissão',
      );
      await f.ask(tester, const NewWorkspace());
      await tester.enterText(find.byType(EditableText).first, 'Agro');
      await tester.pump();
      await tester.tap(find.text('Criar'));
      await settle(tester);

      expect(find.text('Não consegui copiar a imagem'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await settle(tester);
      expect(find.text('Projeto com bancadas fica'), findsOneWidget);
      expect(
        find.text('Remova antes as bancadas de: Nexus, api.'),
        findsOneWidget,
      );
    });
  });

  group('templates de bancada', () {
    testWidgets('canvas vazio não pede nome', (tester) async {
      final f = await mount(tester);
      f.bench.templatePlan = const TemplatePlan(summary: '');
      await f.ask(tester, const SaveAsTemplate('b1', 'deck'));
      expect(find.text('Canvas vazio'), findsOneWidget);
      expect(f.bench.log, ['template?:b1:deck']);
    });

    testWidgets('salvar como: nome da bancada, resumo e grava', (tester) async {
      final f = await mount(tester);
      f.bench.templatePlan = const TemplatePlan(
        summary: '2 agentes — com posição',
        nodes: 2,
      );
      await f.ask(tester, const SaveAsTemplate('b1', 'deck'));
      expect(find.text('Salvar como template'), findsOneWidget);
      expect(find.text('2 agentes — com posição'), findsOneWidget);
      expect(find.text('deck'), findsOneWidget, reason: 'nome sugerido');
      await tester.tap(find.text('Salvar'));
      await settle(tester);
      expect(f.bench.log, [
        'template?:b1:deck',
        'template?:b1:deck',
        'template:b1:deck',
      ]);
    });

    testWidgets('nome que já existe pede para substituir', (tester) async {
      final f = await mount(tester);
      f.bench.templatePlan = const TemplatePlan(summary: 's', nodes: 1);
      f.bench.templatePlans['dupla'] = const TemplatePlan(
        summary: 's',
        nodes: 1,
        template: 'dupla',
        exists: true,
      );
      await f.ask(tester, const SaveAsTemplate('b1', 'deck'));
      tester.testTextInput.enterText('dupla');
      await tester.pump();
      await tester.tap(find.text('Salvar'));
      await settle(tester);
      expect(find.text('Já existe um template "dupla"'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect(f.bench.log.where((e) => e.startsWith('template:')), isEmpty);

      await f.ask(tester, const SaveAsTemplate('b1', 'deck'));
      tester.testTextInput.enterText('dupla');
      await tester.pump();
      await tester.tap(find.text('Salvar'));
      await settle(tester);
      await tester.tap(find.text('Substituir'));
      await settle(tester);
      expect(f.bench.log.last, 'template:b1:dupla');
    });

    testWidgets('atualizar o de origem confirma e regrava', (tester) async {
      final f = await mount(tester);
      f.bench.templatePlan = const TemplatePlan(
        summary: '1 agente',
        nodes: 1,
        template: 'dupla',
        exists: true,
      );
      await f.ask(tester, const UpdateOriginTemplate('b1', 'deck'));
      expect(find.text('Atualizar o template "dupla"?'), findsOneWidget);
      expect(
        find.textContaining('As bancadas que já nasceram deste template'),
        findsOneWidget,
      );
      await tester.tap(find.text('Atualizar'));
      await settle(tester);
      expect(f.bench.log, ['template?:b1:', 'template:b1:']);
    });

    testWidgets('template de origem apagado não vira salvar como', (
      tester,
    ) async {
      final f = await mount(tester);
      f.bench.templatePlan = const TemplatePlan(
        summary: '1 agente',
        nodes: 1,
        template: 'dupla',
      );
      await f.ask(tester, const UpdateOriginTemplate('b1', 'deck'));
      expect(find.text('O template "dupla" não existe mais'), findsOneWidget);
      expect(f.bench.log, ['template?:b1:']);
    });
  });
}
