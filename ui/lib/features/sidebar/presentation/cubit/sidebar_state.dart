import '../../domain/entities/sidebar_tree.dart';
import '../widgets/sidebar_segments.dart';

class SidebarState {
  const SidebarState({
    this.tree = const SidebarTree(),
    this.tab = SidebarTab.all,
  });

  final SidebarTree tree;

  /// Qual das duas abas está na tela: estado passageiro da UI.
  final SidebarTab tab;

  SidebarState copyWith({SidebarTree? tree, SidebarTab? tab}) =>
      SidebarState(tree: tree ?? this.tree, tab: tab ?? this.tab);
}
