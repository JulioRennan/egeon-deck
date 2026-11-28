import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_component.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_probe.dart';
import 'package:egeon_deck/features/canvas/domain/repository/canvas_repository.dart';
import 'package:egeon_deck/features/canvas/presentation/cubit/canvas_commands.dart';
import 'package:egeon_deck/features/canvas/presentation/page/canvas_page.dart';
import 'package:egeon_deck/features/canvas/presentation/widgets/canvas_bench_actions.dart';

import 'dart:typed_data';

import 'eg_host.dart';
import 'inject_fakes.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// O canvas numa janela 1200×800, com o corpo dos cards trocado por um bloco
/// liso — o que o canvas posiciona, não o que o card mostra.
Future<void> pumpCanvas(
  WidgetTester tester,
  CanvasRepository repository, {
  List<String> componentNames = const [],
  List<CanvasComponent>? components,
  CanvasBenchActions? benchActions,
  String benchName = 'bancada',
  String? benchColor,
  ValueChanged<String>? onPickColor,
  ValueChanged<dynamic>? onEditLimit,
  CanvasProbeRegistry? probes,
  CanvasCommands? commands,
  double sidebarInset = 0,
  Future<Uint8List?> Function(String cardId)? nativeCapture,
  ValueChanged<Rect>? onConfigureTerminal,
  ValueChanged<Rect>? onConfigureTerminalAt,
  ValueChanged<CanvasCard>? onRequestConfigure,
  void Function(CanvasCard card, {required bool now})? onRetry,
  ValueChanged<CanvasCard>? onOpenFolder,
  ValueChanged<CanvasCard>? onRequestWorktree,
}) async {
  tester.view
    ..physicalSize = const Size(1200, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  injectFakes(canvas: repository);
  await tester.pumpWidget(
    egHost(
      fill: true,
      size: const Size(1200, 800),
      CanvasPage(
        workbenchId: 'bancada',
        components: () async =>
            components ?? [for (final n in componentNames) CanvasComponent(n)],
        benchActions: benchActions,
        benchName: benchName,
        benchColor: benchColor,
        onPickColor: onPickColor,
        onEditLimit: onEditLimit,
        probes: probes,
        commands: commands,
        sidebarInset: sidebarInset,
        nativeCapture: nativeCapture,
        onConfigureTerminal: onConfigureTerminal,
        onConfigureTerminalAt: onConfigureTerminalAt,
        onRequestConfigure: onRequestConfigure,
        onRetry: onRetry,
        onOpenFolder: onOpenFolder,
        onRequestWorktree: onRequestWorktree,
        bodyBuilder: (context, card) => ColoredBox(
          key: ValueKey('body-${card.id}'),
          color: const Color(0xFF101010),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}
