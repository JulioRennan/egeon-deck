import 'dart:ui';

import '../entities/canvas_card.dart';
import '../entities/canvas_tool.dart';
import '../entities/edge_link.dart';

/// O que o core Rust sabe do canvas de uma bancada: os cards com frame e as
/// ligações. Zoom e pan não entram — são estado de tela.
class CanvasSnapshot {
  const CanvasSnapshot({this.cards = const [], this.links = const []});

  final List<CanvasCard> cards;
  final List<EdgeLink> links;
}

abstract interface class CanvasRepository {
  /// O core manda o estado inteiro a cada mudança; a UI não aplica diferença.
  Stream<CanvasSnapshot> watch(String workbenchId);

  /// Frames gravados ao soltar um arrasto ou um resize — só no fim do gesto,
  /// para não reescrever o arquivo a cada pixel.
  Future<void> saveFrames(String workbenchId, Map<String, Rect> frames);

  /// Cria o nó da ferramenta no retângulo, já em coordenadas do documento.
  Future<void> placeNode(
    String workbenchId,
    CanvasTool tool,
    Rect frame, {
    String? component,
  });

  /// Cria a ligação dirigida `from → to`.
  Future<void> createLink(String workbenchId, String from, String to);

  Future<void> removeLink(String workbenchId, EdgeLink link);

  /// Próximo estado do botão de direção: ida → ida e volta → volta → ida.
  Future<void> cycleLink(String workbenchId, EdgeLink link);

  Future<void> setLinkLimit(String workbenchId, EdgeLink link, int? maxSends);

  Future<void> removeNode(String workbenchId, String nodeId);

  /// O ⌘-clique no subtítulo: a pasta do terminal no Finder.
  Future<void> openFolder(String workbenchId, String nodeId);

  /// O foco da interface, para o core decidir notificação e o que é tecla do
  /// usuário: o app ganhou ou perdeu o foco, e qual nó tem o foco de teclado
  /// (clique no card ou no terminal). Sem nó, o app está em segundo plano.
  /// [window] é o tamanho da área do canvas: o core o usa para dar o frame
  /// padrão a quem nasce sem.
  Future<void> setFocus({
    required bool appActive,
    String? workbenchId,
    String? nodeId,
    Size? window,
  });
}
