import 'dart:ui';

import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/node_form_submit.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/node_form_view.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/node_template.dart';
import 'package:egeon_deck/features/node/agent/domain/errors/agent_error.dart';
import 'package:egeon_deck/features/node/agent/domain/usecase/list_components.dart';
import 'package:egeon_deck/features/node/agent/domain/usecase/node_form_actions.dart';
import 'package:egeon_deck/features/node/agent/presentation/cubit/node_form_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_node_form_repository.dart';
import '../../../support/pump.dart';

void main() {
  late FakeNodeFormRepository repository;

  Future<NodeFormCubit> open({String? nodeId, Rect? frame}) async {
    final cubit = NodeFormCubit(
      target: (workbenchId: 'b1', nodeId: nodeId, frame: frame, visible: null),
      actions: NodeFormActions(repository),
    );
    addTearDown(cubit.close);
    await pump();
    return cubit;
  }

  setUp(() => repository = FakeNodeFormRepository());

  test('abre com o que o core manda e a tela do CLI marcado', () async {
    final cubit = await open();
    final state = cubit.state;
    expect(state, isA<NodeFormLoaded>());
    state as NodeFormLoaded;
    expect(state.cli, 'claude');
    expect(state.screen.offersModel, isTrue);
    expect(state.folders.map((f) => f.shown), ['root', 'api']);
    expect(repository.opened, [null]);
    expect(cubit.editing, isFalse);
  });

  test('o core fora: o formulário diz por quê, sem abrir', () async {
    repository.refuse = 'bancada desconhecida';
    final cubit = await open();
    expect(
      cubit.state,
      isA<NodeFormUnavailable>().having(
        (s) => s.error,
        'error',
        isA<AgentRefused>(),
      ),
    );
  });

  test('trocar de CLI manda o que estava na tela e só mexe no CLI', () async {
    final cubit = await open();
    const shown = ShownFields(cli: 'claude', model: 'claude-opus-5-5');
    await cubit.switchCli('opencode', shown);
    final state = cubit.state;
    expect(state, isA<NodeFormSwitched>());
    state as NodeFormSwitched;
    expect(state.cli, 'opencode');
    expect(state.screen.offersModel, isFalse, reason: 'o OpenCode não tem');
    expect(repository.screens.single.shown, shown);
  });

  test('o + da configuração pede a tela do mesmo CLI com ela', () async {
    final cubit = await open();
    await cubit.pickConfig('~/.claude-x', null);
    expect(repository.screens.single.cli, 'claude');
    expect(repository.screens.single.config, '~/.claude-x');
    expect(
      (cubit.state as NodeFormSwitched).screen.fields.config,
      '~/.claude-x',
    );
  });

  test('o + da pasta entra na lista uma vez só, marcada', () async {
    final cubit = await open();
    await cubit.addFolder('/Users/voce/deck/web');
    final state = cubit.state as NodeFormFolderAdded;
    expect(state.folder, 'web');
    expect(state.folders.map((f) => f.value), ['', 'api', 'web']);
    await cubit.addFolder('/Users/voce/deck/web');
    expect((cubit.state as NodeFormOpen).folders, hasLength(3));
  });

  test('começar de outro carrega o componente inteiro', () async {
    final cubit = await open();
    await cubit.startFrom(
      const ComponentInfo(
        name: 'build',
        kind: NodeKind.shell,
        subtitle: 'Shell',
        template: NodeTemplate(
          name: 'build',
          kind: NodeKind.shell,
          cmd: 'make',
          cwd: 'tools',
        ),
      ),
    );
    final state = cubit.state as NodeFormLoaded;
    expect(state.template.name, 'build');
    expect(state.cli, 'claude', reason: 'shell não tem CLI: fica o primeiro');
    expect(state.folders.map((f) => f.value), contains('tools'));
  });

  test('criar leva o retângulo; aplicar leva o nó', () async {
    final cubit = await open(frame: const Rect.fromLTWH(10, 20, 600, 400));
    const fields = FormFields(name: 'rev', kind: NodeKind.agent);
    await cubit.confirm(fields, saveComponent: true);
    expect(cubit.state, isA<NodeFormDone>());
    expect(
      repository.created.single.frame,
      const Rect.fromLTWH(10, 20, 600, 400),
    );
    expect(repository.created.single.form.saveComponent, isTrue);

    final edit = await open(nodeId: 'claude');
    expect(edit.editing, isTrue);
    await edit.confirm(const FormFields(name: 'critico', kind: NodeKind.agent));
    expect(repository.applied.single.nodeId, 'claude');
    expect((edit.state as NodeFormDone).nodeId, 'critico');
  });

  test(
    'a recusa ao confirmar deixa o formulário aberto com o motivo',
    () async {
      final cubit = await open();
      repository.refuse = 'nome em uso';
      await cubit.confirm(const FormFields(name: 'x', kind: NodeKind.shell));
      expect(
        cubit.state,
        isA<NodeFormRefused>().having(
          (s) => s.error,
          'error',
          isA<AgentRefused>().having(
            (e) => e.message,
            'message',
            'nome em uso',
          ),
        ),
      );
    },
  );

  test('os nomes dos componentes vêm do core, na ordem dele', () async {
    repository = FakeNodeFormRepository(
      saved: const [
        ComponentInfo(
          name: 'revisor',
          kind: NodeKind.agent,
          subtitle: 'Claude Code',
          template: NodeTemplate(name: 'revisor', kind: NodeKind.agent),
        ),
      ],
    );
    expect(await ListComponents(repository)(), ['revisor']);
  });

  test(
    'a linha do componente traz CLI, modelo e o esforço em português',
    () async {
      repository = FakeNodeFormRepository(
        saved: const [
          ComponentInfo(
            name: 'revisor',
            kind: NodeKind.agent,
            subtitle: 'Claude Code',
            template: NodeTemplate(
              name: 'revisor',
              kind: NodeKind.agent,
              agent: 'claude',
              byAgent: {'claude': CliOverrides(model: 'opus', effort: 'high')},
            ),
          ),
        ],
      );
      final choices = await ListComponents(repository).choices('b1');
      expect(
        choices.single.meta,
        'Claude Code · opus · alto',
        reason: 'apelido que o catálogo não conhece fica como está',
      );
    },
  );

  test('o modelo da linha sai com o título do catálogo do CLI', () async {
    repository = FakeNodeFormRepository(
      saved: const [
        ComponentInfo(
          name: 'revisor',
          kind: NodeKind.agent,
          subtitle: 'Claude Code',
          template: NodeTemplate(
            name: 'revisor',
            kind: NodeKind.agent,
            agent: 'claude',
            byAgent: {
              'claude': CliOverrides(model: 'claude-opus-5-5', effort: 'high'),
            },
          ),
        ),
      ],
    );
    final choices = await ListComponents(repository).choices('b1');
    expect(choices.single.meta, 'Claude Code · Opus 5.5 · alto');
    expect(repository.screens.single.cli, 'claude');
  });

  test('sem o catálogo (o core recusa), a linha fica com o apelido', () async {
    repository = FakeNodeFormRepository(
      saved: const [
        ComponentInfo(
          name: 'revisor',
          kind: NodeKind.agent,
          subtitle: 'Claude Code',
          template: NodeTemplate(
            name: 'revisor',
            kind: NodeKind.agent,
            agent: 'claude',
            byAgent: {
              'claude': CliOverrides(model: 'claude-opus-5-5', effort: 'high'),
            },
          ),
        ),
      ],
    )..refuseScreen = true;
    final choices = await ListComponents(repository).choices('b1');
    expect(choices.single.meta, 'Claude Code · claude-opus-5-5 · alto');
  });
}
