part of 'sidebar_cubit.dart';

/// A árvore que o core manda e a aba da barra na tela.
final class SidebarState {
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
