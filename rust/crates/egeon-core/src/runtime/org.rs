//! A organização dentro do ator: workspaces, projetos e bancadas carregados
//! do disco, e o que os tópicos `workspaces` e `workbench/<id>/nodes`
//! mostram deles.
//!
//! As regras são das features (`workspace`, `workbench`, `node`, `edge`);
//! aqui só se carrega, grava e monta o estado do fio.

use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::time::SystemTime;

use crate::commons::ids::{NodeId, ProjectId, WorkbenchId, WorkspaceId};
use crate::commons::paths::Paths;
use crate::features::activity::model::{Activity, ActivitySummary};
use crate::features::agent::store::Profiles;
use crate::features::canvas::edges::{has_port, linkable_from};
use crate::features::dispatch::failure::MAX_ATTEMPTS;
use crate::features::edge::model::EdgeLink;
use crate::features::node::model::{NodeConfig, NodeKind as ConfigKind};
use crate::features::path_text::abbreviate_tilde;
use crate::features::workbench::active::ActiveWorkbenches;
use crate::features::workbench::clock::{ClockPhase, WorkbenchClock as BenchClock};
use crate::features::workbench::model::WorkbenchConfig;
use crate::features::workbench::service::assign_missing_colors;
use crate::features::workbench::store as bench_store;
use crate::features::workbench::tabs::tabs_to_reopen;
use crate::features::workspace::model::WorkspaceConfig;
use crate::features::workspace::routes::OrgState;
use crate::features::workspace::service::reconcile;
use crate::features::workspace::store as space_store;
use crate::features::workspace::tree::WorkspaceTree;
use crate::protocol::org::{
    AccessLock, ActiveEntry, ActiveState, ActivityCounts, ClockState, LinkView, NodeActivity,
    NodeKind, NodeView, NodesState, ProjectView, Rect, ViewMode, WorkbenchClock, WorkbenchView,
    WorkspaceView, WorkspacesState,
};

#[derive(Debug, Clone, Default)]
pub struct Org {
    /// Workspaces, bancadas e a faixa de abas: o que os handlers do `org`
    /// recebem.
    pub state: OrgState,
    /// O HOME do usuário, para `~`.
    pub home: String,
    /// Bancadas com os terminais de pé nesta sessão.
    pub live: HashSet<String>,
    /// Bancadas sendo removidas.
    pub removing: HashSet<String>,
    /// Os perfis de agente (`agents.json`): como cada CLI sobe.
    pub profiles: Profiles,
    /// `web-profiles.json`, lido na partida e entregue ao ator.
    pub web_profiles: std::collections::BTreeMap<String, String>,
    /// Quais pastas de projeto, bancada e nó existem, lidas fora do ator
    /// (`probe_paths`): montar a árvore não pergunta ao disco. Pasta que
    /// ainda não foi lida conta como existente até a próxima leitura.
    pub existing: HashMap<String, bool>,
    /// Pastas de bancada que o macOS não deixa ler, com a pasta protegida
    /// por cima: a cortina. Lidas junto com `existing`.
    pub denied: HashMap<String, Option<String>>,
}

/// As pastas de bancada que o sistema recusa. Bloqueia: chamar fora do ator.
pub fn probe_access(paths: Vec<String>, home: &str) -> HashMap<String, Option<String>> {
    use crate::features::workbench::access::FolderAccess;
    paths
        .into_iter()
        .filter_map(|path| match FolderAccess::check(&path, home) {
            FolderAccess::Denied { folder } => Some((path, folder)),
            _ => None,
        })
        .collect()
}

/// Pergunta ao disco por cada pasta. Bloqueia: chamar de `spawn_blocking`.
pub fn probe_paths(paths: Vec<String>) -> HashMap<String, bool> {
    paths
        .into_iter()
        .map(|path| {
            let there = std::path::Path::new(&path).exists();
            (path, there)
        })
        .collect()
}

/// O que a carga achou, para o log e para gravar de volta.
#[derive(Debug, Default)]
pub struct Loaded {
    pub org: Org,
    pub needs_save: bool,
    pub notes: Vec<String>,
}

