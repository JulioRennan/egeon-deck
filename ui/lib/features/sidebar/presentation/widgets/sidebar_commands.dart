import 'package:flutter/widgets.dart';

import '../../domain/entities/sidebar_bench.dart';
import '../../domain/entities/sidebar_tree.dart';

/// O que a barra pede à casca e que não é dela: abrir formulários e falar com
/// o sistema.
class SidebarCommands {
  const SidebarCommands({
    required this.onCreateWorkspace,
    required this.onCreateBench,
    required this.onCreateBenchFromWorktree,
    required this.onCreateBenchIn,
    required this.onCreateBenchFromWorktreeIn,
    required this.onEditWorkspace,
    required this.onCreateProject,
    required this.onRemoveWorkspace,
    required this.onRemoveProject,
    required this.onRename,
    required this.onDuplicateAsWorktree,
    required this.onEditRules,
    required this.onRecolor,
    required this.onClear,
    required this.onRemove,
    required this.onSaveAsTemplate,
    required this.onCopyPath,
  });

  final VoidCallback onCreateWorkspace;
  final VoidCallback onCreateBench;
  final VoidCallback onCreateBenchFromWorktree;
  final void Function(SidebarProject project) onCreateBenchIn;
  final void Function(SidebarProject project) onCreateBenchFromWorktreeIn;
  final void Function(SidebarWorkspace workspace) onEditWorkspace;
  final void Function(SidebarWorkspace workspace) onCreateProject;
  final void Function(SidebarWorkspace workspace) onRemoveWorkspace;
  final void Function(SidebarWorkspace workspace, SidebarProject project)
  onRemoveProject;
  final void Function(SidebarBench bench) onRename;
  final void Function(SidebarBench bench) onDuplicateAsWorktree;
  final void Function(SidebarBench bench) onEditRules;
  final void Function(SidebarBench bench) onRecolor;
  final void Function(SidebarBench bench) onClear;
  final void Function(SidebarBench bench) onRemove;
  final void Function(SidebarBench bench) onSaveAsTemplate;

  /// Copia o caminho do projeto para a área de transferência.
  final void Function(SidebarProject project) onCopyPath;
}
