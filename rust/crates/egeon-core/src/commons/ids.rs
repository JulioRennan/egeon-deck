//! Os nomes e ids que têm regra: endereço de dispatch, ids de nó, bancada,
//! workspace e projeto, nome de bancada e de branch.
//!
//! As regras são as do Swift, nem mais estritas nem mais frouxas: o que ele
//! gravou em `~/.egeon` tem de abrir aqui.

use std::fmt;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum IdError {
    #[error("id de nó inválido: {0:?} (letras, dígitos, '-', '_' e '.', até 64)")]
    Node(String),
    #[error("id inválido: {0:?} (vira nome de pasta: sem '/', e não '.' nem '..')")]
    Folder(String),
    #[error("nome de bancada vazio")]
    EmptyWorkbenchName,
    #[error("nome de branch vazio")]
    EmptyBranch,
    #[error("endereço inválido: {0:?} (use bancada/nó)")]
    Address(String),
}

macro_rules! string_newtype {
    ($name:ident) => {
        impl $name {
            pub fn as_str(&self) -> &str {
                &self.0
            }
        }

        impl TryFrom<String> for $name {
            type Error = IdError;
            fn try_from(raw: String) -> Result<Self, Self::Error> {
                Self::new(raw)
            }
        }

        impl From<$name> for String {
            fn from(id: $name) -> Self {
                id.0
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str(&self.0)
            }
        }

        impl AsRef<str> for $name {
            fn as_ref(&self) -> &str {
                &self.0
            }
        }
    };
}

/// Id de um nó dentro da bancada. Vai em caminho de URL, em nome de tópico e
/// no endereço de dispatch, então só leva o que não precisa de escape.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct NodeId(String);
string_newtype!(NodeId);

impl NodeId {
    pub fn new(raw: impl Into<String>) -> Result<Self, IdError> {
        let raw = raw.into();
        let valid = !raw.is_empty()
            && raw.len() <= 64
            && raw
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.'));
        if valid {
            Ok(Self(raw))
        } else {
            Err(IdError::Node(raw))
        }
    }

    /// O id do terminal de um nó, que a UI assina em `screen/<id>`: único entre
    /// as bancadas. Nulo quando a junção não é um id válido (longo demais).
    pub fn screen(workbench: &str, node: &str) -> Option<Self> {
        Self::new(format!("{workbench}.{node}")).ok()
    }

    /// `front end` → `front-end`, como `NodeTemplateStore.identifier`: o nome
    /// de um componente vira o id do nó.
    ///
    /// Cada escalar fora de `[a-z0-9-_]` vira traço, então um acento também.
    /// O corte no 64 é daqui: o Swift não tem teto, e um id maior não passaria
    /// em [`NodeId::new`].
    pub fn slug(name: &str) -> Self {
        let lowered = name.trim().to_lowercase();
        let mapped: String = lowered
            .chars()
            .map(|c| {
                if c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_' {
                    c
                } else {
                    '-'
                }
            })
            .collect();
        let collapsed = mapped
            .split('-')
            .filter(|part| !part.is_empty())
            .collect::<Vec<_>>()
            .join("-");
        let mut id = if collapsed.is_empty() {
            "sh".to_owned()
        } else {
            collapsed
        };
        id.truncate(64);
        Self(id.trim_end_matches('-').to_owned())
    }
}

/// Oito hex de um UUID, como `WorkbenchConfig.newID`: único o bastante para
/// uma máquina, curto o bastante para nome de pasta.
fn short_id() -> String {
    let mut id = uuid::Uuid::new_v4().simple().to_string();
    id.truncate(8);
    id
}

/// Id que vira nome de pasta. O Swift sempre gerou oito hex, mas o arquivo é
/// editável à mão; só se recusa o que sairia da pasta de dados.
fn folder_id(raw: String) -> Result<String, IdError> {
    let bad = raw.is_empty() || raw == "." || raw == ".." || raw.contains(['/', '\0']);
    if bad {
        Err(IdError::Folder(raw))
    } else {
        Ok(raw)
    }
}