/// Lê os dois arquivos e concilia, como o `AppDelegate` do Swift na partida.
/// Bloqueia (disco e git): chamar de `spawn_blocking`.
///
/// Arquivo que existe e não abre vira lista vazia, como no Swift — e antes de
/// qualquer gravação por cima, uma cópia `.broken` fica ao lado.
pub fn load(paths: &Paths, home: &str, main_repo: impl Fn(&str) -> Option<String>) -> Loaded {
    let mut notes = Vec::new();
    let benches_file = paths.config(bench_store::FILE);
    let benches = bench_store::load(&benches_file, &paths.config(bench_store::LEGACY_FILE));
    if benches.source == bench_store::Source::Broken {
        notes.push(keep_broken(&benches_file));
    }
    let spaces_file = paths.config(space_store::FILE);
    let spaces = space_store::load(&spaces_file);
    if spaces.as_ref().is_some_and(|s| s.broken) {
        notes.push(keep_broken(&spaces_file));
    }
    let spaces_need_save = spaces.as_ref().is_some_and(|s| s.needs_save);
    let workspaces = spaces.map(|s| s.workspaces).unwrap_or_default();

    let mut workbenches = benches.workbenches;
    let before: Vec<_> = workbenches.iter().map(|w| w.color).collect();
    assign_missing_colors(&mut workbenches);
    let colored = before != workbenches.iter().map(|w| w.color).collect::<Vec<_>>();

    let reconciled = reconcile(&workspaces, &workbenches, home, main_repo);
    notes.extend(reconciled.notes);
    Loaded {
        needs_save: benches.needs_save || spaces_need_save || colored || reconciled.changed,
        notes,
        org: Org {
            state: OrgState {
                open_tabs: tabs_to_reopen(&reconciled.workbenches)
                    .into_iter()
                    .map(|w| w.id.clone())
                    .collect(),
                active_id: reconciled
                    .workbenches
                    .iter()
                    .find(|w| w.tab_active == Some(true) && w.tab_order.is_some())
                    .map(|w| w.id.clone()),
                workspaces: reconciled.workspaces,
                workbenches: reconciled.workbenches,
            },
            home: home.to_owned(),
            ..Org::default()
        },
    }
}

fn keep_broken(file: &Path) -> String {
    let mut copy = file.as_os_str().to_owned();
    copy.push(".broken");
    match std::fs::copy(file, &copy) {
        Ok(_) => format!(
            "{} não abre; cópia em {} antes de gravar por cima",
            file.display(),
            Path::new(&copy).display()
        ),
        Err(err) => format!("{} não abre, e a cópia falhou: {err}", file.display()),
    }
}

/// Grava os dois arquivos. Bloqueia: chamar de `spawn_blocking`.
pub fn save(
    paths: &Paths,
    workspaces: &[WorkspaceConfig],
    workbenches: &[WorkbenchConfig],
) -> Vec<String> {
    let mut errors = Vec::new();
    if let Err(err) = bench_store::save(&paths.config(bench_store::FILE), workbenches) {
        errors.push(err.to_string());
    }
    if let Err(err) = space_store::save(&paths.config(space_store::FILE), workspaces) {
        errors.push(err.to_string());
    }
    errors
}

/// O id do terminal de um nó, que a UI assina em `screen/<id>`: único entre
/// as bancadas e válido como [`NodeId`].
pub fn screen_id(workbench: &str, node: &str) -> Option<NodeId> {
    NodeId::new(format!("{workbench}.{node}")).ok()
}

impl Org {
    fn there(&self, path: &str) -> bool {
        self.existing.get(path).copied().unwrap_or(true)
    }

    /// As pastas das bancadas, para a conferência de acesso.
    pub fn bench_paths(&self) -> Vec<String> {
        self.state
            .workbenches
            .iter()
            .map(|b| b.url_path(&self.home))
            .collect()
    }

    /// A cortina da bancada, se o sistema recusa a pasta.
    pub fn access_of(&self, bench: &WorkbenchConfig) -> Option<AccessLock> {
        use crate::features::workbench::access::FolderAccess;
        let folder = self.denied.get(&bench.url_path(&self.home))?.clone();
        let message = FolderAccess::Denied {
            folder: folder.clone(),
        }
        .message()?;
        Some(AccessLock { folder, message })
    }

