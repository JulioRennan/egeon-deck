/// O que a tela sabe fazer quando o core pede de fora (decisão 35). Quem monta a
/// casca implementa; o usecase só roteia e monta a resposta.
abstract interface class ScreenControl {
  /// Troca o modo da bancada ativa. Devolve o modo aplicado, ou `null` se o
  /// nome é inválido ou não há bancada.
  String? setLayout(String mode);

  /// Recolhe (`true`), abre (`false`) ou alterna (`null`) a barra lateral.
  /// Devolve se ficou recolhida.
  bool setSidebarCollapsed(bool? collapsed);

  /// Troca a aba da barra (`all` ou `active`). Devolve a aba, ou `null` se o
  /// nome é inválido.
  String? setSidebarTab(String tab);

  /// Onde cada nó está na tela, em coordenadas de tela, de cima para baixo.
  Future<Map<String, Object?>> geometry();

  /// Grava o PNG de [target] (`window`, `sidebar` ou `<bancada>/<nó>`) em
  /// [file]. Devolve o caminho, ou `erro: …`.
  Future<String> snapshot(String target, String file);
}
