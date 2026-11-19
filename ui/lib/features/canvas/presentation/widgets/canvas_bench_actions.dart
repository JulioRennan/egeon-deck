import 'package:flutter/foundation.dart';

/// Os botões da bancada na barra do canvas (`CanvasToolbar` do Swift): salvar
/// o canvas como template, atualizar o template de origem e abrir uma bancada
/// numa worktree desta. Quem abre os diálogos é a casca.
class CanvasBenchActions {
  const CanvasBenchActions({
    required this.onSaveTemplate,
    required this.onNewWorktree,
    this.originTemplate,
    this.onUpdateTemplate,
  });

  final VoidCallback onSaveTemplate;
  final VoidCallback onNewWorktree;

  /// De qual template a bancada nasceu. Sem ele, o botão de atualizar some: um
  /// "atualizar" sem alvo não tem o que fazer.
  final String? originTemplate;
  final VoidCallback? onUpdateTemplate;
}
