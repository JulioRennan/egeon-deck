part of 'canvas_tool_cubit.dart';

/// A ferramenta da barra: o que o próximo clique no canvas faz.
sealed class CanvasToolState {
  const CanvasToolState();
}

/// O cursor: clicar seleciona, arrastar o fundo anda a vista.
final class CanvasPointer extends CanvasToolState {
  const CanvasPointer();
}

/// Uma ferramenta armada: o próximo clique cria o nó dela.
final class CanvasArmed extends CanvasToolState {
  const CanvasArmed(this.tool);

  final CanvasTool tool;
}

/// Um componente escolhido no menu do Terminal, com o aviso na tela por uns
/// segundos. Nulo é o shell simples.
final class CanvasAnnouncing extends CanvasToolState {
  const CanvasAnnouncing(this.component);

  final String? component;
}

/// O componente continua armado depois que o aviso some.
final class CanvasComponentArmed extends CanvasToolState {
  const CanvasComponentArmed(this.component);

  final String? component;
}
