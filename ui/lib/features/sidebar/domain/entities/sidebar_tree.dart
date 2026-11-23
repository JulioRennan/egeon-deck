import '../../../../core/domain/entities/activity_summary.dart';
import '../../../../core/domain/entities/organization.dart';
import 'sidebar_bench.dart';
import 'sidebar_filters.dart';
import 'stack_badge.dart';

class SidebarProject {
  const SidebarProject({
    required this.id,
    required this.name,
    this.path = '',
    this.pathExists = true,
    this.collapsed = false,
    this.stored = false,
    this.joins = const [],
    this.benches = const [],
    this.activity = ActivitySummary.none,
    this.stacks = const [],
  });

  final String id;
  final String name;

  /// O caminho como o usuário o vê (com `~`).
  final String path;
  final bool pathExists;
  final bool collapsed;

  /// As tecnologias do projeto, em selos sob o nome. Vazio enquanto o core não
  /// detecta a stack.
  final List<StackBadge> stacks;

  /// Guardado na gaveta do workspace.
  final bool stored;

  /// Multi-projeto: os nomes dos projetos que ele reúne.
  final List<String> joins;
  final List<SidebarBench> benches;

  bool get isMulti => joins.isNotEmpty;

  /// O estado das bancadas dele, como o core o soma.
  final ActivitySummary activity;
}

class SidebarWorkspace {
  const SidebarWorkspace({
    required this.id,
    required this.name,
    this.icon,
    this.collapsed = false,
    this.storedOpen = false,
    this.projects = const [],
    this.activity = ActivitySummary.none,
  });

  final String id;
  final String name;
  final String? icon;
  final bool collapsed;

  /// A gaveta dos guardados está aberta.
  final bool storedOpen;
  final List<SidebarProject> projects;

  List<SidebarProject> get activeProjects => [
    for (final p in projects)
      if (!p.stored) p,
  ];
  List<SidebarProject> get storedProjects => [
    for (final p in projects)
      if (p.stored) p,
  ];

  /// O estado de todas as bancadas dele, como o core o soma.
  final ActivitySummary activity;
  int get benchCount =>
      projects.fold(0, (total, p) => total + p.benches.length);
}

/// A barra lateral inteira: a árvore workspace → projeto → bancada, as
/// bancadas órfãs e a aba Ativas. A regra de onde cada bancada cai é do core.
class SidebarTree {
  const SidebarTree({
    this.workspaces = const [],
    this.orphans = const [],
    this.recent = const [],
    this.stale = const [],
  });

  final List<SidebarWorkspace> workspaces;

  /// Bancadas sem projeto que as receba.
  final List<SidebarBench> orphans;

  /// Aba Ativas: rodaram nas últimas 24 horas / estão de pé há mais que isso.
  final List<SidebarBench> recent;
  final List<SidebarBench> stale;

  int get activeCount => recent.length + stale.length;

  /// Alguma bancada precisa de você.
  bool get wantsAttention =>
      workspaces.any((w) => w.activity.wantsAttention) ||
      orphans.any((b) => b.activity.wantsAttention);

  /// A árvore só com o que casa com [query] no nome da bancada, do projeto ou
  /// do workspace (sem diferenciar maiúsculas). Uma busca de workspace ou de
  /// projeto traz tudo que há dentro dele; o que não tem bancada nem nome que
  /// case some. Busca vazia devolve a própria árvore.
  SidebarTree filtered(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return this;
    bool has(String text) => text.toLowerCase().contains(q);
    bool benchMatches(SidebarBench b, String? project, String? workspace) =>
        has(b.name) ||
        (project != null && has(project)) ||
        (workspace != null && has(workspace));
    return SidebarTree(
      workspaces: [
        for (final w in workspaces)
          if (_keep(w, has, benchMatches))
            _filterWorkspace(w, has, benchMatches),
      ],
      orphans: [
        for (final b in orphans)
          if (benchMatches(b, null, null)) b,
      ],
      recent: [
        for (final b in recent)
          if (benchMatches(b, b.project, b.owner?.name)) b,
      ],
      stale: [
        for (final b in stale)
          if (benchMatches(b, b.project, b.owner?.name)) b,
      ],
    );
  }

  static bool _keep(
    SidebarWorkspace w,
    bool Function(String) has,
    bool Function(SidebarBench, String?, String?) matches,
  ) =>
      has(w.name) ||
      w.projects.any(
        (p) => has(p.name) || p.benches.any((b) => matches(b, p.name, w.name)),
      );

