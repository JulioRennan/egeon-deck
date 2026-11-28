//! Multi-projeto: um projeto feito de outros projetos de pasta do mesmo
//! workspace, com uma pasta que os junta (ADR-065). Porte do `MultiProject` e
//! do `WorkspaceEdit`.

use std::collections::{BTreeMap, HashSet};

use super::model::{ProjectConfig, WorkspaceConfig};
use crate::features::path_text;
use crate::features::workbench::model::new_id;

/// Um multi-projeto como o formulário o vê: nome e as pastas escolhidas.
///
/// Por pasta, e não por id, porque a pasta pode ter acabado de entrar no
/// formulário e ainda não ser projeto nenhum. O id só é resolvido ao salvar.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MultiProjectDraft {
    /// `None` = nasce agora.
    pub id: Option<String>,
    pub name: String,
    pub folders: Vec<String>,
}

impl MultiProjectDraft {
    /// "nexus-web-app + nexus-backend" — o que a linha do formulário e o
    /// subtítulo da barra mostram.
    pub fn summary(&self, home: &str) -> String {
        default_name(&self.folders, home)
    }
}

/// O nome padrão de um multi-projeto sem nome: "nexus-web-app + nexus-backend",
/// as pastas escolhidas, na ordem. É o que o formulário mostra no campo vazio e
/// o que a barra mostra de subtítulo; a UI o pede ao core.
pub fn default_name(folders: &[String], home: &str) -> String {
    folders
        .iter()
        .map(|f| path_text::last_component(&path_text::normalize(f, home)))
        .collect::<Vec<_>>()
        .join(" + ")
}

/// Os rascunhos de um workspace salvo, para abrir o formulário.
pub fn drafts(space: &WorkspaceConfig) -> Vec<MultiProjectDraft> {
    space
        .projects
        .iter()
        .filter(|p| p.is_multi())
        .map(|project| MultiProjectDraft {
            id: Some(project.id.clone()),
            name: project.name.clone(),
            folders: space
                .members_of(project)
                .iter()
                .map(|m| m.path.clone())
                .collect(),
        })
        .collect()
}

/// Um link dentro da pasta do multi-projeto.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LinkName {
    pub name: String,
    pub target: String,
}

/// Nome de cada link dentro da pasta do multi-projeto: o da pasta do
/// repositório, que é como o agente e o `cwd` relativo o chamam. Dois repos com
/// a mesma pasta em lugares diferentes ganham sufixo em vez de um engolir o
/// outro.
pub fn link_names(members: &[&ProjectConfig], home: &str) -> Vec<LinkName> {
    let mut taken: HashSet<String> = HashSet::new();
    members
        .iter()
        .map(|member| {
            let target = member.url_path(home);
            let base = path_text::last_component(&target);
            let mut name = base.clone();
            let mut n = 2;
            while taken.contains(&name) {
                name = format!("{base}-{n}");
                n += 1;
            }
            taken.insert(name.clone());
            LinkName { name, target }
        })
        .collect()
}

/// Onde a bancada em worktree de um multi-projeto mora:
/// `<pai comum>/worktrees/<multi-projeto>/<branch>/`, com uma worktree por
/// repositório dentro, cada uma com o nome do link.
///
/// O nível do multi-projeto existe porque `worktrees/<repo>/` já é das
/// worktrees de um repo só (ADR-022): uma branch com nome de repositório cairia
/// dentro das dele.
pub fn worktree_root(
    project: &ProjectConfig,
    members: &[&ProjectConfig],
    branch: &str,
    home: &str,
) -> String {
    let paths: Vec<String> = members.iter().map(|m| m.url_path(home)).collect();
    let parent = common_parent(&paths, home);
    let root = path_text::join(&parent, "worktrees");
    path_text::join(
        &path_text::join(&root, &sanitize(&project.name)),
        &sanitize(branch),
    )
}

/// `feature/PROJ-1234` viraria subpasta; achatado, o caminho fica previsível.
/// É o `Worktree.sanitize`, que mora em `BranchName` quando o texto já é uma
/// branch; aqui o texto pode ser o nome do projeto.
fn sanitize(text: &str) -> String {
    text.replace('/', "-")
}

/// A branch de cada repositório: a da bancada, salvo a que você trocou.
///
/// A raiz e o nome da bancada são sempre da branch da bancada — é ela que dá
/// nome ao conjunto. O repo com branch própria muda só a worktree dele, e a
/// subpasta continua com o nome do repo, para o `cwd` relativo dos nós valer
/// igual.
pub fn branches(
    links: &[String],
    workbench: &str,
    overrides: &BTreeMap<String, String>,
) -> BTreeMap<String, String> {
    links
        .iter()
        .map(|link| {
            let custom = overrides.get(link).map_or("", |b| b.trim());
            let branch = if custom.is_empty() { workbench } else { custom };
            (link.clone(), branch.to_owned())
        })
        .collect()
}

