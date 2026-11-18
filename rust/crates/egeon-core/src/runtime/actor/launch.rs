//! Os terminais dos nós de uma bancada: o que sobe quando ela abre.
//!
//! A linha, o ambiente e o gancho do shell são do `features::node::launch`
//! (porte do `launchPlan` e do ambiente do `TerminalNode`); aqui só se lança.

use std::path::PathBuf;

use super::Actor;
use crate::commons::ids::NodeId;
use crate::features::agent::claude::catalog::applies_to;
use crate::features::agent::model::AgentProfile;
use crate::features::node::edit::prepare_conversation;
use crate::features::node::launch::{
    ChildContext, catalog, launch_plan, node_environment, rules_for,
};
use crate::features::node::model::{NodeConfig, NodeKind};
use crate::features::workbench::frames::apply_default_frames;
use crate::features::workbench::model::WorkbenchConfig;
use crate::features::workspace::routes::OrgEffect;
use crate::runtime::org::screen_id;

/// O arquivo de ganchos do Claude que o `--settings` aponta.
pub const HOOK_FILE: &str = "claude-hooks.json";

impl Actor {
    /// Sobe os terminais dos nós de shell e de agente da bancada `id` que
    /// ainda não estão de pé, como o `build(index)` do Swift ao ativar uma
    /// bancada pela primeira vez. Web e fila não têm processo.
    pub(super) fn open_terminals(&mut self, id: &str) {
        // O build da bancada dá frame a quem não tem e resgata quem foi gravado
        // fora do documento; o resultado é gravado e dali em diante manda o
        // arquivo. Sem a janela da UI, vale o mínimo de 900×600.
        let window = self.window;
        if let Some(live) = self.org.state.workbenches.iter_mut().find(|w| w.id == id) {
            let before: Vec<_> = live
                .nodes
                .iter()
                .map(|n| n.frame().map(|f| (f.x, f.y)))
                .collect();
            for line in apply_default_frames(live, window) {
                crate::log!("{line}");
            }
            let after: Vec<_> = live
                .nodes
                .iter()
                .map(|n| n.frame().map(|f| (f.x, f.y)))
                .collect();
            if before != after {
                self.apply_org(vec![OrgEffect::PersistWorkbenches]);
            }
        }
        let Some(bench) = self
            .org
            .state
            .workbenches
            .iter()
            .find(|w| w.id == id)
            .cloned()
        else {
            return;
        };
        // Viva antes dos terminais: o lançamento confere que a bancada está
        // aberta (`launch_gone`).
        self.org.live.insert(bench.id.clone());
        for node in &bench.nodes {
            self.open_terminal(&bench, node);
        }
    }

