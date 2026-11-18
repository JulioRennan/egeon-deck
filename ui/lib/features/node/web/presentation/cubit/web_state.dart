import '../../../../../commons/widgets/web_surface.dart';
import '../../domain/entities/web_node_state.dart';

class WebState {
  const WebState({this.node, this.page});

  final WebNodeState? node;
  final WebPageState? page;

  /// O que a barra de endereço mostra: a página onde ela está agora, senão o
  /// que o core guardou.
  String get address => page?.url ?? node?.url ?? '';

  WebState copyWith({WebNodeState? node, WebPageState? page}) =>
      WebState(node: node ?? this.node, page: page ?? this.page);
}
