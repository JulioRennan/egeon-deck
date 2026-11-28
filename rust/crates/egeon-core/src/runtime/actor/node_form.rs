//! Dono: `org`. O formulário de terminal (`NodeTemplateDialog`) e o que o
//! `main.swift` faz com ele: abrir, trocar de CLI, escolher pasta, criar e
//! aplicar a um nó (`configureNewTerminal`, `place`, `editNode`).
//!
//! Comandos do `/ui` que chegam aqui: node_form, node_form_screen, node_folder,
//! apply_node e components; o `create_node` com `form` passa por
//! [`Actor::form_component`]. As regras são de `features::node::form`.

use std::collections::BTreeMap;
use std::path::Path;

use serde_json::json;

use super::Actor;
use super::node_commands::{config_kind, unknown_bench, unknown_node};
use crate::commons::ids::NodeId;
use crate::features::node::form::{self, FormFields as Fields, ScreenRequest, Shown};
use crate::features::node::model::{NodeKind as ConfigKind, NodeTemplate, Overrides};
use crate::features::node::{edit, service as node_service, store as components};
use crate::features::workbench::folders;
use crate::features::workbench::model::WorkbenchConfig;
use crate::features::workspace::routes::OrgEffect;
use crate::protocol::message::Reply;
use crate::protocol::org::{
    ApplyNode, CliChoice, CliOverrides, ComponentView, ConfigOption, FolderOption, FormFields,
    ModelOption, NodeFolder, NodeForm, NodeFormScreen, NodeFormSubmit, NodeFormView, NodeKind,
    NodeScreenView, ScreenFields, ShownFields, TemplateDraft,
};
use crate::runtime::org::screen_id;

/// O componente do fio, na forma da feature.
pub(super) fn template_in(draft: TemplateDraft) -> NodeTemplate {
    let kind = config_kind(draft.kind);
    let mut template = NodeTemplate::new(draft.name, kind);
    template.agent = draft.agent;
    template.maestro = draft.maestro;
    template.cwd = draft.cwd;
    template.prompt = draft.prompt;
    template.rules = draft.rules;
    template.command = draft.cmd.filter(|_| kind == ConfigKind::Shell);
    template.by_agent = draft.by_agent.map(|map| {
        map.into_iter()
            .map(|(cli, o)| {
                let over = Overrides {
                    cmd: o.cmd,
                    config: o.config,
                    model: o.model,
                    effort: o.effort,
                    prompt: o.prompt,
                    rules: o.rules,
                };
                (cli, over)
            })
            .collect()
    });
    template
}

fn wire_kind(kind: ConfigKind) -> NodeKind {
    match kind {
        ConfigKind::Shell => NodeKind::Shell,
        ConfigKind::Agent => NodeKind::Agent,
        ConfigKind::Web => NodeKind::Web,
        ConfigKind::Queue => NodeKind::Queue,
    }
}

pub(super) fn template_out(template: &NodeTemplate) -> TemplateDraft {
    TemplateDraft {
        name: template.name.clone(),
        kind: wire_kind(template.kind),
        agent: template.agent.clone(),
        maestro: template.maestro,
        cwd: template.cwd.clone(),
        prompt: template.prompt.clone(),
        rules: template.rules.clone(),
        by_agent: template.by_agent.as_ref().map(|map| {
            map.iter()
                .map(|(cli, o)| {
                    let over = CliOverrides {
                        cmd: o.cmd.clone(),
                        config: o.config.clone(),
                        model: o.model.clone(),
                        effort: o.effort.clone(),
                        prompt: o.prompt.clone(),
                        rules: o.rules.clone(),
                    };
                    (cli.clone(), over)
                })
                .collect()
        }),
        cmd: template.command.clone(),
    }
}

fn shown_in(shown: ShownFields) -> Shown {
    Shown {
        cli: shown.cli,
        model: shown.model,
        effort: shown.effort,
        config: shown.config,
        prompt: shown.prompt,
        rules: shown.rules,
    }
}

fn fields_in(fields: FormFields) -> Fields {
    Fields {
        name: fields.name,
        kind: config_kind(fields.kind),
        agent: fields.agent,
        cwd: fields.cwd,
        cmd: fields.cmd,
        maestro: fields.maestro,
    }
}

impl Actor {
    /// O workspace da bancada, quando ela é de um projeto.
    fn workspace_of(&self, bench: &WorkbenchConfig) -> Option<usize> {
        let project = bench.project.as_deref()?;
        self.org
            .state
            .workspaces
            .iter()
            .position(|w| w.projects.iter().any(|p| p.id == project))
    }

