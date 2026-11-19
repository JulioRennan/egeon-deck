import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/standard_dialogs.dart';
import '../../../../core/adapters/injector.dart';
import '../../../../core/domain/entities/workbench.dart';
import '../../../../core/domain/entities/workbench_clock.dart';
import '../../../workbench/presentation/widgets/clock_chip.dart';
import '../../../workbench/domain/errors/workbench_error.dart';
import '../../../workbench/domain/usecase/reset_clock.dart';
import '../../../workbench/domain/entities/worktree_info.dart';
import '../../../workbench/domain/entities/worktree_source.dart';
import '../../../workbench/domain/usecase/bench_creation.dart';
import '../../../workbench/presentation/widgets/node_worktree_form.dart';
import '../../../canvas/domain/usecase/open_node_folder.dart';
import '../../../node/agent/domain/errors/agent_error.dart';
import '../../../node/agent/domain/usecase/retry_agent.dart';
import '../../../../core/domain/entities/workbench_node.dart';
import '../../../../theme/workbench_palette.dart';
import '../../../canvas/domain/entities/canvas_card.dart';
import '../../../canvas/domain/entities/edge_link.dart';
import '../../../canvas/domain/errors/canvas_error.dart';
import '../../../canvas/domain/usecase/edit_links.dart';
import '../../../canvas/domain/usecase/remove_node.dart';
import '../../../canvas/presentation/page/canvas_page.dart';
import '../../../canvas/presentation/widgets/canvas_bench_actions.dart';
import '../forms/app_forms.dart';
import '../forms/form_request.dart';
import '../../../canvas/domain/entities/canvas_probe.dart';
import '../../../canvas/presentation/cubit/canvas_commands.dart';
import '../../../node/agent/domain/usecase/list_components.dart';
import '../../../node/agent/presentation/widgets/agent_accessory.dart';
import '../../../node/agent/presentation/widgets/node_form.dart';
import '../../../node/queue/presentation/widgets/queue_body.dart';
import '../../../node/terminal/presentation/widgets/terminal_body.dart';
import '../../../node/web/presentation/cubit/web_capture_registry.dart';
import '../../../node/web/presentation/widgets/web_body.dart';

/// O canvas da bancada na tela: o terminal no corpo de cada card de terminal e
/// as duas perguntas que o canvas deixa para a casca — o limite de uma ligação
/// e a confirmação de fechar um nó.
class WorkbenchCanvas extends StatelessWidget {
  const WorkbenchCanvas({
    required this.bench,
    this.sidebarInset = 0,
    this.clock,
    super.key,
  });

  final Workbench bench;

  /// O cronômetro da bancada, na faixa sob a barra de ações (ADR-085).
  final WorkbenchClock? clock;

  /// O quanto da esquerda a barra lateral flutuante cobre.
  final double sidebarInset;

  /// O corpo de cada card, pelo tipo. A tela do terminal é do `screen` do nó;
  /// sem ele, o próprio id.
  Widget _body(BuildContext context, CanvasCard card) => switch (card.kind) {
    NodeKind.shell ||
    NodeKind.agent => TerminalBody(nodeId: card.screen ?? card.id),
    NodeKind.queue => QueueBody(workbenchId: bench.id, nodeId: card.id),
    NodeKind.web => WebBody(workbenchId: bench.id, nodeId: card.id),
  };

  /// A faixa extra do cabeçalho: só o agente tem (modelo, esforço, contexto).
  Widget? _accessory(BuildContext context, CanvasCard card) =>
      card.kind == NodeKind.agent
      ? AgentAccessory(
          workbenchId: bench.id,
          nodeId: card.id,
          onRequestClear: (clear) =>
              unawaited(confirmClearAgent(context, card.id, clear)),
        )
      : null;

