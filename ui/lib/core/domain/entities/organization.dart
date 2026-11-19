import '../../../commons/utils/wire.dart';
import 'activity_summary.dart';
import 'view_mode.dart';
import 'workbench_clock.dart';

/// Uma bancada como o tópico `workspaces` a traz.
class OrgBench {
  const OrgBench({
    required this.id,
    required this.name,
    required this.path,
    this.project,
    this.template,
    this.color,
    this.view = ViewMode.canvas,
    this.tabOrder,
    this.tabActive = false,
    this.exists = true,
    this.live = false,
    this.removing = false,
    this.rules,
    this.agents = 0,
    this.activity = ActivitySummary.none,
    this.clock,
    this.access,
    this.busy,
    this.banner,
  });

  final String id;
  final String name;
  final String path;

  /// Id do projeto a que pertence; ausente é órfã.
  final String? project;

  /// O template de bancada de que nasceu; ausente, nenhum.
  final String? template;
  final String? color;
  final ViewMode view;

  /// A posição da aba; ausente, a bancada não está aberta.
  final int? tabOrder;
  final bool tabActive;

  /// A pasta existe no disco.
  final bool exists;

  /// Os terminais da bancada estão de pé.
  final bool live;

  /// A remoção está em curso.
  final bool removing;

  /// As regras da bancada; ausente, sem regras.
  final String? rules;

  /// Quantos agentes a bancada tem.
  final int agents;
  final ActivitySummary activity;

  /// O cronômetro; ausente até a bancada ter rodado.
  final WorkbenchClock? clock;

  /// Sem acesso à pasta: o aviso pronto do core. Ausente, tudo certo.
  final FolderAccess? access;

  /// O "um instante" (limpando, removendo): o texto pronto do core.
  final String? busy;

  /// A faixa do shell (a cópia do que o git não versiona), pronta do core.
  final String? banner;

  factory OrgBench.fromMap(Map<String, Object?> map) => OrgBench(
    id: map['id']! as String,
    name: map['name']! as String,
    path: map['path']! as String,
    project: map['project'] as String?,
    template: map['template'] as String?,
    color: map['color'] as String?,
    view: ViewMode.fromWire(map['view']),
    tabOrder: map['tab_order'] as int?,
    tabActive: map['tab_active'] as bool? ?? false,
    exists: map['exists'] as bool? ?? true,
    live: map['live'] as bool? ?? false,
    removing: map['removing'] as bool? ?? false,
    rules: map['rules'] as String?,
    agents: map['agents'] as int? ?? 0,
    activity: ActivitySummary.fromMap(
      (map['activity'] as Map<String, Object?>?) ?? const {},
    ),
    clock: map['clock'] == null
        ? null
        : WorkbenchClock.fromMap(map['clock']! as Map<String, Object?>),
    access: map['access'] == null
        ? null
        : FolderAccess.fromMap(map['access']! as Map<String, Object?>),
    busy: map['busy'] as String?,
    banner: map['banner'] as String?,
  );
}

/// A pasta da bancada que o sistema não deixa abrir: qual é e o texto do aviso,
/// montado pelo core.
class FolderAccess {
  const FolderAccess({required this.message, this.folder});

  factory FolderAccess.fromMap(Map<String, Object?> map) => FolderAccess(
    folder: map['folder'] as String?,
    message: map['message'] as String? ?? '',
  );

  final String? folder;
  final String message;
}

class OrgProject {
  const OrgProject({
    required this.id,
    required this.name,
    required this.path,
    this.exists = true,
    this.collapsed = false,
    this.stored = false,
    this.members,
    this.benches = const [],
    this.activity = ActivitySummary.none,
  });

  final String id;
  final String name;
  final String path;

  /// A pasta do projeto existe no disco.
  final bool exists;
  final bool collapsed;
  final bool stored;

  /// Multi-projeto: os ids dos projetos que ele junta; ausente, é simples.
  final List<String>? members;

  /// Ids das bancadas do projeto, na ordem.
  final List<String> benches;

  /// O estado das bancadas dele, já somado pelo core.
  final ActivitySummary activity;