    /// A configuração que cada CLI sugere num terminal novo: a última
    /// escolhida no workspace. Vazio ao editar — ali vale a do nó.
    fn suggested_configs(
        &self,
        bench: &WorkbenchConfig,
        creating: bool,
    ) -> BTreeMap<String, String> {
        if !creating {
            return BTreeMap::new();
        }
        self.workspace_of(bench)
            .and_then(|w| self.org.state.workspaces[w].last_configs.clone())
            .unwrap_or_default()
    }

    fn screen_view(
        &self,
        bench: &WorkbenchConfig,
        creating: bool,
        template: &NodeTemplate,
        shown: Option<&Shown>,
        cli: Option<&str>,
        picked_config: Option<&str>,
    ) -> NodeScreenView {
        let suggested = self.suggested_configs(bench, creating);
        let screen = form::screen(
            ScreenRequest {
                template,
                shown,
                cli,
                picked_config,
                suggested_configs: &suggested,
            },
            &self.org.profiles,
            &|profile| self.model_catalog(profile),
            &self.org.home,
        );
        NodeScreenView {
            template: template_out(&screen.template),
            fields: ScreenFields {
                model: screen.fields.model,
                effort: screen.fields.effort,
                config: screen.fields.config,
                prompt: screen.fields.prompt,
                rules: screen.fields.rules,
            },
            models: screen
                .models
                .into_iter()
                .map(|m| ModelOption {
                    label: m.label,
                    id: m.id,
                })
                .collect(),
            efforts: screen.efforts,
            config_env: screen.config_env,
            config_items: screen
                .config_items
                .into_iter()
                .map(|i| ConfigOption {
                    title: i.title,
                    value: i.value,
                })
                .collect(),
        }
    }

    fn component_views(&self) -> Vec<ComponentView> {
        let file = self.config.paths.config(components::FILE);
        components::load(&file)
            .into_values()
            .map(|component| ComponentView {
                name: component.name.clone(),
                kind: wire_kind(component.kind),
                subtitle: form::subtitle(&component, &self.org.profiles),
                prompt: component.prompt.clone(),
                template: template_out(&component),
            })
            .collect()
    }

    /// Abre o formulário: de terminal novo (agente, Claude Code) ou do nó.
    pub(super) fn node_form(&self, re: u64, f: NodeForm) -> Reply {
        let Some(index) = self.org.index_of(&f.workbench) else {
            return unknown_bench(re, &f.workbench);
        };
        let bench = &self.org.state.workbenches[index];
        let template = match &f.node {
            Some(id) => {
                let Some(node) = bench.nodes.iter().find(|n| n.id == id.as_str()) else {
                    return unknown_node(re, id.as_str());
                };
                node_service::capture(node, node.component.as_deref().unwrap_or(&node.id))
            }
            None => {
                let mut template = NodeTemplate::new("", ConfigKind::Agent);
                template.agent = Some("claude".to_owned());
                template
            }
        };
        let keys: Vec<&String> = self.org.profiles.keys().collect();
        let cli = template
            .agent
            .as_ref()
            .filter(|a| keys.contains(a))
            .or_else(|| keys.first().copied())
            .cloned();

        let root = bench.url_path(&self.org.home);
        let suggestions = folders::list(&folders::repo_children(Path::new(&root)));
        let current = template.cwd.clone().unwrap_or_default();
        let folders = folders::folder_options(&current, &suggestions)
            .into_iter()
            .map(|value| FolderOption {
                shown: folders::shown(Some(&value)).to_owned(),
                value,
            })
            .collect();

        let screen = self.screen_view(
            bench,
            f.node.is_none(),
            &template,
            None,
            cli.as_deref(),
            None,
        );
        let view = NodeFormView {
            template: template_out(&template),
            cli,
            clis: self
                .org
                .profiles
                .iter()
                .map(|(key, p)| CliChoice {
                    key: key.clone(),
                    name: p.display_name.clone(),
                })
                .collect(),
            folders,
            components: self.component_views(),
            screen,
        };
        Reply::with(re, &view)
    }

    /// A tela para um CLI: ao trocar de CLI e depois do + da configuração.
    pub(super) fn node_form_screen(&self, re: u64, s: NodeFormScreen) -> Reply {
        let Some(index) = self.org.index_of(&s.workbench) else {
            return unknown_bench(re, &s.workbench);
        };
        let bench = &self.org.state.workbenches[index];
        let shown = s.shown.map(shown_in);
        let view = self.screen_view(
            bench,
            s.node.is_none(),
            &template_in(s.template),
            shown.as_ref(),
            s.cli.as_deref(),
            s.config.as_deref(),
        );
        Reply::with(re, &view)
    }