  /// O formulário de terminal: novo (no [frame], ou no primeiro lugar livre
  /// do que está à vista, [visible]) ou do nó [nodeId].
  Future<void> _nodeForm(
    BuildContext context, {
    String? nodeId,
    Rect? frame,
    Rect? visible,
  }) => showNodeForm(
    context,
    workbenchId: bench.id,
    nodeId: nodeId,
    frame: frame,
    visible: visible,
    root: bench.path,
  );

  /// O menu do Terminal sem o core é só "Shell simples" e "Configurar…".
  static Future<List<String>> _componentNames() =>
      inject<ListComponents>()().catchError(
        (_) => const <String>[],
        test: (error) => error is AgentError,
      );

  @override
  Widget build(BuildContext context) => CanvasPage(
    key: ValueKey(bench.id),
    workbenchId: bench.id,
    probes: inject<CanvasProbeRegistry>(),
    commands: inject<CanvasCommands>(),
    sidebarInset: sidebarInset,
    nativeCapture: inject<WebCaptureRegistry>().capture,
    glow: bench.color == null ? null : WorkbenchPalette.of(bench.color),
    bodyBuilder: _body,
    accessoryBuilder: _accessory,
    componentNames: _componentNames,
    infoBar: switch (clock) {
      final clock? => ClockChip(
        clock: clock,
        // Recusa do core não tem o que mostrar: o relógio continua como está.
        onReset: () => unawaited(
          inject<ResetClock>()(bench.id)
              .catchError((_) {}, test: (e) => e is WorkbenchError),
        ),
      ),
      null => null,
    },
    onConfigureTerminal: (visible) =>
        unawaited(_nodeForm(context, visible: visible)),
    onConfigureTerminalAt: (frame) =>
        unawaited(_nodeForm(context, frame: frame)),
    onRequestConfigure: (card) =>
        unawaited(_nodeForm(context, nodeId: card.id)),
    onEditLimit: (link) => editEdgeLimit(context, bench.id, link),
    onRequestClose: (card) => confirmRemoveNode(context, bench, card),
    // Sem tentativa agendada (ela já disparou), o core recusa e o estado
    // novo já diz o que houve.
    onRequestWorktree: (card) =>
        unawaited(openNodeWorktree(context, bench.id, card)),
    onOpenFolder: (card) => unawaited(
      inject<OpenNodeFolder>()(
        bench.id,
        card.id,
      ).catchError((_) {}, test: (e) => e is CanvasError),
    ),
    onRetry: (card, {required now}) => unawaited(
      inject<RetryAgent>(bench.id)(
        card.id,
        now: now,
      ).catchError((_) {}, test: (e) => e is AgentError),
    ),
    benchActions: CanvasBenchActions(
      onSaveTemplate: () =>
          unawaited(handleForm(context, SaveAsTemplate(bench.id, bench.name))),
      originTemplate: bench.template,
      onUpdateTemplate: () => unawaited(
        handleForm(context, UpdateOriginTemplate(bench.id, bench.name)),
      ),
      onNewWorktree: () =>
          unawaited(handleForm(context, DuplicateBench(bench.id, bench.name))),
    ),
  );
}

/// Pergunta antes, como a limpeza da bancada: o botão fica colado aos
/// controles de modelo, e o clique errado custaria o contexto do agente.
/// "Nova worktree para este terminal…" (`nodeWorktree` do Swift): o core lê
/// o repositório da pasta do nó, a pessoa escolhe a branch e só aquele card é
/// reapontado — id, papel, arestas e posição ficam; o processo reinicia.
Future<void> openNodeWorktree(
  BuildContext context,
  String bench,
  CanvasCard card,
) async {
  final source = WorktreeSource.node(bench, card.id);
  final actions = inject<WorktreeActions>();
  final WorktreeInfo info;
  try {
    info = await actions.info(source);
  } on WorkbenchError catch (failure) {
    if (!context.mounted) return;
    return messageDialog(
      context,
      title: '"${card.id}" não abre num repositório git',
      message: _worktreeFailure(failure),
    );
  }
  if (!context.mounted) return;
  final branch = await showNodeWorktreeForm(
    context,
    source: source,
    nodeId: card.id,
    repo: info.repo,
    currentPath: card.subtitle,
    suggested: info.suggestedBranch,
  );
  if (branch == null || !context.mounted) return;
  try {
    await actions.create(source, branch);
  } on WorkbenchError catch (failure) {
    if (!context.mounted) return;
    await messageDialog(
      context,
      title: 'Não consegui abrir a worktree',
      message: _worktreeFailure(failure),
    );
  }
}

