import '../../domain/entities/sidebar_bench.dart';

/// O que a linha de uma bancada pode pedir. Quem decide o que fazer com cada
/// pedido (abrir formulário, perguntar ao core) é a casca.
class BenchActions {
  const BenchActions({
    required this.onSelect,
    required this.onRename,
    required this.onDuplicateAsWorktree,
    required this.onEditRules,
    required this.onRecolor,
    required this.onClear,
    required this.onRemove,
  });

  final void Function(String id) onSelect;
  final void Function(SidebarBench bench) onRename;
  final void Function(SidebarBench bench) onDuplicateAsWorktree;
  final void Function(SidebarBench bench) onEditRules;
  final void Function(SidebarBench bench) onRecolor;
  final void Function(SidebarBench bench) onClear;
  final void Function(SidebarBench bench) onRemove;
}
