import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/canvas_card.dart';
import '../../domain/entities/canvas_tool.dart';
import '../../domain/entities/canvas_viewport.dart';
import '../../domain/errors/canvas_error.dart';
import '../../domain/usecase/place_node.dart';
import 'canvas_memory.dart';

part 'canvas_tool_state.dart';

/// A ferramenta armada de um canvas e o aviso do componente escolhido. Solta
/// o nó onde o gesto cai; sem componente, o terminal pede o formulário.
class CanvasToolCubit extends Cubit<CanvasToolState> {
  CanvasToolCubit({
    required this.workbenchId,
    required this._placeNode,
    this.bannerTime = const Duration(seconds: 3),
    CanvasMemory? memory,
  }) : _memory = memory,
       super(memory?.tool(workbenchId) ?? const CanvasPointer());

  final CanvasMemory? _memory;

  /// Tamanho mínimo do arrasto para valer como retângulo desenhado: abaixo
  /// disso o clique cria o nó no tamanho padrão da ferramenta.
  static const dragThreshold = 24.0;

  final String workbenchId;
  final PlaceNode _placeNode;

  /// Quanto o aviso do componente escolhido fica na tela.
  final Duration bannerTime;
  Timer? _bannerTimer;
  final _configure = StreamController<Rect>.broadcast();

  /// Terminal solto sem componente: onde ele vai nascer, para quem compõe a
  /// tela abrir o formulário.
  Stream<Rect> get configureTerminal => _configure.stream;

  /// A ferramenta que o próximo clique usa.
  CanvasTool get tool => switch (state) {
    CanvasPointer() => CanvasTool.cursor,
    CanvasArmed(:final tool) => tool,
    CanvasAnnouncing() || CanvasComponentArmed() => CanvasTool.agent,
  };

  void selectTool(CanvasTool tool) {
    if (tool == this.tool && state is! CanvasAnnouncing) return;
    _bannerTimer?.cancel();
    emit(tool == CanvasTool.cursor ? const CanvasPointer() : CanvasArmed(tool));
  }

  /// Escolher um componente arma a ferramenta de terminal: o próximo clique no
  /// canvas é que decide onde ele nasce.
  void pickComponent(String? name) {
    emit(CanvasAnnouncing(name));
    _bannerTimer?.cancel();
    _bannerTimer = Timer(bannerTime, () {
      if (!isClosed && state is CanvasAnnouncing) {
        emit(CanvasComponentArmed(name));
      }
    });
  }

  /// Solta o nó da ferramenta armada. [start] e [end] são os pontos do gesto,
  /// em pixels da janela, convertidos pela [viewport]; um clique sem arrastar
  /// cria no tamanho padrão.
  Future<void> placeByGesture(
    Offset start,
    Offset end,
    CanvasViewport viewport,
  ) async {
    final armed = state;
    final tool = this.tool;
    if (tool == CanvasTool.cursor) return;
    final a = viewport.toDocument(start);
    final b = viewport.toDocument(end);
    final dragged = Rect.fromPoints(a, b);
    final rect =
        (dragged.width < dragThreshold || dragged.height < dragThreshold)
        ? a & tool.defaultNodeSize
        : dragged;
    final frame = Rect.fromLTWH(
      rect.left.roundToDouble(),
      rect.top.roundToDouble(),
      math.max(CanvasCard.minSize.width, rect.width.roundToDouble()),
      math.max(CanvasCard.minSize.height, rect.height.roundToDouble()),
    );
    final component = switch (armed) {
      CanvasAnnouncing(:final component) ||
      CanvasComponentArmed(:final component) => component,
      CanvasPointer() || CanvasArmed() => null,
    };
    // Igual ao Figma: colocou, volta pro cursor. O componente escolhido vale
    // para um nó só — deixá-lo armado faria o clique seguinte criar um revisor
    // sem você ter pedido.
    _bannerTimer?.cancel();
    emit(const CanvasPointer());
    // Sem componente, o terminal de agente é configurado antes de existir: o retângulo
    // marcado vai junto, e o formulário não custa a posição nem o tamanho.
    if (tool == CanvasTool.agent && component == null) {
      _configure.add(frame);
      return;
    }
    await _placeNode(
      workbenchId,
      tool,
      frame,
      component: component,
    ).catchError((_) {}, test: (error) => error is CanvasError);
  }

  @override
  Future<void> close() async {
    // A ferramenta armada fica armada na volta; o aviso, não.
    final kept = state;
    _memory?.keepTool(
      workbenchId,
      kept is CanvasAnnouncing ? CanvasComponentArmed(kept.component) : kept,
    );
    _bannerTimer?.cancel();
    await _configure.close();
    return super.close();
  }
}