String _worktreeFailure(WorkbenchError failure) => switch (failure) {
  WorkbenchRefused(:final message) => message,
  WorkbenchOffline() => 'O app perdeu a conexão com o core.',
};

Future<void> confirmClearAgent(
  BuildContext context,
  String nodeId,
  VoidCallback clear,
) async {
  final confirmed = await confirmDialog(
    context,
    title: 'Limpar a conversa de "$nodeId"?',
    message:
        'O agente esquece a conversa atual. O chat e a trilha da bancada '
        'continuam como estão.',
    confirmLabel: 'Limpar',
  );
  if (confirmed) clear();
}

/// O texto do limite: vazio é "sem limite", e o que não é número não muda
/// nada — interpretar lixo como "libera" seria o erro mais caro desse campo.
({bool valid, int? limit}) parseEdgeLimit(String typed) {
  final text = typed.trim();
  if (text.isEmpty) return (valid: true, limit: null);
  final number = int.tryParse(text);
  if (number == null) return (valid: false, limit: null);
  return (valid: true, limit: number < 1 ? 1 : number);
}

String edgeTitle(EdgeLink link) {
  if (link.isBidirectional) return '${link.a} ↔ ${link.b}';
  return link.aToB ? '${link.a} → ${link.b}' : '${link.b} → ${link.a}';
}

Future<void> editEdgeLimit(
  BuildContext context,
  String workbenchId,
  EdgeLink link,
) async {
  final links = inject<EditLinks>();
  final typed = await promptDialog(
    context,
    title: edgeTitle(link),
    message:
        'Quantas vezes esta ligação pode disparar numa mesma conversa. Num '
        'par ligado nos dois sentidos, é o número de idas e voltas.\n\n'
        'Vazio = sem limite.',
    confirmLabel: 'Salvar',
    initial: link.maxSends?.toString() ?? '',
    placeholder: 'sem limite',
    allowEmpty: true,
  );
  if (typed == null || !context.mounted) return;
  final parsed = parseEdgeLimit(typed);
  if (!parsed.valid) return;
  await _guard(context, () => links.setLimit(workbenchId, link, parsed.limit));
}

/// O que remover este nó leva junto, por tipo.
String removalWarning(CanvasCard card) => switch (card.kind) {
  NodeKind.shell || NodeKind.agent =>
    'O processo do terminal é encerrado junto — o que estiver rodando nele '
        'para.',
  NodeKind.web =>
    'A sessão fica salva no perfil do nó — reabrir um nó web com esse perfil '
        'volta logado.',
  NodeKind.queue =>
    'As tarefas da fila e os prints anotados nelas são apagados junto.',
};

Future<void> confirmRemoveNode(
  BuildContext context,
  Workbench bench,
  CanvasCard card,
) async {
  final remove = inject<RemoveNode>();
  final confirmed = await confirmDialog(
    context,
    title: 'Remover "${card.title}" do bancada ${bench.name}?',
    message: removalWarning(card),
    confirmLabel: 'Remover',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  await _guard(context, () => remove(bench.id, card.id));
}

Future<void> _guard(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } on CanvasRefused catch (failure) {
    if (!context.mounted) return;
    await messageDialog(
      context,
      title: 'Não foi possível',
      message: failure.message,
    );
  }
}
