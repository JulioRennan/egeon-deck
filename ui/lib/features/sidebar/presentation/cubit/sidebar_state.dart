part of 'sidebar_cubit.dart';

/// A barra lateral: a árvore que o core manda, mostrada inteira ou só com o
/// que está ativo — a aba é estado passageiro da UI.
sealed class SidebarState {
  const SidebarState(this.tree);

  final SidebarTree tree;
}

/// A aba "Todas".
final class SidebarAll extends SidebarState {
  const SidebarAll([super.tree = const SidebarTree()]);
}

/// A aba "Ativas".
final class SidebarActive extends SidebarState {
  const SidebarActive(super.tree);
}