/// Os componentes de um caminho, com `/` na frente quando é absoluto (o
/// `pathComponents` do Foundation).
fn components(path: &str) -> Vec<&str> {
    let mut out = Vec::new();
    if path.starts_with(path_text::is_separator) {
        out.push("/");
    }
    out.extend(
        path.split(path_text::is_separator)
            .filter(|c| !c.is_empty()),
    );
    out
}

/// `sep` é a barra em que os caminhos vieram escritos.
fn join_components(parts: &[&str], sep: char) -> String {
    let sep = sep.to_string();
    match parts {
        [] => String::new(),
        ["/"] => sep,
        ["/", rest @ ..] => format!("{sep}{}", rest.join(&sep)),
        all => all.join(&sep),
    }
}

/// O pai comum mais fundo. Sem nenhum além da raiz — repos em volumes
/// diferentes —, o do primeiro: mandar a worktree para `/` não serve a
/// ninguém, e o primeiro é o que você escolheu primeiro. Sem caminho nenhum,
/// o HOME.
pub fn common_parent(paths: &[String], home: &str) -> String {
    let parents: Vec<Vec<&str>> = paths
        .iter()
        .map(|p| {
            let mut parts = components(p);
            parts.pop();
            parts
        })
        .collect();
    let Some(first) = parents.first() else {
        return home.to_owned();
    };
    let sep = path_text::style(&paths[0]);
    let mut common: Vec<&str> = first.clone();
    for other in &parents[1..] {
        let shared = common.iter().zip(other).take_while(|(a, b)| a == b).count();
        common.truncate(shared);
    }
    if common.len() > 1 {
        return join_components(&common, sep);
    }
    join_components(&parents[0], sep)
}

/// O que salvar o formulário do workspace faz com a lista de projetos.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Outcome {
    pub projects: Vec<ProjectConfig>,
    /// Tirados no formulário, mas com bancada dentro: ficam.
    pub refused: Vec<String>,
}

/// Pura, para testar sem tela: quem é projeto de pasta, quem é multi-projeto e
/// o que fica porque tem bancada dentro. `link_path` diz onde mora a pasta de
/// links de um multi-projeto novo, e `has_workbenches` é a árvore.
pub fn apply_edit(
    existing: &[ProjectConfig],
    folders: &[String],
    multis: &[MultiProjectDraft],
    home: &str,
    link_path: impl Fn(&str) -> String,
    has_workbenches: impl Fn(&str) -> bool,
) -> Outcome {
    let mut kept: Vec<ProjectConfig> = Vec::new();
    let mut refused = Vec::new();

    // Pasta que já era projeto mantém o id — é ele que as bancadas guardam.
    // Pasta tirada com bancada dentro fica: senão a bancada viraria órfã sem
    // você ter pedido isso.
    let wanted_multis: HashSet<&str> = multis.iter().filter_map(|d| d.id.as_deref()).collect();
    for project in existing {
        let wanted = if project.is_multi() {
            wanted_multis.contains(project.id.as_str())
        } else {
            folders.iter().any(|f| project.owns(f, home))
        };
        if wanted {
            kept.push(project.clone());
        } else if has_workbenches(&project.id) {
            kept.push(project.clone());
            refused.push(project.name.clone());
        }
    }
    for folder in folders {
        if kept.iter().any(|p| !p.is_multi() && p.owns(folder, home)) {
            continue;
        }
        kept.push(ProjectConfig::for_folder(folder, home));
    }

    let member_ids = |kept: &[ProjectConfig], draft: &MultiProjectDraft| -> Vec<String> {
        draft
            .folders
            .iter()
            .filter_map(|folder| {
                kept.iter()
                    .find(|p| !p.is_multi() && p.owns(folder, home))
                    .map(|p| p.id.clone())
            })
            .collect()
    };
    for draft in multis {
        let name = draft.name.trim();
        let members = member_ids(&kept, draft);
        let existing_at = draft
            .id
            .as_deref()
            .and_then(|id| kept.iter().position(|p| p.id == id));
        match existing_at {
            Some(i) => {
                if !name.is_empty() {
                    kept[i].name = name.to_owned();
                }
                kept[i].members = Some(members);
            }
            None => {
                let id = new_id();
                let shown = if name.is_empty() {
                    draft.summary(home)
                } else {
                    name.to_owned()
                };
                let mut project = ProjectConfig::new(shown, link_path(&id));
                project.id = id;
                project.members = Some(members);
                kept.push(project);
            }
        }
    }
    Outcome {
        projects: kept,
        refused,
    }
}