macro_rules! folder_newtype {
    ($(#[$doc:meta])* $name:ident) => {
        $(#[$doc])*
        #[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
        #[serde(try_from = "String", into = "String")]
        pub struct $name(String);
        string_newtype!($name);

        impl $name {
            pub fn new(raw: impl Into<String>) -> Result<Self, IdError> {
                folder_id(raw.into()).map(Self)
            }

            pub fn generate() -> Self {
                Self(short_id())
            }
        }
    };
}

folder_newtype!(
    /// Identidade da bancada que o nome não dá: apagar uma e criar outra com
    /// o mesmo nome é outra bancada.
    WorkbenchId
);
folder_newtype!(WorkspaceId);
folder_newtype!(ProjectId);

/// Nome da bancada: a primeira parte do endereço de dispatch, renomeável.
///
/// O Swift não barra a barra no nome, e uma bancada `a/b` fica sem alcance
/// pelo endereço. É defeito de lá, portado como está.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct WorkbenchName(String);
string_newtype!(WorkbenchName);

impl WorkbenchName {
    /// Aparado nas pontas, como o renomear do Swift.
    pub fn new(raw: impl Into<String>) -> Result<Self, IdError> {
        let raw = raw.into();
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            Err(IdError::EmptyWorkbenchName)
        } else {
            Ok(Self(trimmed.to_owned()))
        }
    }

    /// Nome livre derivado de `suggestion`: `deck`, `deck-2`, `deck-3`… O nome
    /// é a primeira parte do endereço, então precisa ser único.
    pub fn available(suggestion: &str, taken: &[&str]) -> Self {
        let base = if suggestion.is_empty() {
            "bancada"
        } else {
            suggestion
        };
        if !taken.contains(&base) {
            return Self(base.to_owned());
        }
        let mut n = 2;
        while taken.contains(&format!("{base}-{n}").as_str()) {
            n += 1;
        }
        Self(format!("{base}-{n}"))
    }
}

/// Endereço de dispatch: `bancada/nó`. Não depende de título de janela nem de
/// posição na tela.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Address {
    pub workbench: String,
    pub node: String,
}

impl Address {
    pub fn new(workbench: &WorkbenchName, node: &NodeId) -> Self {
        Self {
            workbench: workbench.0.clone(),
            node: node.0.clone(),
        }
    }

    /// Como o `split(separator: "/", maxSplits: 1)` do Swift: barra no começo
    /// some (`/a/b` é `a/b`), e o resto da linha depois da primeira barra é o
    /// nó, barras inclusive.
    ///
    /// As partes não são validadas: um nome que não existe dá "bancada
    /// desconhecida" em quem procura, como lá.
    pub fn parse(raw: &str) -> Result<Self, IdError> {
        match raw.trim_start_matches('/').split_once('/') {
            Some((workbench, node)) if !node.is_empty() => Ok(Self {
                workbench: workbench.to_owned(),
                node: node.to_owned(),
            }),
            _ => Err(IdError::Address(raw.to_owned())),
        }
    }
}

impl fmt::Display for Address {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}/{}", self.workbench, self.node)
    }
}

/// Nome de branch como o usuário escreveu. O Swift só recusa o vazio; o
/// resto quem julga é o git.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct BranchName(String);
string_newtype!(BranchName);

