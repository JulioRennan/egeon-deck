import 'package:egeon_deck/core/domain/entities/activity_summary.dart';
import 'package:egeon_deck/features/sidebar/domain/entities/sidebar_bench.dart';
import 'package:egeon_deck/features/sidebar/domain/entities/sidebar_tree.dart';

SidebarBench bench(
  String id, {
  String? name,
  String? color,
  bool selected = false,
  bool live = false,
  bool removing = false,
  bool pathExists = true,
  ActivitySummary activity = ActivitySummary.none,
  BenchOwner? owner,
  String? project,
}) => SidebarBench(
  id: id,
  name: name ?? id,
  path: '~/code/$id',
  pathExists: pathExists,
  color: color,
  selected: selected,
  live: live,
  removing: removing,
  activity: activity,
  owner: owner,
  project: project,
);

/// Dois workspaces: o primeiro com um projeto ativo (duas bancadas), um
/// projeto vazio e um guardado na gaveta; mais uma bancada órfã.
SidebarTree sampleTree({bool storedOpen = false, bool collapsed = false}) =>
    SidebarTree(
      workspaces: [
        SidebarWorkspace(
          id: 'w1',
          name: 'Duck',
          storedOpen: storedOpen,
          collapsed: collapsed,
          projects: [
            SidebarProject(
              id: 'p1',
              name: 'egeon',
              path: '~/code/egeon',
              benches: [
                bench('deck', selected: true, live: true, color: 'blue'),
                bench('nexus', color: 'pink'),
              ],
            ),
            const SidebarProject(id: 'p2', name: 'vazio', path: '~/code/vazio'),
            SidebarProject(
              id: 'p3',
              name: 'velho',
              path: '~/code/velho',
              stored: true,
              benches: [bench('antigo')],
            ),
          ],
        ),
        const SidebarWorkspace(id: 'w2', name: 'Casa'),
      ],
      orphans: [bench('solta')],
      recent: [bench('deck', live: true)],
      stale: [bench('antigo')],
    );
