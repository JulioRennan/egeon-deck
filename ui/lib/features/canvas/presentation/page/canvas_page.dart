import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/canvas_card.dart';
import '../../domain/entities/canvas_component.dart';
import '../../domain/entities/canvas_probe.dart';
import '../../domain/entities/edge_link.dart';
import '../../../../core/adapters/injector.dart';
import '../cubit/canvas_commands.dart';
import '../cubit/canvas_cubit.dart';
import '../cubit/canvas_motion_cubit.dart';
import '../cubit/canvas_tool_cubit.dart';
import '../widgets/canvas_bench_actions.dart';
import '../widgets/canvas_surface.dart';

/// O canvas de uma bancada. O cubit nasce aqui, preso à bancada: trocar de
/// bancada troca a [key] e o cubit antigo fecha a assinatura.
///
/// Só compõe: o que cada card mostra vem de [bodyBuilder], para o canvas não
/// conhecer terminal, web nem fila.
class CanvasPage extends StatelessWidget {
  const CanvasPage({
    required this.workbenchId,
    required this.bodyBuilder,
    this.accessoryBuilder,
    this.glow,
    this.components,
    this.benchName = '',
    this.benchColor,
    this.onPickColor,
    this.onConfigureTerminal,
    this.onConfigureTerminalAt,
    this.benchActions,
    this.infoBar,
    this.onRequestConfigure,
    this.onEditLimit,
    this.onRequestClose,
    this.onRetry,
    this.onOpenFolder,
    this.onRequestWorktree,
    this.probes,
    this.nativeCapture,
    this.commands,
    this.sidebarInset = 0,
    super.key,
  });

  final String workbenchId;
  final CardBodyBuilder bodyBuilder;
  final CardAccessoryBuilder? accessoryBuilder;
  final Color? glow;

  /// Os componentes salvos, pedidos quando o menu do Terminal abre.
  final Future<List<CanvasComponent>> Function()? components;

  /// A cor da bancada (nome gravado) e quem a troca: o botão de cor da barra.
  final String benchName;
  final String? benchColor;
  final ValueChanged<String>? onPickColor;

  /// "Configurar novo terminal…", com o que está à vista no canvas.
  final ValueChanged<Rect>? onConfigureTerminal;

  /// Terminal solto sem componente: o formulário para aquele lugar.
  final ValueChanged<Rect>? onConfigureTerminalAt;

  /// Os botões de template e worktree da barra.
  final CanvasBenchActions? benchActions;

  /// A faixa informativa sob a barra de ações (ADR-085): quem compõe a tela a
  /// monta, para o canvas não conhecer a bancada.
  final Widget? infoBar;

  /// O lápis do card de terminal.
  final ValueChanged<CanvasCard>? onRequestConfigure;
  final ValueChanged<EdgeLink>? onEditLimit;
  final ValueChanged<CanvasCard>? onRequestClose;

  /// "Tentar agora" / "Cancelar tentativa" no status de um agente.
  final void Function(CanvasCard card, {required bool now})? onRetry;

  /// O ⌘-clique no subtítulo de um terminal: a pasta dele no Finder.
  final ValueChanged<CanvasCard>? onOpenFolder;

  /// "Nova worktree para este terminal…" de um shell ou agente.
  final ValueChanged<CanvasCard>? onRequestWorktree;

  /// Os comandos do menu da casca: ferramentas e zoom.
  final CanvasCommands? commands;

  /// O quanto da esquerda a barra lateral flutuante cobre (enquadrar desconta).
  final double sidebarInset;

  /// Onde o canvas se registra para `/geometry` e `/shot`.
  final CanvasProbeRegistry? probes;

  /// A captura da página nativa de um card (web).
  final Future<Uint8List?> Function(String cardId)? nativeCapture;

  @override
  Widget build(BuildContext context) {
    // Três assuntos, três cubits: o que a mão faz no canvas, a ferramenta
    // armada e o movimento (o realce de uma ligação convive com o zoom).
    return MultiBlocProvider(
      key: ValueKey(workbenchId),
      providers: [
        BlocProvider(create: (_) => inject<CanvasCubit>(workbenchId)),
        BlocProvider(create: (_) => inject<CanvasToolCubit>(workbenchId)),
        BlocProvider(
          create: (context) =>
              inject<CanvasMotionCubit>(context.read<CanvasCubit>().motion),
        ),
      ],
      child: CanvasSurface(
        bodyBuilder: bodyBuilder,
        accessoryBuilder: accessoryBuilder,
        glow: glow,
        components: components,
        benchName: benchName,
        benchColor: benchColor,
        onPickColor: onPickColor,
        onConfigureTerminal: onConfigureTerminal,
        onConfigureTerminalAt: onConfigureTerminalAt,
        benchActions: benchActions,
        infoBar: infoBar,
        onRequestConfigure: onRequestConfigure,
        onEditLimit: onEditLimit,
        onRequestClose: onRequestClose,
        onRetry: onRetry,
        onOpenFolder: onOpenFolder,
        onRequestWorktree: onRequestWorktree,
        probes: probes,
        commands: commands,
        sidebarInset: sidebarInset,
        nativeCapture: nativeCapture,
      ),
    );
  }
}