    /// As pastas que a árvore e os nós mostram como existentes ou não.
    pub fn watched_paths(&self) -> Vec<String> {
        let projects = self
            .state
            .workspaces
            .iter()
            .flat_map(|w| &w.projects)
            .map(|p| p.url_path(&self.home));
        let benches = self.state.workbenches.iter().flat_map(|b| {
            let nodes = b
                .nodes
                .iter()
                .filter(|n| n.cwd.is_some())
                .map(|n| b.resolved_directory(n, &self.home));
            std::iter::once(b.url_path(&self.home)).chain(nodes)
        });
        let mut all: Vec<String> = projects.chain(benches).collect();
        all.sort();
        all.dedup();
        all
    }

    /// O `directory` da bancada, com o disco do cache: o `cwd` que não
    /// existe abre na raiz.
    fn directory_of(&self, bench: &WorkbenchConfig, node: &NodeConfig) -> (String, bool) {
        let root = bench.url_path(&self.home);
        if node.cwd.is_none() {
            return (root, true);
        }
        let candidate = bench.resolved_directory(node, &self.home);
        if self.there(&candidate) {
            (candidate, true)
        } else {
            (root, false)
        }
    }

    /// Grava na bancada a faixa de abas, como o `recordTabOrder` do Swift: é o
    /// que faz o app reabrir com as mesmas abas.
    pub fn record_tab_order(&mut self) {
        let OrgState {
            workbenches,
            open_tabs,
            active_id,
            ..
        } = &mut self.state;
        for bench in workbenches.iter_mut() {
            bench.tab_order = open_tabs
                .iter()
                .position(|t| *t == bench.id)
                .map(|n| n as i64);
            bench.tab_active = (active_id.as_deref() == Some(bench.id.as_str())).then_some(true);
        }
    }

    pub fn name_of(&self, id: &WorkbenchId) -> Option<String> {
        self.index_of(id)
            .map(|i| self.state.workbenches[i].name.clone())
    }

    pub fn index_of(&self, id: &WorkbenchId) -> Option<usize> {
        self.state
            .workbenches
            .iter()
            .position(|w| w.id == id.as_str())
    }

    /// `live_of` dá, por bancada, a atividade dos terminais (do dispatch) e
    /// o cronômetro (do `org`).
    pub fn workspaces_state(
        &self,
        now: SystemTime,
        live_of: impl Fn(&WorkbenchConfig) -> (Option<ActivitySummary>, Option<BenchClock>),
    ) -> WorkspacesState {
        let tree = WorkspaceTree::new(&self.state.workspaces, &self.state.workbenches);
        let bench_id =
            |index: usize| WorkbenchId::new(self.state.workbenches[index].id.clone()).ok();
        let bench_counts: Vec<ActivityCounts> = self
            .state
            .workbenches
            .iter()
            .map(|b| live_of(b).0.map(counts).unwrap_or_default())
            .collect();
        let project_counts = |id: &str| -> ActivityCounts {
            tree.indices_in_project(id)
                .into_iter()
                .filter_map(|i| bench_counts.get(i).copied())
                .sum()
        };
        let workspaces = self
            .state
            .workspaces
            .iter()
            .filter_map(|space| {
                Some(WorkspaceView {
                    activity: space.projects.iter().map(|p| project_counts(&p.id)).sum(),
                    id: WorkspaceId::new(space.id.clone()).ok()?,
                    name: space.name.clone(),
                    icon: space.icon.clone(),
                    collapsed: space.is_collapsed(),
                    stored_open: space.is_stored_open(),
                    projects: space
                        .projects
                        .iter()
                        .filter_map(|project| {
                            Some(ProjectView {
                                activity: project_counts(&project.id),
                                id: ProjectId::new(project.id.clone()).ok()?,
                                name: project.name.clone(),
                                path: project.path.clone(),
                                exists: self.there(&project.url_path(&self.home)),
                                collapsed: project.is_collapsed(),
                                stored: project.is_stored(),
                                members: project.members.as_ref().map(|ids| {
                                    ids.iter()
                                        .filter_map(|id| ProjectId::new(id.clone()).ok())
                                        .collect()
                                }),
                                workbenches: tree
                                    .indices_in_project(&project.id)
                                    .into_iter()
                                    .filter_map(bench_id)
                                    .collect(),
                            })
                        })
                        .collect(),
                })
            })
            .collect();

        let live: Vec<usize> = (0..self.state.workbenches.len())
            .filter(|&i| self.live.contains(&self.state.workbenches[i].id))
            .collect();
        let last_active: HashMap<usize, SystemTime> = live
            .iter()
            .filter_map(|&i| Some((i, live_of(&self.state.workbenches[i]).1?.last_active?)))
            .collect();
        let active = ActiveWorkbenches::new(&live, &last_active, now);
        let entries = |indices: &[usize], state| {
            indices
                .iter()
                .filter_map(|&i| bench_id(i))
                .map(move |workbench| ActiveEntry { workbench, state })
                .collect::<Vec<_>>()
        };
        let mut active_list = entries(&active.recent, ActiveState::Recent);
        active_list.extend(entries(&active.stale, ActiveState::Stale));

        WorkspacesState {
            workspaces,
            orphans: tree.orphans().into_iter().filter_map(bench_id).collect(),
            workbenches: self
                .state
                .workbenches
                .iter()
                .filter_map(|bench| self.workbench_view(bench, live_of(bench)))
                .collect(),
            active: active_list,
        }
    }

