import 'dart:ui';

import '../../../../core/domain/entities/workbench_node.dart';
import 'canvas_card.dart';
import 'canvas_viewport.dart';

/// Onde está a janela na tela, em coordenadas de TELA com origem no topo (as do
/// CGEvent): [x] e [y] são o canto superior esquerdo da área de conteúdo e
/// [screenHeight] a altura da tela em que ela está. Quem sabe isso é a casca.
class WindowFrame {
  const WindowFrame({
    required this.x,
    required this.y,
    required this.screenHeight,
  });

  final double x;
  final double y;
  final double screenHeight;
}

/// O que a rota `/geometry` e a `/shot` perguntam ao canvas de fora: onde cada
/// nó está na tela (estimar de uma captura erra, sobretudo com zoom) e a imagem
/// de um card. Quem roteia e conhece a janela é a casca; o canvas só responde
/// pelo que é dele.
abstract class CanvasProbe {
  /// A bancada que este canvas mostra.
  String get workbenchId;

  /// A geometria do canvas com [window] por cima: coordenadas de tela de cima
  /// para baixo, inteiras. [mode] é o modo da bancada (`canvas` ou `chat`): em
  /// chat o canvas está coberto e não há zoom, então a magnificação sai 1.
  Map<String, Object?> geometry(WindowFrame window, {String mode = 'canvas'});

  /// PNG do card inteiro (cabeçalho e borda) em [file]. Devolve o caminho, ou
  /// `erro: …` quando não deu.
  Future<String> snapshot(String cardId, String file);
}

/// Onde o canvas ao vivo se registra para a casca achá-lo. Um só: o da bancada
/// que está na tela.
class CanvasProbeRegistry {
  CanvasProbe? _active;

  CanvasProbe? get active => _active;

  void register(CanvasProbe probe) => _active = probe;

  /// Só solta se ainda for o mesmo: a bancada nova registra antes de a antiga
  /// sair, e a saída da antiga não pode derrubar o registro da nova.
  void unregister(CanvasProbe probe) {
    if (identical(_active, probe)) _active = null;
  }
}

/// A geometria do Swift: o dicionário que `/geometry` devolve, em coordenadas
/// de tela com origem no topo.
///
/// [origin] é onde o canvas começa dentro da área de conteúdo da janela,
/// e [size] o tamanho dele.
Map<String, Object?> canvasGeometry({
  required String workbenchId,
  required CanvasViewport viewport,
  required List<CanvasCard> cards,
  required Offset origin,
  required Size size,
  required WindowFrame window,
  required double headerHeight,
  String mode = 'canvas',
}) {
  int round(double v) => v.round();
  Map<String, int> rect(Rect r) => {
    'x': round(r.left),
    'y': round(r.top),
    'w': round(r.width),
    'h': round(r.height),
  };

  // Do documento para a tela: a vista, o canto do canvas na janela e a janela.
  final base = Offset(window.x + origin.dx, window.y + origin.dy);
  Rect onScreen(Rect doc) {
    final topLeft = viewport.toScreen(doc.topLeft) + base;
    return Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      doc.width * viewport.zoom,
      doc.height * viewport.zoom,
    );
  }

  final nodes = <Map<String, Object?>>[];
  for (final card in cards) {
    final frame = onScreen(card.frame);
    final header = Rect.fromLTWH(
      frame.left,
      frame.top,
      frame.width,
      headerHeight * viewport.zoom,
    );
    nodes.add({
      'id': card.id,
      'kind': _className(card.kind),
      'docFrame': {
        'x': card.frame.left.truncate(),
        'y': card.frame.top.truncate(),
        'w': card.frame.width.truncate(),
        'h': card.frame.height.truncate(),
      },
      'screenFrame': rect(frame),
      'screenHeader': rect(header),
      // Dentro do cabeçalho, à esquerda do rótulo e longe do botão de fechar.
      'grabPoint': {
        'x': round(header.left + (header.width / 4 < 6 ? header.width / 4 : 6)),
        'y': round(header.center.dy),
      },
    });
  }

  return {
    'workbench': workbenchId,
    'mode': mode,
    'magnification': mode == 'canvas'
        ? (viewport.zoom * 1000).round() / 1000
        : 1,
    'docSize': {
      'w': viewport.document.width.truncate(),
      'h': viewport.document.height.truncate(),
    },
    'scrollOrigin': {
      'x': viewport.origin.dx.truncate(),
      'y': viewport.origin.dy.truncate(),
    },
    'canvasOnScreen': rect(
      Rect.fromLTWH(base.dx, base.dy, size.width, size.height),
    ),
    'nodes': nodes,
  };
}

/// O `kind` do `/geometry` é, como no Swift, o nome da classe da view do nó:
/// scripts externos leem este campo, e a troca de app não pode aparecer neles.
String _className(NodeKind kind) => switch (kind) {
  NodeKind.shell || NodeKind.agent => 'TerminalNode',
  NodeKind.web => 'WebNode',
  NodeKind.queue => 'QueueNode',
};
