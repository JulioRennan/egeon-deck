import 'dart:ui';

import '../../domain/entities/canvas_card.dart';
import '../../domain/entities/canvas_tool.dart';
import '../../domain/entities/canvas_viewport.dart';
import '../../domain/entities/edge_link.dart';

/// Ligação sendo desenhada agora: origem fixa, ponta seguindo o mouse.
class PendingLink {
  const PendingLink({required this.from, required this.to});

  final String from;

  /// Em coordenadas do documento.
  final Offset to;
}

/// O estado do canvas: os cards com o frame vivo (que acompanha o arrasto
/// antes de o core gravar), as ligações e o estado passageiro de tela —
/// vista, ferramenta armada, realce.
class CanvasState {
  const CanvasState({
    this.viewport = const CanvasViewport(),
    this.cards = const [],
    this.links = const [],
    this.tool = CanvasTool.cursor,
    this.hovered,
    this.pending,
    this.pendingComponent,
    this.banner,
    this.panning = false,
    this.moving = false,
  });

  final CanvasViewport viewport;
  final List<CanvasCard> cards;
  final List<EdgeLink> links;
  final CanvasTool tool;

  /// Ligação sob o cursor. Recebe destaque e mostra os controles.
  final EdgeLink? hovered;
  final PendingLink? pending;

  /// Componente com que o próximo terminal nasce. Nulo = shell padrão. Fica no
  /// canvas porque é estado de gesto: você escolhe "revisor" e o próximo
  /// clique cria um revisor.
  final String? pendingComponent;
  final String? banner;
  final bool panning;

  /// Algo mexeu na vista ou nos cards há pouco (pan, zoom, arrasto): corpos
  /// nativos esperam parar para voltar ao vivo.
  final bool moving;

  Map<String, Rect> get frames => {for (final c in cards) c.id: c.frame};

  Rect? get union {
    if (cards.isEmpty) return null;
    return cards.map((c) => c.frame).reduce((a, b) => a.expandToInclude(b));
  }

  CanvasState copyWith({
    CanvasViewport? viewport,
    List<CanvasCard>? cards,
    List<EdgeLink>? links,
    CanvasTool? tool,
    EdgeLink? Function()? hovered,
    PendingLink? Function()? pending,
    String? Function()? pendingComponent,
    String? Function()? banner,
    bool? panning,
    bool? moving,
  }) => CanvasState(
    viewport: viewport ?? this.viewport,
    cards: cards ?? this.cards,
    links: links ?? this.links,
    tool: tool ?? this.tool,
    hovered: hovered != null ? hovered() : this.hovered,
    pending: pending != null ? pending() : this.pending,
    pendingComponent: pendingComponent != null
        ? pendingComponent()
        : this.pendingComponent,
    banner: banner != null ? banner() : this.banner,
    panning: panning ?? this.panning,
    moving: moving ?? this.moving,
  );
}
