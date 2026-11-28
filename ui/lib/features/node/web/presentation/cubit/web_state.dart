part of 'web_cubit.dart';

/// O nó web, fase por fase.
sealed class WebState {
  const WebState();
}

/// O core ainda não mandou o nó: sem página, sem perfil.
final class WebWaiting extends WebState {
  const WebWaiting();
}

/// O core mandou o nó: a URL que ele guardou e o perfil.
sealed class WebWithNode extends WebState {
  const WebWithNode(this.node);

  final WebNode node;
}

/// A página nativa ainda não disse onde está: a barra mostra o que o core
/// guardou.
final class WebOpening extends WebWithNode {
  const WebOpening(super.node);
}

/// A página nativa disse onde está e se carrega; a barra mostra a página.
final class WebShown extends WebWithNode {
  const WebShown(super.node, this.page);

  final WebPageState page;
}