  bool get isMulti => members != null;

  factory OrgProject.fromMap(Map<String, Object?> map) => OrgProject(
    id: map['id']! as String,
    name: map['name']! as String,
    path: map['path'] as String? ?? '',
    exists: map['exists'] as bool? ?? true,
    collapsed: map['collapsed'] as bool? ?? false,
    stored: map['stored'] as bool? ?? false,
    members: map['members'] == null
        ? null
        : [for (final m in map['members']! as List<Object?>) m! as String],
    benches: [
      for (final b in (map['workbenches'] as List<Object?>? ?? const []))
        b! as String,
    ],
    activity: ActivitySummary.fromMap(
      (map['activity'] as Map<String, Object?>?) ?? const {},
    ),
  );
}

class OrgWorkspace {
  const OrgWorkspace({
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
  final bool storedOpen;
  final List<OrgProject> projects;

  /// O estado de todas as bancadas dele, já somado pelo core.
  final ActivitySummary activity;

  factory OrgWorkspace.fromMap(Map<String, Object?> map) => OrgWorkspace(
    id: map['id']! as String,
    name: map['name']! as String,
    icon: map['icon'] as String?,
    collapsed: map['collapsed'] as bool? ?? false,
    storedOpen: map['stored_open'] as bool? ?? false,
    projects: mapList(map['projects'], OrgProject.fromMap),
    activity: ActivitySummary.fromMap(
      (map['activity'] as Map<String, Object?>?) ?? const {},
    ),
  );
}

/// Estado de uma bancada de pé na aba Ativas.
enum ActiveState {
  recent,
  stale;

  static ActiveState fromWire(Object? raw) =>
      raw == 'recent' ? ActiveState.recent : ActiveState.stale;
}

class ActiveEntry {
  const ActiveEntry(this.workbench, this.state);

  final String workbench;
  final ActiveState state;
}

/// A organização inteira: o que o core manda no tópico `workspaces`. A barra
/// lateral, as abas e a casca leem dela, cada uma do seu jeito.
class Organization {
  const Organization({
    this.workspaces = const [],
    this.orphans = const [],
    this.workbenches = const [],
    this.active = const [],
  });

  final List<OrgWorkspace> workspaces;

  /// Ids das bancadas sem projeto que as receba.
  final List<String> orphans;
  final List<OrgBench> workbenches;
  final List<ActiveEntry> active;

  OrgBench? bench(String id) {
    for (final b in workbenches) {
      if (b.id == id) return b;
    }
    return null;
  }

  OrgWorkspace? workspace(String id) {
    for (final w in workspaces) {
      if (w.id == id) return w;
    }
    return null;
  }

  OrgProject? project(String id) {
    for (final w in workspaces) {
      for (final p in w.projects) {
        if (p.id == id) return p;
      }
    }
    return null;
  }

  /// O workspace que tem o projeto.
  OrgWorkspace? workspaceOf(String projectId) {
    for (final w in workspaces) {
      if (w.projects.any((p) => p.id == projectId)) return w;
    }
    return null;
  }

  /// As abas: as bancadas com posição, nessa ordem.
  List<OrgBench> get openTabs => [
    for (final b in workbenches)
      if (b.tabOrder != null) b,
  ]..sort((a, b) => a.tabOrder!.compareTo(b.tabOrder!));

  /// A bancada na tela.
  OrgBench? get activeBench {
    for (final b in workbenches) {
      if (b.tabActive) return b;
    }
    return null;
  }

  factory Organization.fromMap(Map<String, Object?> map) => Organization(
    workspaces: mapList(map['workspaces'], OrgWorkspace.fromMap),
    orphans: [
      for (final o in (map['orphans'] as List<Object?>? ?? const []))
        o! as String,
    ],
    workbenches: mapList(map['workbenches'], OrgBench.fromMap),
    active: [
      for (final a in (map['active'] as List<Object?>? ?? const []))
        ActiveEntry(
          (a! as Map<String, Object?>)['workbench']! as String,
          ActiveState.fromWire((a as Map<String, Object?>)['state']),
        ),
    ],
  );
}