    fn workbench_view(
        &self,
        bench: &WorkbenchConfig,
        (summary, clock): (Option<ActivitySummary>, Option<BenchClock>),
    ) -> Option<WorkbenchView> {
        Some(WorkbenchView {
            id: WorkbenchId::new(bench.id.clone()).ok()?,
            name: bench.name.clone(),
            path: bench.path.clone(),
            project: bench
                .project
                .as_ref()
                .and_then(|p| ProjectId::new(p.clone()).ok()),
            template: bench.template.clone(),
            color: bench.color.map(|c| c.raw().to_owned()),
            view: match bench.view_mode().raw() {
                "chat" => ViewMode::Chat,
                _ => ViewMode::Canvas,
            },
            tab_order: bench.tab_order.and_then(|n| u32::try_from(n).ok()),
            tab_active: bench.tab_active.unwrap_or(false),
            exists: self.there(&bench.url_path(&self.home)),
            live: self.live.contains(&bench.id),
            removing: self.removing.contains(&bench.id),
            rules: bench.rules.clone(),
            activity: summary.map(counts).unwrap_or_default(),
            agents: bench
                .nodes
                .iter()
                .filter(|n| n.kind == ConfigKind::Agent)
                .count() as u32,
            clock: clock.map(|c| clock_view(&c, &summary.unwrap_or_default())),
            access: self.access_of(bench),
        })
    }

    /// `alive` diz se o terminal de `screen/<id>` está de pé; `activity`, o
    /// que o dispatch sabe do endereço `bancada/nó`.
    pub fn nodes_state(
        &self,
        index: usize,
        alive: impl Fn(&NodeId) -> bool,
        activity: impl Fn(&str) -> Option<(Activity, usize)>,
        offset: i64,
    ) -> Option<NodesState> {
        let bench = self.state.workbenches.get(index)?;
        let nodes = bench
            .nodes
            .iter()
            .filter_map(|node| self.node_view(bench, node, &alive, &activity, offset))
            .collect();
        let links = EdgeLink::collapse(bench.edge_list())
            .into_iter()
            .filter_map(|link| {
                Some(LinkView {
                    a: NodeId::new(link.a).ok()?,
                    b: NodeId::new(link.b).ok()?,
                    a_to_b: link.a_to_b,
                    b_to_a: link.b_to_a,
                    max_sends: link.max_sends.and_then(|n| u32::try_from(n).ok()),
                })
            })
            .collect();
        Some(NodesState {
            workbench: WorkbenchId::new(bench.id.clone()).ok()?,
            nodes,
            links,
        })
    }

