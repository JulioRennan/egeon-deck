import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/standard_dialogs.dart';
import '../../../../core/adapters/injector.dart';
import '../../../../core/domain/entities/workbench.dart';
import '../../../../core/domain/entities/workbench_node.dart';
import '../../../../theme/workbench_palette.dart';
import '../../../canvas/domain/entities/canvas_card.dart';
import '../../../canvas/domain/entities/edge_link.dart';
import '../../../canvas/domain/errors/canvas_error.dart';
import '../../../canvas/domain/usecase/edit_links.dart';
import '../../../canvas/domain/usecase/remove_node.dart';
import '../../../canvas/presentation/page/canvas_page.dart';
import '../../../canvas/domain/entities/canvas_probe.dart';
import '../../../canvas/presentation/cubit/canvas_commands.dart';
import '../../../node/agent/presentation/widgets/agent_accessory.dart';
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
    super.key,
  });

  final Workbench bench;

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
      ? AgentAccessory(workbenchId: bench.id, nodeId: card.id)
      : null;

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
    onEditLimit: (link) => editEdgeLimit(context, bench.id, link),
    onRequestClose: (card) => confirmRemoveNode(context, bench, card),
  );
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