impl BranchName {
    pub fn new(raw: impl Into<String>) -> Result<Self, IdError> {
        let raw = raw.into();
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            Err(IdError::EmptyBranch)
        } else {
            Ok(Self(trimmed.to_owned()))
        }
    }

    /// `feature/PROJ-1234` viraria subpasta; achatado, o caminho fica
    /// previsível e fácil de apagar.
    pub fn sanitized(&self) -> String {
        self.0.replace('/', "-")
    }

    /// `<pai do repo>/worktrees/<repo>/<branch achatada>`, como
    /// `Worktree.suggestedPath`: fora da pasta do app, porque worktree é
    /// artefato do git.
    pub fn suggested_worktree_path(&self, repo_root: &Path) -> PathBuf {
        let parent = repo_root.parent().unwrap_or(Path::new("/"));
        let repo = repo_root.file_name().unwrap_or_default();
        parent.join("worktrees").join(repo).join(self.sanitized())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn node_id_aceita_o_de_sempre() {
        for ok in ["t1", "claude-1.dev_2", "a", &"x".repeat(64)] {
            assert!(NodeId::new(ok).is_ok(), "{ok:?}");
        }
        for bad in ["", "a/b", "a b", "ç", "a?b", &"x".repeat(65)] {
            assert_eq!(
                NodeId::new(bad),
                Err(IdError::Node(bad.to_owned())),
                "{bad:?}"
            );
        }
    }

    #[test]
    fn node_id_pelo_json_valida() {
        let ok: NodeId = serde_json::from_str("\"t1\"").unwrap();
        assert_eq!(ok.as_str(), "t1");
        assert!(serde_json::from_str::<NodeId>("\"a/b\"").is_err());
        assert_eq!(serde_json::to_string(&ok).unwrap(), "\"t1\"");
    }

    // NodeTemplateStore.identifier(from:)
    #[test]
    fn slug_como_no_swift() {
        assert_eq!(NodeId::slug("front end").as_str(), "front-end");
        assert_eq!(NodeId::slug("front / end").as_str(), "front-end");
        assert_eq!(NodeId::slug("  Revisor_2  ").as_str(), "revisor_2");
        assert_eq!(NodeId::slug("Ação").as_str(), "a-o");
        assert_eq!(NodeId::slug("--a--").as_str(), "a");
        assert_eq!(NodeId::slug("").as_str(), "sh");
        assert_eq!(NodeId::slug("///").as_str(), "sh");
        assert_eq!(NodeId::slug(&"a".repeat(80)).as_str().len(), 64);
        // O slug é sempre um id válido: o maestro compara um com o outro.
        for name in ["front end", "Ação", "", "x.y"] {
            assert!(NodeId::new(NodeId::slug(name).as_str()).is_ok());
        }
    }

    #[test]
    fn ids_gerados_sao_oito_hex_e_diferentes() {
        let a = WorkbenchId::generate();
        let b = WorkbenchId::generate();
        assert_eq!(a.as_str().len(), 8);
        assert!(
            a.as_str()
                .bytes()
                .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase())
        );
        assert_ne!(a, b);
        assert_eq!(WorkspaceId::generate().as_str().len(), 8);
        assert_eq!(ProjectId::generate().as_str().len(), 8);
    }

    #[test]
    fn id_de_pasta_recusa_o_que_sai_da_pasta() {
        for ok in ["1a2b3c4d", "feito-a-mao", "Geral"] {
            assert!(WorkbenchId::new(ok).is_ok(), "{ok:?}");
        }
        for bad in ["", ".", "..", "a/b", "../x", "a\0b"] {
            assert_eq!(
                WorkspaceId::new(bad),
                Err(IdError::Folder(bad.to_owned())),
                "{bad:?}"
            );
        }
        assert!(serde_json::from_str::<ProjectId>("\"..\"").is_err());
    }

    #[test]
    fn nome_de_bancada_aparado_e_nao_vazio() {
        assert_eq!(WorkbenchName::new("  deck ").unwrap().as_str(), "deck");
        assert_eq!(WorkbenchName::new("   "), Err(IdError::EmptyWorkbenchName));
        assert_eq!(WorkbenchName::new(""), Err(IdError::EmptyWorkbenchName));
        // Defeito do Swift portado: a barra passa.
        assert!(WorkbenchName::new("a/b").is_ok());
    }

    // WorkbenchStore.availableName
    #[test]
    fn nome_livre_como_no_swift() {
        assert_eq!(WorkbenchName::available("deck", &[]).as_str(), "deck");
        assert_eq!(
            WorkbenchName::available("deck", &["deck"]).as_str(),
            "deck-2"
        );
        assert_eq!(
            WorkbenchName::available("deck", &["deck", "deck-2", "deck-3"]).as_str(),
            "deck-4"
        );
        assert_eq!(
            WorkbenchName::available("deck", &["deck-2"]).as_str(),
            "deck"
        );
        assert_eq!(WorkbenchName::available("", &[]).as_str(), "bancada");
        assert_eq!(
            WorkbenchName::available("", &["bancada"]).as_str(),
            "bancada-2"
        );
    }

    #[test]
    fn endereco_parte_como_o_split_do_swift() {
        let parse = |raw: &str| {
            Address::parse(raw)
                .map(|a| (a.workbench, a.node))
                .map_err(|_| ())
        };
        let pair = |w: &str, n: &str| Ok((w.to_owned(), n.to_owned()));
        assert_eq!(parse("deck/claude"), pair("deck", "claude"));
        assert_eq!(parse("/deck/claude"), pair("deck", "claude"));
        assert_eq!(parse("//deck/claude"), pair("deck", "claude"));
        assert_eq!(parse("a/b/c"), pair("a", "b/c"));
        assert_eq!(parse("a//b"), pair("a", "/b"));
        assert_eq!(parse("a///b"), pair("a", "//b"));
        assert_eq!(parse("a/b/"), pair("a", "b/"));
        assert_eq!(parse("deck//"), pair("deck", "/"));
        for bad in ["", "deck", "/deck", "deck/", "/", "//"] {
            assert_eq!(parse(bad), Err(()), "{bad:?}");
        }
    }

    #[test]
    fn endereco_volta_ao_texto() {
        let address = Address::new(
            &WorkbenchName::new("deck").unwrap(),
            &NodeId::new("claude").unwrap(),
        );
        assert_eq!(address.to_string(), "deck/claude");
        assert_eq!(Address::parse("deck/claude").unwrap(), address);
    }

    #[test]
    fn branch_nao_vazia_e_achatada() {
        assert_eq!(BranchName::new("  "), Err(IdError::EmptyBranch));
        let branch = BranchName::new(" feature/PROJ-1234 ").unwrap();
        assert_eq!(branch.as_str(), "feature/PROJ-1234");
        assert_eq!(branch.sanitized(), "feature-PROJ-1234");
    }

    // Worktree.suggestedPath
    #[test]
    fn worktree_sugerida_fora_do_repo() {
        let branch = BranchName::new("feature/x").unwrap();
        assert_eq!(
            branch.suggested_worktree_path(Path::new("/Users/eu/code/deck")),
            PathBuf::from("/Users/eu/code/worktrees/deck/feature-x")
        );
    }
}