    fn node_view(
        &self,
        bench: &WorkbenchConfig,
        node: &NodeConfig,
        alive: &impl Fn(&NodeId) -> bool,
        activity: &impl Fn(&str) -> Option<(Activity, usize)>,
        offset: i64,
    ) -> Option<NodeView> {
        let (directory, exists) = self.directory_of(bench, node);
        let screen = match node.kind {
            ConfigKind::Shell | ConfigKind::Agent => screen_id(&bench.id, &node.id),
            ConfigKind::Web | ConfigKind::Queue => None,
        };
        let up = screen.as_ref().is_some_and(alive);
        Some(NodeView {
            id: NodeId::new(node.id.clone()).ok()?,
            kind: match node.kind {
                ConfigKind::Shell => NodeKind::Shell,
                ConfigKind::Agent => NodeKind::Agent,
                ConfigKind::Web => NodeKind::Web,
                ConfigKind::Queue => NodeKind::Queue,
            },
            agent: node.agent.clone(),
            cwd: node.cwd.clone(),
            dir: abbreviate_tilde(&directory, &self.home),
            cmd: node.cmd.clone(),
            model: node.model.clone(),
            effort: node.effort.clone(),
            ultracode: node.ultracode,
            url: node.url.clone(),
            role: node.prompt.clone(),
            rules: node.rules.clone(),
            component: node.component.clone(),
            maestro: node.is_maestro(),
            frame: node.frame().map(|f| Rect {
                x: f.x,
                y: f.y,
                w: f.w,
                h: f.h,
            }),
            screen: screen.filter(|_| up),
            alive: up,
            activity: activity(&bench.address_of(node))
                .map(|(a, pending)| activity_view(&a, pending, offset)),
            exists,
            port: has_port(bench, &node.id),
            linkable: linkable_from(bench, &node.id)
                .into_iter()
                .filter_map(|id| NodeId::new(id).ok())
                .collect(),
        })
    }
}

/// Os contadores da barra e da aba, do `ActivitySummary`.
fn counts(summary: ActivitySummary) -> ActivityCounts {
    ActivityCounts {
        working: summary.working,
        starting: summary.starting,
        attention: summary.attention,
        done: summary.done,
        background: summary.background,
    }
}

/// O cronômetro da bancada em segundos inteiros, e as fases que andam agora
/// (`WorkbenchClock.phases` do Swift).
fn clock_view(clock: &BenchClock, summary: &ActivitySummary) -> WorkbenchClock {
    let seconds = |phase| clock.get(phase).max(0.0) as u64;
    WorkbenchClock {
        running: seconds(ClockPhase::Running),
        waiting: seconds(ClockPhase::Waiting),
        failed: seconds(ClockPhase::Failed),
        ticking: BenchClock::phases(summary)
            .into_iter()
            .map(|phase| match phase {
                ClockPhase::Running => ClockState::Running,
                ClockPhase::Waiting => ClockState::Waiting,
                ClockPhase::Failed => ClockState::Failed,
            })
            .collect(),
    }
}

