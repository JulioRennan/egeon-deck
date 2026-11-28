import '../entities/web_node.dart';

abstract interface class WebRepository {
  /// O estado do nó web [nodeId]. O core manda o estado inteiro a cada mudança.
  Stream<WebNode> watch(String nodeId);

  /// O que se digitou na barra de endereço, cru: o core decide se é endereço
  /// (com esquema ou parecendo host) ou busca, e devolve a URL no estado.
  Future<void> navigate(String nodeId, String typed);

  /// A página navegou sozinha (clique, redirecionamento): o core grava a URL.
  Future<void> reportNavigated(String nodeId, String url);

  Future<void> setProfile(String nodeId, String profile);
}