    /// O + da pasta: relativo dentro da bancada, `~` fora (ADR-017).
    pub(super) fn node_folder(&self, re: u64, f: NodeFolder) -> Reply {
        let Some(index) = self.org.index_of(&f.workbench) else {
            return unknown_bench(re, &f.workbench);
        };
        let root = self.org.state.workbenches[index].url_path(&self.org.home);
        let cwd = form::stored_folder(&f.path, Some(&root), &self.org.home);
        let shown = folders::shown(Some(&cwd)).to_owned();
        Reply::with(re, &json!({"cwd": cwd, "shown": shown}))
    }

    pub(super) fn components(&self, re: u64) -> Reply {
        Reply::with(re, &json!({"components": self.component_views()}))
    }

    /// O componente que sai do formulário confirmado: lembra a configuração no
    /// workspace e, se pedido, salva como componente. `current` é o nó em
    /// edição: ali só se lembra a configuração quando ela ou o CLI mudou.
    pub(super) fn form_component(
        &mut self,
        index: usize,
        submit: NodeFormSubmit,
        current: Option<&crate::features::node::NodeConfig>,
    ) -> NodeTemplate {
        let shown = submit.shown.map(shown_in);
        let component = form::finish(
            &template_in(submit.template),
            &fields_in(submit.fields),
            shown.as_ref(),
        );
        self.remember_config(index, &component, current);
        if submit.save_component {
            let file = self.config.paths.config(components::FILE);
            if let Err(error) = components::put(&file, component.clone()) {
                crate::log!("componente \"{}\" não foi salvo: {error}", component.name);
            }
        }
        component
    }

    fn remember_config(
        &mut self,
        index: usize,
        component: &NodeTemplate,
        current: Option<&crate::features::node::NodeConfig>,
    ) {
        let Some((agent, config)) = form::config_to_remember(component) else {
            return;
        };
        // Ao editar, mexer no nome de um terminal no padrão não é escolher o
        // padrão para o workspace.
        if let Some(current) = current
            && current.config == config
            && current.agent.as_deref() == Some(agent.as_str())
        {
            return;
        }
        let Some(w) = self.workspace_of(&self.org.state.workbenches[index]) else {
            return;
        };
        let workspace = &mut self.org.state.workspaces[w];
        if workspace.last_configs.as_ref().and_then(|m| m.get(&agent)) == config.as_ref() {
            return;
        }
        workspace.remember(config.as_deref(), &agent);
        self.apply_org(vec![OrgEffect::SaveWorkspaces]);
    }

    /// Aplica o formulário a um nó já na tela.
    ///
    /// Nome, comando, agente e pasta definem como o processo foi lançado:
    /// mudá-los troca o processo. O nó novo guarda o que o formulário não
    /// mostra (conversa, ultracode, URL) e fica no mesmo lugar do canvas.
    pub(super) fn apply_node(&mut self, re: u64, a: ApplyNode) -> Reply {
        let Some(index) = self.org.index_of(&a.workbench) else {
            return unknown_bench(re, &a.workbench);
        };
        let Some(position) = self.org.state.workbenches[index]
            .nodes
            .iter()
            .position(|n| n.id == a.node.as_str())
        else {
            return unknown_node(re, a.node.as_str());
        };
        let current = self.org.state.workbenches[index].nodes[position].clone();
        let component = self.form_component(index, a.form, Some(&current));

        let renamed = NodeId::slug(&component.name);
        let new_id = if renamed.as_str() == current.id {
            current.id.clone()
        } else {
            edit::next_id(renamed.as_str(), &self.org.state.workbenches[index])
        };
        let mut updated = node_service::instantiate(&component, &new_id).keeping_state(&current);
        if let Some(frame) = current.frame() {
            updated.set_frame(frame);
        }
        let same = form::same_process(&updated, &current) && new_id == current.id;
        self.org.state.workbenches[index].nodes[position] = updated.clone();

        if !same {
            // O processo antigo é encerrado pelo id dele: renomeado, o novo
            // sobe com outro.
            let bench_id = self.org.state.workbenches[index].id.clone();
            if let Some(terminal) = screen_id(&bench_id, &current.id) {
                let _ = self.close(&terminal);
            }
            self.restart_node(index, position, updated);
        }
        self.apply_org(vec![OrgEffect::PersistWorkbenches]);
        Reply::with(re, &json!({"node": new_id}))
    }
}
