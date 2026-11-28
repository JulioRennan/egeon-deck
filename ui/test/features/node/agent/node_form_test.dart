import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/node_form_view.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/node_template.dart';
import 'package:egeon_deck/features/node/agent/presentation/widgets/node_form.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_node_form_repository.dart';
import '../../../support/fake_path_picker.dart';
import '../../../support/hand_cursor.dart';
import '../../../support/inject_fakes.dart';
import '../../../support/overlay_host.dart';

/// O formulário de terminal: o mesmo para criar e para editar.
void main() {
  late FakeNodeFormRepository repository;
  late FakePathPicker picker;
  late BuildContext context;

  Future<void> mount(
    WidgetTester tester, {
    List<ComponentInfo> saved = const [],
    NodeTemplate? node,
  }) async {
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repository = FakeNodeFormRepository(saved: saved, nodeTemplate: node);
    picker = FakePathPicker();
    injectFakes(nodeForms: repository, paths: picker);
    await tester.pumpWidget(
      overlayHost(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
        size: const Size(1100, 1000),
      ),
    );
  }

  String? Function() open(WidgetTester tester, {String? nodeId, Rect? frame}) {
    String? result;
    var done = false;
    showNodeForm(
      context,
      workbenchId: 'b1',
      nodeId: nodeId,
      frame: frame,
      root: '~/deck',
    ).then((id) {
      result = id;
      done = true;
    });
    return () {
      expect(done, isTrue, reason: 'o formulário fechou');
      return result;
    };
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('terminal novo: agente com o Claude Code, e criar leva tudo', (
    tester,
  ) async {
    await mount(tester);
    final result = open(tester, frame: const Rect.fromLTWH(1, 2, 600, 400));
    await settle(tester);

    expect(find.text('Novo terminal'), findsOneWidget);
    expect(
      find.text('O nome vira o id do nó e aparece no endereço de dispatch.'),
      findsOneWidget,
    );
    expect(find.text('MODELO'), findsOneWidget);
    expect(find.text('ESFORÇO'), findsOneWidget);
    expect(find.text('CONFIGURAÇÃO — CLAUDE_CONFIG_DIR'), findsOneWidget);
    expect(find.text('PAPEL — quem este terminal é'), findsOneWidget);
    expect(find.text('COMANDO — vazio abre o zsh'), findsNothing);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('node-name')),
        matching: find.byType(EditableText),
      ),
      'revisor',
    );
    await tester.tap(find.byKey(const ValueKey('folder-api')));
    await tester.tap(find.byKey(const ValueKey('node-maestro')));
    await tester.tap(find.byKey(const ValueKey('save-component')));
    await tester.pump();
    await tester.tap(find.text('Criar'));
    await settle(tester);

    final created = repository.created.single;
    expect(created.frame, const Rect.fromLTWH(1, 2, 600, 400));
    expect(created.form.fields.name, 'revisor');
    expect(created.form.fields.kind, NodeKind.agent);
    expect(created.form.fields.agent, 'claude');
    expect(created.form.fields.cwd, 'api');
    expect(created.form.fields.maestro, isTrue);
    expect(created.form.saveComponent, isTrue);
    expect(created.form.shown?.cli, 'claude');
    expect(result(), 'revisor');
  });

  testWidgets('o select de esforço lista os níveis em português', (
    tester,
  ) async {
    await mount(tester);
    open(tester, frame: const Rect.fromLTWH(1, 2, 600, 400));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('node-effort')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (final name in ['baixo', 'médio', 'alto']) {
      expect(find.text(name), findsWidgets, reason: name);
    }
    expect(find.text('medium'), findsNothing);
  });

  testWidgets('shell é nome, comando e pasta; o resto some', (tester) async {
    await mount(tester);
    open(tester);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('node-kind-0')));
    await tester.pump();

    expect(find.text('COMANDO — vazio abre o zsh'), findsOneWidget);
    expect(find.text('CLI'), findsNothing);
    expect(find.text('MODELO'), findsNothing);
    expect(find.text('PAPEL — quem este terminal é'), findsNothing);
    expect(find.byKey(const ValueKey('node-maestro')), findsNothing);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('node-cmd')),
        matching: find.byType(EditableText),
      ),
      'npm run dev',
    );
    await tester.tap(find.text('Criar'));
    await settle(tester);
    final fields = repository.created.single.form.fields;
    expect(fields.kind, NodeKind.shell);
    expect(fields.agent, isNull);
    expect(fields.cmd, 'npm run dev');
  });

  testWidgets('trocar de CLI guarda a tela e esconde o que o CLI não tem', (
    tester,
  ) async {
    await mount(tester);
    open(tester);
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('node-prompt')),
        matching: find.byType(EditableText),
      ),
      'revisa o core',
    );
    await tester.tap(find.byKey(const ValueKey('cli-opencode')));
    await settle(tester);

    final asked = repository.screens.single;
    expect(asked.cli, 'opencode');
    expect(asked.shown?.cli, 'claude');
    expect(asked.shown?.prompt, 'revisa o core');
    expect(find.text('MODELO'), findsNothing);
    expect(find.text('CONFIGURAÇÃO — CLAUDE_CONFIG_DIR'), findsNothing);
    expect(find.text('revisa o core'), findsOneWidget, reason: 'papel é geral');
  });

  testWidgets('o + da pasta abre na bancada e a escolhida fica marcada', (
    tester,
  ) async {
    await mount(tester);
    open(tester);
    await settle(tester);
    picker.nextFolder = '~/deck/web';
    await tester.tap(find.byKey(const ValueKey('folder-add')));
    await settle(tester);
    expect(picker.asked, ['pasta@~/deck']);
    expect(find.byKey(const ValueKey('folder-web')), findsOneWidget);

    await tester.tap(find.text('Criar'));
    await settle(tester);
    expect(repository.created.single.form.fields.cwd, 'web');
  });

  testWidgets('começar de outro: sem componentes, o aviso de como salvar', (
    tester,
  ) async {
    await mount(tester);
    open(tester);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-tab-1')));
    await tester.pump();
    expect(
      find.textContaining('Nenhum componente salvo ainda.'),
      findsOneWidget,
    );
  });

  testWidgets('começar de outro: o card preenche e volta para os detalhes', (
    tester,
  ) async {
    await mount(
      tester,
      saved: const [
        ComponentInfo(
          name: 'build',
          kind: NodeKind.shell,
          subtitle: 'Shell',
          template: NodeTemplate(
            name: 'build',
            kind: NodeKind.shell,
            cmd: 'make',
          ),
        ),
      ],
    );
    open(tester);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-tab-1')));
    await tester.pump();
    expectHandOnEveryClickable(tester);
    await tester.tap(find.byKey(const ValueKey('component-build')));
    await settle(tester);

    expect(find.text('COMANDO — vazio abre o zsh'), findsOneWidget);
    expect(find.text('make'), findsOneWidget);
    expect(find.text('build'), findsOneWidget);
  });

  testWidgets('editar: o título é o nó e confirmar aplica', (tester) async {
    await mount(
      tester,
      node: const NodeTemplate(
        name: 'claude',
        kind: NodeKind.agent,
        agent: 'claude',
        prompt: 'revisa',
      ),
    );
    final result = open(tester, nodeId: 'claude');
    await settle(tester);
    expect(find.text('Configurar claude'), findsOneWidget);
    expect(find.text('revisa'), findsOneWidget);
    await tester.tap(find.text('Aplicar'));
    await settle(tester);
    expect(repository.applied.single.nodeId, 'claude');
    expect(repository.opened, ['claude']);
    expect(result(), 'claude');
  });

  testWidgets('a recusa do core aparece e o formulário fica', (tester) async {
    await mount(tester);
    open(tester);
    await settle(tester);
    repository.refuse = 'nome em uso';
    await tester.tap(find.text('Criar'));
    await settle(tester);
    expect(find.text('nome em uso'), findsOneWidget);
    expect(find.text('Novo terminal'), findsOneWidget);
  });
}
