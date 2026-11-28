import 'package:flutter/widgets.dart';

import '../../../../commons/utils/bench_identity.dart';
import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/menu.dart';
import '../../../../theme/egeon_colors.dart';
import '../../domain/entities/sidebar_bench.dart';
import '../../domain/entities/sidebar_tree.dart';
import 'bench_actions.dart';
import 'group_actions.dart';
import 'sidebar_commands.dart';

/// O menu ⋯ de uma bancada. Só entra o que o app sabe fazer: "Encerrar
/// terminais" (sem rota no core) e os atalhos que não estão ligados (↵, F2)
/// ficam de fora. [project] é o projeto da bancada, quando a árvore o conhece
/// (na visão Ativas não) — sem ele não há "nova bancada numa worktree".
List<MenuElement> benchMenu(
  BuildContext context, {
  required SidebarBench bench,
  required BenchActions actions,
  required SidebarCommands commands,
  SidebarProject? project,
}) {
  final c = context.eg;
  return [
    MenuHeader(bench.name),
    MenuItem(
      'Abrir',
      icon: EgIcons.arrowRight,
      onSelected: () => actions.onSelect(bench.id),
    ),
    MenuItem(
      'Renomear…',
      icon: EgIcons.edit,
      onSelected: () => actions.onRename(bench),
    ),
    MenuItem(
      'Mudar cor…',
      leading: bench.color == null
          ? null
          : _Dot(BenchIdentity.of(bench.color).color(c)),
      icon: bench.color == null ? EgIcons.template : null,
      onSelected: () => actions.onRecolor(bench),
    ),
    MenuItem(
      'Salvar como template',
      icon: EgIcons.template,
      onSelected: () => commands.onSaveAsTemplate(bench),
    ),
    MenuItem(
      'Regras da bancada…',
      icon: EgIcons.queue,
      onSelected: () => actions.onEditRules(bench),
    ),
    if (project != null)
      MenuItem(
        'Nova bancada numa worktree',
        icon: EgIcons.worktree,
        onSelected: () => commands.onCreateBenchFromWorktreeIn(project),
      ),
    MenuItem(
      'Duplicar em nova worktree…',
      icon: EgIcons.copy,
      onSelected: () => actions.onDuplicateAsWorktree(bench),
    ),
    const MenuSeparator(),
    MenuItem(
      'Limpar bancada…',
      icon: EgIcons.broom,
      onSelected: () => actions.onClear(bench),
    ),
    const MenuSeparator(),
    MenuItem(
      'Remover bancada…',
      icon: EgIcons.trash,
      danger: true,
      onSelected: () => actions.onRemove(bench),
    ),
  ];
}

/// O menu ⋯ de um projeto. "Abrir no Finder", "Renomear…" e o item de recolher
/// não têm ação no app ainda: ficam de fora.
List<MenuElement> projectMenu({
  required SidebarWorkspace workspace,
  required SidebarProject project,
  required GroupActions actions,
  required SidebarCommands commands,
}) => [
  MenuHeader(project.name),
  if (!project.isMulti)
    MenuItem(
      'Nova bancada…',
      icon: EgIcons.plus,
      onSelected: () => actions.onCreateBench(project),
    ),
  MenuItem(
    'Nova bancada em worktree…',
    icon: EgIcons.worktree,
    onSelected: () => actions.onCreateBenchFromWorktree(project),
  ),
  MenuItem(
    'Copiar caminho',
    icon: EgIcons.copy,
    onSelected: () => commands.onCopyPath(project),
  ),
  const MenuSeparator(),
  MenuItem(
    project.stored ? 'Tirar da gaveta' : 'Guardar na gaveta',
    icon: EgIcons.archive,
    onSelected: () =>
        actions.onSetStored(workspace.id, project.id, stored: !project.stored),
  ),
  const MenuSeparator(),
  MenuItem(
    'Remover projeto…',
    icon: EgIcons.trash,
    danger: true,
    onSelected: () => actions.onRemoveProject(workspace, project),
  ),
];

/// Os projetos do workspace que estão abertos (com bancada para mostrar): é o
/// que "Recolher tudo" fecha.
List<SidebarProject> openProjects(SidebarWorkspace workspace) => [
  for (final p in [...workspace.activeProjects, ...workspace.storedProjects])
    if (!p.collapsed && p.benches.isNotEmpty) p,
];

/// O menu ⋯ de um workspace. "Recolher tudo" fecha cada projeto aberto pelo
/// mesmo comando de recolher de um projeto só (o estado é do core); sem projeto
/// aberto, fica desabilitado.
List<MenuElement> workspaceMenu({
  required SidebarWorkspace workspace,
  required GroupActions actions,
}) => [
  MenuHeader(workspace.name),
  MenuItem(
    'Novo projeto…',
    icon: EgIcons.folder,
    onSelected: () => actions.onCreateProject(workspace),
  ),
  MenuItem(
    'Editar nome e foto…',
    icon: EgIcons.edit,
    onSelected: () => actions.onEditWorkspace(workspace),
  ),
  MenuItem(
    'Recolher tudo',
    icon: EgIcons.chevronUp,
    onSelected: openProjects(workspace).isEmpty
        ? null
        : () {
            for (final project in openProjects(workspace)) {
              actions.onToggleProject(workspace.id, project.id);
            }
          },
  ),
  const MenuSeparator(),
  MenuItem(
    'Remover workspace…',
    icon: EgIcons.trash,
    danger: true,
    onSelected: () => actions.onRemoveWorkspace(workspace),
  ),
];

class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 16,
    height: 16,
    child: Center(
      child: SizedBox(
        width: 10,
        height: 10,
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    ),
  );
}
