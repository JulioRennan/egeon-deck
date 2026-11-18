part of 'web_cubit.dart';

/// O nó web: esperando o core dizer qual página e perfil, ou com eles.
sealed class WebState {
  const WebState();
}

/// O core ainda não mandou o nó: sem página, sem perfil.
final class WebWaiting extends WebState {
  const WebWaiting();
}

/// O que o core guardou do nó e, depois que a página nativa abre, onde ela
/// está.
final class WebShown extends WebState {
  const WebShown({required this.node, this.page});

  final WebNode node;
  final WebPageState? page;

  /// O que a barra de endereço mostra: a página onde ela está agora, senão o
  /// que o core guardou.
  String get address => page?.url ?? node.url;

  WebShown copyWith({WebNode? node, WebPageState? page}) =>
      WebShown(node: node ?? this.node, page: page ?? this.page);
}