  static SidebarWorkspace _filterWorkspace(
    SidebarWorkspace w,
    bool Function(String) has,
    bool Function(SidebarBench, String?, String?) matches,
  ) {
    final all = has(w.name);
    return SidebarWorkspace(
      id: w.id,
      name: w.name,
      icon: w.icon,
      collapsed: false,
      storedOpen: w.storedOpen,
      activity: w.activity,
      projects: [
        for (final p in w.projects)
          if (all ||
              has(p.name) ||
              p.benches.any((b) => matches(b, p.name, w.name)))
            SidebarProject(
              id: p.id,
              name: p.name,
              path: p.path,
              pathExists: p.pathExists,
              collapsed: false,
              stored: p.stored,
              joins: p.joins,
              activity: p.activity,
              stacks: p.stacks,
              benches: [
                for (final b in p.benches)
                  if (all || has(p.name) || matches(b, p.name, w.name)) b,
              ],
            ),
      ],
    );
  }

  /// A árvore só com as bancadas que passam em [filters]; o projeto e o
  /// workspace que ficam sem bancada saem. As órfãs não são de workspace
  /// nenhum, então saem quando se escolhe um. Sem filtro devolve a própria.
  SidebarTree narrowed(SidebarFilters filters) {
    if (filters.isEmpty) return this;
    final only = filters.workspaceId;
    bool keep(SidebarBench b) => filters.matches(b);
    bool fromOnly(SidebarBench b) => only == null || b.owner?.id == only;
    return SidebarTree(
      workspaces: [
        for (final w in workspaces)
          if (only == null || w.id == only) ?_narrowWorkspace(w, keep),
      ],
      orphans: only == null ? orphans.where(keep).toList() : const [],
      recent: recent.where((b) => keep(b) && fromOnly(b)).toList(),
      stale: stale.where((b) => keep(b) && fromOnly(b)).toList(),
    );
  }

  static SidebarWorkspace? _narrowWorkspace(
    SidebarWorkspace w,
    bool Function(SidebarBench) keep,
  ) {
    final projects = [
      for (final p in w.projects)
        if (p.benches.any(keep))
          SidebarProject(
            id: p.id,
            name: p.name,
            path: p.path,
            pathExists: p.pathExists,
            collapsed: false,
            stored: p.stored,
            joins: p.joins,
            activity: p.activity,
            stacks: p.stacks,
            benches: p.benches.where(keep).toList(),
          ),
    ];
    if (projects.isEmpty) return null;
    return SidebarWorkspace(
      id: w.id,
      name: w.name,
      icon: w.icon,
      collapsed: false,
      storedOpen: w.storedOpen,
      activity: w.activity,
      projects: projects,
    );
  }

  int get allCount =>
      workspaces.fold(0, (total, w) => total + w.benchCount) + orphans.length;
  bool get isEmpty => allCount == 0;

  /// Monta a barra a partir da organização: cada linha de bancada vem do mapa
  /// de bancadas.
  factory SidebarTree.fromOrganization(Organization org) {
    SidebarBench? row(String id, {OrgWorkspace? owner}) {
      final b = org.bench(id);
      if (b == null) return null;
      final project = b.project == null ? null : org.project(b.project!);
      return SidebarBench(
        id: b.id,
        name: b.name,
        path: b.path,
        pathExists: b.exists,
        color: b.color,
        selected: b.tabActive,
        live: b.live,
        removing: b.removing,
        activity: b.activity,
        clock: b.clock,
        owner: owner == null
            ? null
            : BenchOwner(id: owner.id, name: owner.name, icon: owner.icon),
        project: owner == null ? null : project?.name,
      );
    }

    List<SidebarBench> rows(Iterable<String> ids) => [
      for (final id in ids) ?row(id),
    ];

    List<SidebarBench> activeRows(ActiveState state) => [
      for (final a in org.active)
        if (a.state == state)
          ?row(a.workbench, owner: _ownerOf(org, a.workbench)),
    ];

    return SidebarTree(
      workspaces: [
        for (final w in org.workspaces)
          SidebarWorkspace(
            id: w.id,
            name: w.name,
            icon: w.icon,
            collapsed: w.collapsed,
            storedOpen: w.storedOpen,
            activity: w.activity,
            projects: [
              for (final p in w.projects)
                SidebarProject(
                  id: p.id,
                  name: p.name,
                  path: p.path,
                  pathExists: p.exists,
                  collapsed: p.collapsed,
                  stored: p.stored,
                  joins: [
                    for (final m in p.members ?? const <String>[])
                      ?org.project(m)?.name,
                  ],
                  benches: rows(p.benches),
                  activity: p.activity,
                ),
            ],
          ),
      ],
      orphans: rows(org.orphans),
      recent: activeRows(ActiveState.recent),
      stale: activeRows(ActiveState.stale),
    );
  }

  static OrgWorkspace? _ownerOf(Organization org, String benchId) {
    final project = org.bench(benchId)?.project;
    return project == null ? null : org.workspaceOf(project);
  }
}
