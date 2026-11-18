import '../../../../core/domain/entities/activity_summary.dart';
import '../../../../core/domain/entities/organization.dart';
import 'sidebar_bench.dart';

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
  });

  final String id;
  final String name;

  /// O caminho como o usuário o vê (com `~`).
  final String path;
  final bool pathExists;
  final bool collapsed;

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
