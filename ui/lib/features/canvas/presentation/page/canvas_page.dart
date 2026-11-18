import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/canvas_card.dart';
import '../../domain/entities/canvas_probe.dart';
import '../../domain/entities/edge_link.dart';
import '../../../../core/adapters/injector.dart';
import '../cubit/canvas_commands.dart';
import '../cubit/canvas_cubit.dart';
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
    this.componentNames = const [],
    this.onConfigureTerminal,
    this.onEditLimit,
    this.onRequestClose,
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
  final List<String> componentNames;
  final VoidCallback? onConfigureTerminal;
  final ValueChanged<EdgeLink>? onEditLimit;
  final ValueChanged<CanvasCard>? onRequestClose;

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
    return BlocProvider(
      key: ValueKey(workbenchId),
      create: (_) => inject<CanvasCubit>(workbenchId),
      child: CanvasSurface(
        bodyBuilder: bodyBuilder,
        accessoryBuilder: accessoryBuilder,
        glow: glow,
        componentNames: componentNames,
        onConfigureTerminal: onConfigureTerminal,
        onEditLimit: onEditLimit,
        onRequestClose: onRequestClose,
        probes: probes,
        commands: commands,
        sidebarInset: sidebarInset,
        nativeCapture: nativeCapture,
      ),
    );
  }
}