    /// Sobe o terminal de um nó, se for de shell ou de agente e ainda não
    /// estiver de pé: o que criar um nó e reiniciar um nó editado usam.
    pub(super) fn open_terminal(&mut self, bench: &WorkbenchConfig, node: &NodeConfig) {
        if !matches!(node.kind, NodeKind::Shell | NodeKind::Agent) {
            return;
        }
        let Some(terminal) = screen_id(&bench.id, &node.id) else {
            crate::log!(
                "bancada {}: nó \"{}\" sem id de terminal válido",
                bench.name,
                node.id
            );
            return;
        };
        if self
            .nodes
            .get(&terminal)
            .is_some_and(|n| n.session.is_some())
        {
            return;
        }
        let home = self.config.default_cwd.clone();
        let home_text = home.to_string_lossy().into_owned();
        let paths = self.config.paths.clone();
        let hook_file = paths.config(HOOK_FILE).to_string_lossy().into_owned();
        let egeon_home = paths.home().to_string_lossy().into_owned();
        let zsh_dir = paths.config("zsh");
        let deck = self.config.flavor.identifier();
        let flavor = if self.config.flavor.is_dev() {
            "dev"
        } else {
            ""
        };
        let profile = node
            .agent
            .as_ref()
            .and_then(|a| self.org.profiles.get(a))
            .cloned();
        // O `prepared` do Swift: agente que guarda conversa ganha o id uma vez,
        // antes de subir, e a bancada é gravada — sem ele o `--session-id` e o
        // `--resume` do launch_plan nunca entram.
        let mut node = node.clone();
        if prepare_conversation(&mut node, profile.as_ref()) {
            if let Some(stored) = self
                .org
                .state
                .workbenches
                .iter_mut()
                .find(|w| w.id == bench.id)
                .and_then(|w| w.nodes.iter_mut().find(|n| n.id == node.id))
            {
                *stored = node.clone();
            }
            self.persist();
        }
        let node = &node;
        let address = bench.address_of(node);
        let plan = launch_plan(
            node,
            profile.as_ref(),
            catalog(node).as_deref(),
            rules_for(node, bench.rules.as_deref()).as_deref(),
            &hook_file,
        );
        let ctx = ChildContext {
            base: self.base_environment(),
            address: &address,
            deck,
            egeon_home: &egeon_home,
            flavor,
            zsh_dir: &zsh_dir,
            home: &home,
        };
        let (env, notes) = node_environment(node, profile.as_ref(), &ctx);
        let directory = bench.directory(node, &home_text);
        for line in plan.notes.iter().chain(&notes).chain(&directory.warning) {
            crate::log!("{line}");
        }
        let hooked = plan.hooked;
        // CLI sem flag de system prompt: o papel entra como primeira
        // mensagem, pela fila do dispatch (TerminalNode.swift:326).
        let role = plan
            .prompt_to_inject
            .clone()
            .filter(|p| profile.is_some() && !p.is_empty());
        let launch = Launch {
            terminal,
            bench: bench.id.clone(),
            node: node.id.clone(),
            resolved: bench.resolved_directory(node, &home_text),
            address,
            cwd: PathBuf::from(&directory.path),
            command: plan.command,
            env,
            hooked,
            role,
        };
        // Claude herda a confiança do repositório antes de subir (ADR-071,
        // TerminalNode.swift:310); a pasta da config vem do ambiente final do
        // filho. Antes do corte só se grava dentro da pasta de dados
        // (decisão 36), a mesma regra do `install.rs`.
        match profile.filter(applies_to) {
            Some(profile) => {
                let config_dir = profile.config_env.as_ref().and_then(|name| {
                    launch
                        .env
                        .iter()
                        .find(|(k, _)| k == name)
                        .map(|(_, v)| v.clone())
                });
                let own = deck
                    .starts_with("egeon-next")
                    .then(|| paths.home().to_path_buf());
                let cwd = launch.cwd.clone();
                self.seed_trust_then(cwd, config_dir, own, move |actor| {
                    actor.launch(launch);
                });
            }
            None => self.launch(launch),
        }
    }

    fn launch(&mut self, launch: Launch) {
        if let Some(gone) = self.launch_gone(&launch) {
            crate::log!("terminal {}: não subo, {gone}", launch.address);
            return;
        }
        let Launch {
            terminal,
            address,
            cwd,
            command,
            env,
            hooked,
            role,
            ..
        } = launch;
        // A gravação da confiança corre fora do ator: outro pedido pode ter
        // subido este terminal nesse meio-tempo.
        if self
            .nodes
            .get(&terminal)
            .is_some_and(|n| n.session.is_some())
        {
            return;
        }
        match self.spawn_terminal(
            terminal.clone(),
            Some(address.clone()),
            &cwd,
            Some(command),
            env,
            super::DEFAULT_SIZE,
        ) {
            Ok(info) => {
                if let Some(n) = self.nodes.get_mut(&terminal) {
                    n.hooked = hooked;
                }
                crate::log!("terminal {address}: pid {}", info.pid);
                if let Some(role) = role {
                    self.dispatch_enqueue_role(&address, role);
                }
                // O agente sobe depois da confiança, já com a bancada na
                // tela: o "vivo" do nó e a contagem da árvore mudam agora.
                self.publish_org();
            }
            Err(err) => crate::log!("terminal {address}: não subiu — {err}"),
        }
    }