/// A atividade no fio: o nome do caso, a regra de atenção e o rótulo do
/// cabeçalho do `Activity` do Swift. `offset` é o fuso, em segundos, para a
/// hora da nova tentativa.
pub fn activity_view(activity: &Activity, pending: usize, offset: i64) -> NodeActivity {
    let mut view = NodeActivity {
        state: String::new(),
        needs_attention: activity.needs_attention(),
        waiting_on: Vec::new(),
        error: None,
        attempt: None,
        label: None,
        glyph: None,
        tone: None,
        pending: u32::try_from(pending).unwrap_or(u32::MAX),
    };
    let (state, glyph, label, tone): (&str, Option<&str>, Option<String>, Option<&str>) =
        match activity {
            Activity::Starting => ("starting", Some("spinner"), Some("preparando".into()), None),
            Activity::Working => ("working", Some("spinner"), Some("trabalhando".into()), None),
            Activity::Background => (
                "background",
                Some("hourglass"),
                Some("em segundo plano".into()),
                None,
            ),
            Activity::Awaiting(peers) => {
                view.waiting_on = peers.clone();
                let who = if peers.is_empty() {
                    "vizinho".to_owned()
                } else {
                    peers.join(", ")
                };
                (
                    "awaiting",
                    Some("hourglass"),
                    Some(format!("aguardando {who}")),
                    None,
                )
            }
            Activity::Waiting => (
                "waiting",
                Some("dot"),
                Some("terminou".into()),
                Some("green"),
            ),
            Activity::Asking => (
                "asking",
                Some("dot"),
                Some("precisa de você".into()),
                Some("orange"),
            ),
            Activity::Retrying { attempt, at } => {
                view.attempt = Some(*attempt);
                let label = format!(
                    "tentando de novo às {} ({attempt}/{MAX_ATTEMPTS})",
                    clock_text(*at, offset)
                );
                ("retrying", Some("retry"), Some(label), None)
            }
            Activity::Failed(error) => {
                view.error = Some(error.clone());
                (
                    "failed",
                    Some("dot"),
                    Some(format!("falhou — {error}")),
                    Some("red"),
                )
            }
            Activity::Dead => (
                "dead",
                Some("cross"),
                Some("processo encerrado".into()),
                Some("red"),
            ),
            Activity::Ready => ("ready", None, None, None),
        };
    view.state = state.to_owned();
    view.glyph = glyph.map(str::to_owned);
    view.label = label;
    view.tone = tone.map(str::to_owned);
    view
}

/// `HH:mm` na hora local, como o `Activity.clock` do Swift.
fn clock_text(at: SystemTime, offset: i64) -> String {
    let secs = at
        .duration_since(SystemTime::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
        + offset;
    let day = secs.rem_euclid(86_400);
    format!("{:02}:{:02}", day / 3600, day % 3600 / 60)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn atencao_so_em_quem_pergunta_ou_falhou() {
        let asking = activity_view(&Activity::Asking, 0, 0);
        assert_eq!(
            (asking.state.as_str(), asking.needs_attention),
            ("asking", true)
        );
        let failed = activity_view(&Activity::Failed("429".into()), 0, 0);
        assert!(failed.needs_attention);
        assert_eq!(failed.error.as_deref(), Some("429"));
        let waiting = activity_view(&Activity::Waiting, 0, 0);
        assert!(
            !waiting.needs_attention,
            "terminou não interrompe (ADR-024)"
        );
        let awaiting = activity_view(&Activity::Awaiting(vec!["deck/rev".into()]), 0, 0);
        assert_eq!(awaiting.waiting_on, ["deck/rev"]);
        assert!(!awaiting.needs_attention);
    }

    /// O cabeçalho do card, como o `Activity.label` e o `color` do Swift.
    #[test]
    fn rotulo_glifo_e_cor_do_cabecalho() {
        let view = |a: Activity, pending| {
            let v = activity_view(&a, pending, -3 * 3600);
            (v.label, v.glyph, v.tone, v.pending)
        };
        let s = |t: &str| Some(t.to_owned());
        assert_eq!(
            view(Activity::Working, 2),
            (s("trabalhando"), s("spinner"), None, 2)
        );
        assert_eq!(
            view(Activity::Waiting, 0),
            (s("terminou"), s("dot"), s("green"), 0)
        );
        assert_eq!(
            view(Activity::Asking, 0),
            (s("precisa de você"), s("dot"), s("orange"), 0)
        );
        assert_eq!(
            view(Activity::Awaiting(vec![]), 0).0,
            s("aguardando vizinho")
        );
        assert_eq!(
            view(Activity::Dead, 0),
            (s("processo encerrado"), s("cross"), s("red"), 0)
        );
        assert_eq!(view(Activity::Ready, 1), (None, None, None, 1));
        // 17:05 UTC é 14:05 em UTC-3.
        let at = SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(17 * 3600 + 5 * 60);
        assert_eq!(
            view(Activity::Retrying { attempt: 2, at }, 0).0,
            s("tentando de novo às 14:05 (2/3)")
        );
    }
}
