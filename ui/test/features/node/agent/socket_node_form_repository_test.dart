import 'dart:ui';

import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/node_form_submit.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/node_template.dart';
import 'package:egeon_deck/features/node/agent/domain/errors/agent_error.dart';
import 'package:egeon_deck/features/node/agent/domain/repository/socket_node_form_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/protocol_fixtures.dart';
import '../../../support/pump.dart';
import '../../../support/socket_fixture_harness.dart';

/// O formulário de terminal fala exatamente o que o core Rust grava nas
/// fixtures: os comandos saem iguais e as respostas são lidas inteiras.
void main() {
  late SocketHarness harness;
  late SocketNodeFormRepository repository;
  final commands = loadProtocolFixture('commands');
  final replies = loadProtocolFixture('replies');
  const wb = '1a2b3c4d';

  setUp(() async {
    harness = await SocketHarness.start();
    repository = SocketNodeFormRepository(harness.client);
  });
  tearDown(() => harness.dispose());

  /// A resposta da fixture sem o `re` dela: quem responde é o harness.
  Map<String, Object?> body(String name) => {...replies[name]!}
    ..remove('re')
    ..remove('ok');

  NodeTemplate template(String fixture) {
    final command = commands[fixture]!;
    final form = command['form'] as Map<String, Object?>?;
    return NodeTemplate.fromMap(
      (form?['template'] ?? command['template'])! as Map<String, Object?>,
    );
  }

  const shown = ShownFields(
    cli: 'claude',
    model: 'claude-opus-5-5',
    effort: 'high',
    prompt: 'revisa o core',
  );

  NodeFormSubmit submit(String fixture) => NodeFormSubmit(
    template: template(fixture),
    fields: const FormFields(
      name: 'revisor',
      kind: NodeKind.agent,
      agent: 'claude',
      cwd: 'api',
      maestro: true,
    ),
    shown: shown,
    saveComponent: true,
  );

  test('os comandos saem como o core os lê', () async {
    expect(
      await harness.sent(() => repository.open(wb), reply: body('node_form')),
      withoutId(commands['node_form']!),
    );
    expect(
      await harness.sent(
        () => repository.open(wb, nodeId: 'claude'),
        reply: body('node_form'),
      ),
      withoutId(commands['node_form_do_no']!),
    );
    expect(
      await harness.sent(
        () => repository.screen(
          wb,
          template: template('node_form_screen'),
          shown: shown,
          cli: 'codex',
          config: '/Users/voce/.codex-x',
        ),
        reply: body('node_form_screen'),
      ),
      withoutId(commands['node_form_screen']!),
    );
    expect(
      await harness.sent(
        () => repository.folder(wb, '/Users/voce/deck/api'),
        reply: body('node_folder'),
      ),
      withoutId(commands['node_folder']!),
    );
    expect(
      await harness.sent(
        () => repository.create(
          wb,
          submit('create_node_form'),
          frame: const Rect.fromLTWH(120, 80.5, 640, 420),
        ),
        reply: {'node': 'revisor'},
      ),
      withoutId(commands['create_node_form']!),
    );
    // Sem desenho: o que está à vista, para o core achar o lugar livre.
    expect(
      await harness.sent(
        () => repository.create(
          wb,
          submit('create_node_form_visivel'),
          visible: const Rect.fromLTWH(120, 80.5, 640, 420),
        ),
        reply: {'node': 'revisor'},
      ),
      withoutId(commands['create_node_form_visivel']!),
    );
    expect(
      await harness.sent(
        () => repository.apply(wb, 'claude', submit('apply_node')),
        reply: body('no_aplicado'),
      ),
      withoutId(commands['apply_node']!),
    );
    expect(
      await harness.sent(repository.components, reply: body('components')),
      withoutId(commands['components']!),
    );
  });

  test('o formulário aberto: componente, CLIs, pastas e a tela', () async {
    final future = repository.open(wb);
    await pump();
    harness.connection.say({
      ...replies['node_form']!,
      're': harness.connection.sent.last['id'],
    });
    final view = await future;
    expect(view.cli, 'claude');
    expect(view.clis.map((c) => c.name), ['Claude Code', 'Codex']);
    expect(view.folders.first.shown, 'root');
    expect(view.folders.first.value, '');
    expect(view.components.single.subtitle, 'Claude Code');
    expect(view.template.byAgent['claude']!.model, 'claude-opus-5-5');
    final screen = view.screen;
    expect(screen.models.first.id, isNull, reason: 'o padrão do CLI');
    expect(screen.offersModel, isTrue);
    expect(screen.efforts, ['low', 'medium', 'high']);
    expect(screen.configEnv, 'CLAUDE_CONFIG_DIR');
    expect(screen.configItems.first.value, isNull);
    expect(screen.fields.effort, 'high');
  });

  test('aplicar devolve o id final; a recusa vira AgentRefused', () async {
    final future = repository.apply(wb, 'claude', submit('apply_node'));
    await pump();
    harness.connection.say({
      ...replies['no_aplicado']!,
      're': harness.connection.sent.last['id'],
    });
    expect(await future, 'revisor');

    final refused = repository.folder(wb, '/x');
    await pump();
    harness.connection.say({
      're': harness.connection.sent.last['id'],
      'ok': false,
      'error': "bancada desconhecida '1a2b3c4d'",
    });
    await expectLater(refused, throwsA(isA<AgentRefused>()));
  });

  test('os componentes salvos dão os nomes do menu', () async {
    final future = repository.components();
    await pump();
    harness.connection.say({
      ...replies['components']!,
      're': harness.connection.sent.last['id'],
    });
    expect((await future).map((c) => c.name), ['revisor']);
  });
}
