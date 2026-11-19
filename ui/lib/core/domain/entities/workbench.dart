import 'view_mode.dart';

/// A bancada na tela, como o core Rust a conta. Lida pela casca, pela faixa de
/// abas, pelo canvas e pelo chat.
class Workbench {
  const Workbench({
    required this.id,
    required this.name,
    required this.path,
    this.color,
    this.view = ViewMode.canvas,
    this.template,
  });

  final String id;
  final String name;

  /// O caminho como o usuário o vê (com `~`).
  final String path;

  /// Nome da cor (`blue`, `sand`…); quem a resolve é o tema.
  final String? color;
  final ViewMode view;

  /// O template de bancada de que ela nasceu; ausente, nenhum.
  final String? template;
}
