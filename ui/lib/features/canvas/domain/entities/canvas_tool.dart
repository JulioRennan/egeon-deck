import '../../../../core/domain/entities/workbench_node.dart';

import 'dart:ui';

/// Ferramentas da barra. `cursor` é o modo normal — navegar, arrastar nó,
/// digitar no terminal. As outras armam o próximo clique no canvas.
enum CanvasTool {
  cursor,
  terminal,
  web,
  queue;

  /// Que tipo de nó esta ferramenta cria. Nem toda ferramenta cria nó.
  NodeKind? get nodeKind => switch (this) {
    cursor => null,
    terminal => NodeKind.shell,
    web => NodeKind.web,
    queue => NodeKind.queue,
  };

  /// Tamanho de quem só clica, sem arrastar. A fila é uma coluna de anotações,
  /// não uma tela de terminal.
  Size get defaultNodeSize =>
      this == queue ? const Size(540, 700) : const Size(720, 460);
}
