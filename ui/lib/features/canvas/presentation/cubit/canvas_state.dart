part of 'canvas_cubit.dart';

/// Ligação sendo desenhada agora: origem fixa, ponta seguindo o mouse.
final class PendingLink {
  const PendingLink({required this.from, required this.to});

  final String from;

  /// Em coordenadas do documento.
  final Offset to;
}

/// O canvas: os cards com o frame vivo (que acompanha o arrasto antes de o
/// core gravar), as ligações e a vista — e o que a mão está fazendo nele.
sealed class CanvasState {
  const CanvasState({
    this.viewport = const CanvasViewport(),
    this.cards = const [],
    this.links = const [],
  });

  final CanvasViewport viewport;
  final List<CanvasCard> cards;
  final List<EdgeLink> links;

  Map<String, Rect> get frames => {for (final c in cards) c.id: c.frame};

  Rect? get union {
    if (cards.isEmpty) return null;
    return cards.map((c) => c.frame).reduce((a, b) => a.expandToInclude(b));
  }
}

/// Nada na mão.
final class CanvasIdle extends CanvasState {
  const CanvasIdle({super.viewport, super.cards, super.links});
}

/// Arrastando o fundo: a vista anda com a mão.
final class CanvasPanning extends CanvasState {
  const CanvasPanning({super.viewport, super.cards, super.links});
}

/// Arrastando ou redimensionando um card.
final class CanvasDraggingCard extends CanvasState {
  const CanvasDraggingCard({
    required this.cardId,
    super.viewport,
    super.cards,
    super.links,
  });

  final String cardId;
}

/// Puxando uma ligação do `+` de um terminal.
final class CanvasLinking extends CanvasState {
  const CanvasLinking({
    required this.pending,
    super.viewport,
    super.cards,
    super.links,
  });

  final PendingLink pending;
}

/// O cursor sobre uma ligação: ela ganha destaque e os controles.
final class CanvasLinkHovered extends CanvasState {
  const CanvasLinkHovered({
    required this.link,
    super.viewport,
    super.cards,
    super.links,
  });

  final EdgeLink link;
}