    /// O lançamento ainda vale? A confiança é gravada fora do ator, e nesse
    /// meio-tempo a bancada pode ter fechado, o nó sumido ou a pasta mudado
    /// (a bancada movida para outra worktree fecha e reabre): o lançamento
    /// velho não sobe um terminal fantasma nem toma o lugar do novo.
    fn launch_gone(&self, launch: &Launch) -> Option<&'static str> {
        let Some(bench) = self
            .org
            .state
            .workbenches
            .iter()
            .find(|w| w.id == launch.bench)
        else {
            return Some("a bancada foi removida");
        };
        if !self.org.live.contains(&bench.id) {
            return Some("a bancada foi fechada");
        }
        let Some(node) = bench.nodes.iter().find(|n| n.id == launch.node) else {
            return Some("o nó foi removido");
        };
        let home = self.config.default_cwd.to_string_lossy();
        if bench.resolved_directory(node, &home) != launch.resolved {
            return Some("a pasta mudou");
        }
        None
    }

    /// O perfil de agente do terminal `id` (`<wb>.<nó>`), para quem decide
    /// pelo modo de injeção ou pelos ganchos. Terminal solto ou de shell não
    /// tem.
    pub(super) fn node_profile(&self, id: &NodeId) -> Option<&AgentProfile> {
        let (bench, node) = id.as_str().split_once('.')?;
        let bench = self.org.state.workbenches.iter().find(|w| w.id == bench)?;
        let node = bench.nodes.iter().find(|n| n.id == node)?;
        self.org.profiles.get(node.agent.as_ref()?)
    }
}

/// O que sobe o terminal, guardado enquanto a confiança é gravada.
struct Launch {
    terminal: NodeId,
    bench: String,
    node: String,
    /// A pasta pedida, sem o disco: o que se compara na volta.
    resolved: String,
    address: String,
    cwd: PathBuf,
    command: String,
    env: Vec<(String, String)>,
    hooked: bool,
    role: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::super::processes_commands::support::Rig;
    use super::*;

    /// A volta da gravação da confiança não sobe terminal para nó removido,
    /// bancada fechada ou pasta que mudou; o lançamento que ainda vale sobe.
    #[tokio::test]
    async fn lancamento_que_volta_tarde_confere_se_ainda_vale() {
        let mut rig = Rig::new();
        let bench = WorkbenchConfig::new(
            "deck",
            "/tmp/deck",
            vec![NodeConfig::new(NodeKind::Agent, "dev")],
        );
        let id = bench.id.clone();
        let terminal = screen_id(&id, "dev").unwrap();
        let home = rig.actor.config.default_cwd.to_string_lossy().into_owned();
        let resolved = bench.resolved_directory(&bench.nodes[0], &home);
        let launch = || Launch {
            terminal: terminal.clone(),
            bench: id.clone(),
            node: "dev".into(),
            resolved: resolved.clone(),
            address: "deck/dev".into(),
            cwd: PathBuf::from("/tmp/deck"),
            command: "true".into(),
            env: Vec::new(),
            hooked: false,
            role: None,
        };
        rig.actor.org.state.workbenches.push(bench);

        // Fechada: não está entre as vivas.
        rig.actor.launch(launch());
        assert!(!rig.actor.nodes.contains_key(&terminal));

        rig.actor.org.live.insert(id.clone());
        rig.actor.org.state.workbenches[0].nodes[0].cwd = Some("outra".into());
        rig.actor.launch(launch());
        assert!(!rig.actor.nodes.contains_key(&terminal), "pasta mudou");

        rig.actor.org.state.workbenches[0].nodes.clear();
        rig.actor.launch(launch());
        assert!(!rig.actor.nodes.contains_key(&terminal), "nó removido");

        rig.actor.org.state.workbenches[0]
            .nodes
            .push(NodeConfig::new(NodeKind::Agent, "dev"));
        rig.actor.launch(launch());
        assert!(rig.actor.nodes.contains_key(&terminal), "ainda vale");
    }
}
