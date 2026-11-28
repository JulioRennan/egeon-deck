//! Dono: `org`. Os formulários de bancada (decisão 37): os templates de
//! bancada (listar e salvar o canvas como um) e as leituras do formulário de
//! worktree, com ou sem bancada de origem.
//!
//! Comandos do `/ui` que chegam aqui: templates, save_template, worktree_info e
//! worktree_plan.

use serde_json::json;

use super::node_commands::unknown_bench;
use super::{Actor, ClientId};
use crate::commons::ids::WorkbenchId;
use crate::features::path_text;
use crate::features::workbench::model::{ViewMode as ConfigView, WorkbenchConfig};
use crate::features::workbench::service::{capture_template, template_summary};
use crate::features::workbench::store as bench_store;
use crate::features::workspace::model::ProjectConfig;
use crate::features::workspace::routes::OrgEffect;
use crate::features::worktree::form;
use crate::protocol::message::Reply;
use crate::protocol::org::{
    SaveTemplate, TemplatePlan, TemplateView, ViewMode, WorktreeInfo, WorktreePlanRequest,
    WorktreeSource,
};

/// De onde o formulário de worktree parte, já resolvido contra a organização.
enum Origin {
    Bench(WorkbenchConfig),
    /// Sem bancada: a pasta expandida e como o usuário a escreveu.
    Folder {
        path: String,
        shown: String,
    },
    Multi(Result<WorktreeInfo, String>),
}

impl Actor {
    /// Os templates salvos, para o formulário de bancada nova.
    pub(super) fn templates(&self, re: u64) -> Reply {
        let file = self.config.paths.config(bench_store::TEMPLATES_FILE);
        let templates: Vec<TemplateView> = bench_store::load_templates(&file)
            .into_iter()
            .map(|(name, template)| TemplateView {
                name,
                nodes: u32::try_from(template.nodes.len()).unwrap_or(u32::MAX),
                base_path: template.base_path,
                view: template.view.map(|view| match view {
                    ConfigView::Canvas => ViewMode::Canvas,
                    ConfigView::Chat => ViewMode::Chat,
                }),
            })
            .collect();
        Reply::with(re, &json!({"templates": templates}))
    }

    /// "Salvar este canvas como um template novo" e "Atualizar o template de
    /// origem" (`saveCurrentAsTemplate`/`updateOriginTemplate`). Os nós da
    /// bancada já têm o layout da tela: o `move_node` grava cada frame.
    pub(super) fn save_template(&mut self, re: u64, s: SaveTemplate) -> Reply {
        let Some(index) = self.org.index_of(&s.workbench) else {
            return unknown_bench(re, &s.workbench);
        };
        let bench = &self.org.state.workbenches[index];
        let file = self.config.paths.config(bench_store::TEMPLATES_FILE);
        let name = match &s.name {
            Some(typed) => {
                let typed = typed.trim();
                if typed.is_empty() {
                    return Reply::err(re, "o template pede um nome");
                }
                Some(typed.to_owned())
            }
            None => bench.template.clone(),
        };
        let exists = name
            .as_deref()
            .is_some_and(|n| bench_store::template(&file, n).is_some());
        if s.dry_run {
            let plan = TemplatePlan {
                summary: template_summary(bench),
                nodes: u32::try_from(bench.nodes.len()).unwrap_or(u32::MAX),
                template: name,
                exists,
            };
            return Reply::with(re, &plan);
        }
        let Some(name) = name else {
            return Reply::err(re, "a bancada não nasceu de um template");
        };
        if bench.nodes.is_empty() {
            return Reply::err(re, "canvas vazio");
        }
        // Apagado desde que a bancada nasceu: virar um "salvar como" silencioso
        // seria pior do que dizer.
        if s.name.is_none() && !exists {
            return Reply::err(re, format!("o template \"{name}\" não existe mais"));
        }
        let captured = capture_template(bench);
        let count = captured.nodes.len();
        if let Err(error) = bench_store::put_template(&file, &name, captured) {
            return Reply::err(re, error.to_string());
        }
        if s.name.is_some() {
            crate::log!("template \"{name}\" salvo com {count} nós");
            // A bancada passa a ter origem: o botão de atualizar aparece agora.
            self.org.state.workbenches[index].template = Some(name.clone());
            self.apply_org(vec![OrgEffect::PersistWorkbenches]);
        } else {
            crate::log!(
                "template \"{name}\" atualizado a partir da bancada \"{}\"",
                self.org.state.workbenches[index].name
            );
        }
        Reply::with(re, &json!({"template": name}))
    }

    /// O resumo do formulário de worktree. O git roda fora do ator, sobre uma
    /// cópia da bancada.
    pub(super) fn worktree_info(
        &mut self,
        client: ClientId,
        re: u64,
        source: &WorktreeSource,
    ) -> Option<Reply> {
        let origin = match self.worktree_origin(source) {
            Ok(origin) => origin,
            Err(error) => return Some(Reply::err(re, error)),
        };
        let (git, home) = (self.user_git(), self.org.home.clone());
        let script = self
            .config
            .paths
            .config("worktree-copy.sh")
            .to_string_lossy()
            .into_owned();
        match origin {
            Origin::Multi(info) => {
                return Some(match info {
                    Ok(info) => Reply::with(re, &info),
                    Err(error) => Reply::err(re, error),
                });
            }
            Origin::Bench(bench) => {
                self.answer_form(client, re, move || form::info(&git, &bench, &home, &script));
            }
            Origin::Folder { path, shown } => {
                self.answer_form(client, re, move || {
                    form::info_at(&git, &path, &shown, &script)
                });
            }
        }
        None
    }

    /// O veredito do nome da branch, a cada tecla do formulário.
    pub(super) fn worktree_plan(
        &mut self,
        client: ClientId,
        re: u64,
        r: WorktreePlanRequest,
    ) -> Option<Reply> {
        let (path, shown) = match self.worktree_origin(&r.source) {
            Ok(Origin::Bench(bench)) => (bench.url_path(&self.org.home), bench.path),
            Ok(Origin::Folder { path, shown }) => (path, shown),
            // O formulário do multi-projeto não mostra veredito.
            Ok(Origin::Multi(_)) => {
                return Some(Reply::err(re, "multi-projeto não tem veredito de branch"));
            }
            Err(error) => return Some(Reply::err(re, error)),
        };
        let (git, home) = (self.user_git(), self.org.home.clone());
        self.answer_form(client, re, move || {
            form::plan_at(&git, &path, &shown, &r.branch, &home)
        });
        None
    }

    /// A bancada (multi-projeto vai ao formulário de um campo por repositório,
    /// como o `duplicateWorkbenchAsWorktree`), ou o projeto (multi idem), ou a
    /// pasta escolhida.
    fn worktree_origin(&self, source: &WorktreeSource) -> Result<Origin, String> {
        let home = &self.org.home;
        // Um terminal só: o repositório é o da pasta em que ele abre, que pode
        // ser vizinho ao da bancada.
        if let (Some(id), Some(node)) = (&source.workbench, &source.node) {
            let index = self
                .org
                .index_of(id)
                .ok_or_else(|| format!("bancada desconhecida '{id}'"))?;
            let path = self.org.node_directory(index, node.as_str())?;
            return Ok(Origin::Folder {
                shown: path_text::abbreviate_tilde(&path, home),
                path,
            });
        }
        if let Some(id) = &source.workbench {
            let bench = self
                .bench_by_id(id)
                .ok_or_else(|| format!("bancada desconhecida '{id}'"))?;
            if let Some(multi) = bench.project.as_deref().and_then(|p| self.multi_info(p)) {
                return Ok(Origin::Multi(multi));
            }
            return Ok(Origin::Bench(bench));
        }
        let project = match &source.project {
            Some(id) => Some(
                self.project(id.as_str())
                    .ok_or_else(|| format!("projeto desconhecido '{id}'"))?,
            ),
            None => None,
        };
        if let Some(multi) = source
            .project
            .as_ref()
            .and_then(|p| self.multi_info(p.as_str()))
        {
            return Ok(Origin::Multi(multi));
        }
        match (&source.path, project) {
            (Some(path), _) => Ok(Origin::Folder {
                path: path_text::normalize(path, home),
                shown: path.clone(),
            }),
            (None, Some(project)) => Ok(Origin::Folder {
                path: project.url_path(home),
                shown: project.path.clone(),
            }),
            (None, None) => Err("pede a pasta do repositório".to_owned()),
        }
    }

    fn project(&self, id: &str) -> Option<&ProjectConfig> {
        self.org
            .state
            .workspaces
            .iter()
            .find_map(|w| w.project_with_id(id))
    }

    /// O formulário de multi-projeto, quando o projeto é um.
    fn multi_info(&self, project: &str) -> Option<Result<WorktreeInfo, String>> {
        self.org.state.workspaces.iter().find_map(|space| {
            let project = space.project_with_id(project).filter(|p| p.is_multi())?;
            Some(form::multi_info(
                project,
                &space.members_of(project),
                &self.org.home,
            ))
        })
    }

    pub(super) fn bench_by_id(&self, id: &WorkbenchId) -> Option<WorkbenchConfig> {
        self.org
            .state
            .workbenches
            .iter()
            .find(|w| w.id == id.as_str())
            .cloned()
    }

    /// Roda a leitura do formulário fora do ator e responde com o resultado, ou
    /// com o erro dela.
    pub(super) fn answer_form<T: serde::Serialize + Send + 'static>(
        &self,
        client: ClientId,
        re: u64,
        read: impl FnOnce() -> Result<T, String> + Send + 'static,
    ) {
        self.blocking(
            read,
            Box::new(
                move |actor: &mut Actor, done: Result<Result<T, String>, String>| {
                    let reply = match done.and_then(|read| read) {
                        Ok(value) => Reply::with(re, &value),
                        Err(error) => Reply::err(re, error),
                    };
                    actor.send_reply(client, &reply);
                },
            ),
        );
    }
}
