//! Qual cópia do app está rodando e onde ela guarda os arquivos (decisão 17).
//!
//! Até o corte, `~/.egeon-next` (estável) e `~/.egeon-next-dev` (dev);
//! `EGEON_HOME` sobrescreve, para teste. O `~/.egeon` é do Egeon estável em uso
//! e nunca é aberto daqui.

use std::path::{Path, PathBuf};

/// Qual cópia do app está rodando.
///
/// Existe para o app poder ser desenvolvido enquanto é usado: o estável segura
/// os agentes de verdade, e o dev é o que se derruba e reconstrói. Com uma
/// pasta só, o dev subiria os mesmos terminais do estável nas mesmas pastas, e
/// os dois brigariam para gravar o `workbenches.json`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Flavor {
    Stable,
    Dev,
}

impl Flavor {
    /// O core não tem bundle: quem diz é a UI, que lê o dela e acende
    /// `EGEON_FLAVOR=dev`. Sem a variável vale o estável, como no Swift sem
    /// bundle — é o menos surpreendente, e um teste solto não escreve na pasta
    /// do dev.
    pub fn from_env(value: Option<&str>) -> Self {
        if value == Some("dev") {
            Self::Dev
        } else {
            Self::Stable
        }
    }

    pub fn is_dev(self) -> bool {
        self == Self::Dev
    }

    pub fn display_name(self) -> &'static str {
        match self {
            Self::Stable => "Egeon Deck",
            Self::Dev => "Egeon Deck (dev)",
        }
    }

    /// Prefixo de rótulo em ferramenta de diagnóstico, e o `EGEON_DECK` que
    /// marca os processos.
    ///
    /// Até o corte não é o do Swift (`egeon`, `egeon-dev`): o Egeon em uso
    /// toma por órfão dele todo processo com o seu deck que não descenda
    /// dele, e o mataria depois de uma hora.
    pub fn identifier(self) -> &'static str {
        match self {
            Self::Stable => "egeon-next",
            Self::Dev => "egeon-next-dev",
        }
    }

    fn folder(self) -> &'static str {
        match self {
            Self::Stable => ".egeon-next",
            Self::Dev => ".egeon-next-dev",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum PathsError {
    #[error("sem HOME no ambiente e sem EGEON_HOME: não há onde gravar")]
    NoHome,
    #[error("EGEON_HOME aponta para {0}, que é do Egeon estável — use outra pasta")]
    StableHome(PathBuf),
}

/// A pasta de dados. Recebe o ambiente como parâmetro para o teste não
/// depender do processo.
pub fn egeon_home(
    flavor: Flavor,
    egeon_home: Option<&str>,
    home: Option<&str>,
) -> Result<PathBuf, PathsError> {
    let home = home.filter(|h| !h.is_empty()).map(PathBuf::from);
    let chosen = match egeon_home.filter(|h| !h.is_empty()) {
        Some(custom) => PathBuf::from(custom),
        None => home
            .as_ref()
            .ok_or(PathsError::NoHome)?
            .join(flavor.folder()),
    };
    if let Some(home) = &home {
        // As duas do Swift: o dev de lá também tem agentes em uso.
        for stable in [".egeon", ".egeon-dev"] {
            if inside(&chosen, &home.join(stable)) {
                return Err(PathsError::StableHome(chosen));
            }
        }
    }
    Ok(chosen)
}

/// `path` é `root` ou fica dentro dele. Pelo caminho canônico do ancestral
/// que existir, para um link não passar pela guarda; o resto, com `.` e `..`
/// resolvidos. A comparação é por componente: `~/.egeon-next` não está
/// dentro de `~/.egeon`.
fn inside(path: &Path, root: &Path) -> bool {
    canonical(path).starts_with(canonical(root))
}

fn canonical(path: &Path) -> PathBuf {
    let path = lexical(path);
    let mut existing = path.as_path();
    let mut rest = Vec::new();
    loop {
        if let Ok(real) = std::fs::canonicalize(existing) {
            return rest.iter().rev().fold(real, |acc, part| acc.join(part));
        }
        match (existing.parent(), existing.file_name()) {
            (Some(parent), Some(name)) => {
                rest.push(name.to_owned());
                existing = parent;
            }
            _ => return path,
        }
    }
}

fn lexical(path: &Path) -> PathBuf {
    use std::path::Component;
    let mut out = PathBuf::new();
    for part in path.components() {
        match part {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other),
        }
    }
    out
}

/// Tudo que o app guarda, dentro da pasta de dados: os mesmos nomes do
/// `Flavor` do Swift.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Paths {
    home: PathBuf,
}

impl Paths {
    pub fn new(home: PathBuf) -> Self {
        Self { home }
    }

    pub fn home(&self) -> &Path {
        &self.home
    }

    pub fn config(&self, name: &str) -> PathBuf {
        self.home.join(name)
    }

    /// O log do core (decisão 38): na pasta de dados, e por isso um por
    /// flavor, como o `Flavor.logPath` do Swift separava `~/egeon.log` e
    /// `~/egeon-dev.log`.
    pub fn log_file(&self) -> PathBuf {
        self.config(crate::commons::log::FILE)
    }

    /// O socket de controle.
    pub fn socket(&self) -> PathBuf {
        self.config("sock")
    }

    /// Onde mora o `egeon`, que vai na frente do `PATH` de todo filho.
    pub fn cli_dir(&self) -> PathBuf {
        self.config("bin")
    }

    /// O que é de uma bancada e não do app: memória dos agentes, histórico do
    /// chat. Bancada primeiro, assunto dentro — apagar, copiar ou olhar uma
    /// bancada é mexer numa pasta só.
    pub fn workbenches_dir(&self) -> PathBuf {
        self.config("workbenches")
    }

    pub fn workbench_dir(&self, name: &str) -> PathBuf {
        self.workbenches_dir().join(name)
    }

    /// O mesmo para workspace: hoje só a imagem dele mora aqui.
    pub fn workspaces_dir(&self) -> PathBuf {
        self.config("workspaces")
    }

    pub fn workspace_dir(&self, id: &str) -> PathBuf {
        self.workspaces_dir().join(id)
    }

    /// A pasta de links de um multi-projeto: é ela que a bancada no checkout
    /// principal abre.
    pub fn multi_project_dir(&self, id: &str) -> PathBuf {
        self.config("projects").join(id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const HOME: Option<&str> = Some("/Users/eu");

    /// `FlavorTests.testLogsAreSeparate`: o estável e o dev não escrevem no
    /// mesmo log.
    #[test]
    fn logs_do_estavel_e_do_dev_sao_separados() {
        let log = |flavor| Paths::new(egeon_home(flavor, None, HOME).unwrap()).log_file();
        assert_eq!(
            log(Flavor::Stable),
            PathBuf::from("/Users/eu/.egeon-next/egeon.log")
        );
        assert_eq!(
            log(Flavor::Dev),
            PathBuf::from("/Users/eu/.egeon-next-dev/egeon.log")
        );
    }

    #[test]
    fn padrao_e_egeon_next() {
        assert_eq!(
            egeon_home(Flavor::Stable, None, HOME).unwrap(),
            PathBuf::from("/Users/eu/.egeon-next")
        );
        assert_eq!(
            egeon_home(Flavor::Stable, Some(""), HOME).unwrap(),
            PathBuf::from("/Users/eu/.egeon-next")
        );
    }

    // FlavorTests.testConfigDirectoriesAreSeparate
    #[test]
    fn pastas_do_estavel_e_do_dev_sao_separadas() {
        let stable = egeon_home(Flavor::Stable, None, HOME).unwrap();
        let dev = egeon_home(Flavor::Dev, None, HOME).unwrap();
        assert!(stable.ends_with(".egeon-next"));
        assert!(dev.ends_with(".egeon-next-dev"));
        assert_ne!(stable, dev);
    }

    // FlavorTests.testCurrentWithoutBundleIsStable
    #[test]
    fn sem_a_variavel_e_estavel() {
        assert_eq!(Flavor::from_env(None), Flavor::Stable);
        assert_eq!(Flavor::from_env(Some("")), Flavor::Stable);
        assert_eq!(Flavor::from_env(Some("stable")), Flavor::Stable);
        assert_eq!(Flavor::from_env(Some("dev")), Flavor::Dev);
    }

    #[test]
    fn nome_como_no_swift_e_rotulo_proprio_ate_o_corte() {
        assert_eq!(Flavor::Stable.display_name(), "Egeon Deck");
        assert_eq!(Flavor::Dev.display_name(), "Egeon Deck (dev)");
        assert_eq!(Flavor::Stable.identifier(), "egeon-next");
        assert_eq!(Flavor::Dev.identifier(), "egeon-next-dev");
        assert!(Flavor::Dev.is_dev() && !Flavor::Stable.is_dev());
    }

    #[test]
    fn egeon_home_sobrescreve() {
        for flavor in [Flavor::Stable, Flavor::Dev] {
            assert_eq!(
                egeon_home(flavor, Some("/tmp/x"), HOME).unwrap(),
                PathBuf::from("/tmp/x")
            );
            assert_eq!(
                egeon_home(flavor, Some("/tmp/x"), None).unwrap(),
                PathBuf::from("/tmp/x")
            );
        }
    }

    #[test]
    fn vizinha_com_o_mesmo_comeco_passa() {
        for raw in [
            "/Users/eu/.egeon-next",
            "/Users/eu/.egeon-devx",
            "/Users/eu/.egeon2/x",
        ] {
            assert!(egeon_home(Flavor::Stable, Some(raw), HOME).is_ok(), "{raw}");
        }
    }

    /// Link para dentro da pasta do estável não passa pela guarda.
    #[cfg(unix)]
    #[test]
    fn link_para_dentro_do_estavel_e_recusado() {
        let base = std::env::temp_dir().join(format!("egeon-paths-{}", std::process::id()));
        let stable = base.join(".egeon");
        std::fs::create_dir_all(&stable).unwrap();
        let link = base.join("atalho");
        let _ = std::fs::remove_file(&link);
        std::os::unix::fs::symlink(&stable, &link).unwrap();
        let home = base.to_string_lossy().into_owned();
        let chosen = link.join("novo").to_string_lossy().into_owned();
        let refused = egeon_home(Flavor::Stable, Some(&chosen), Some(&home));
        let _ = std::fs::remove_dir_all(&base);
        assert!(
            matches!(refused, Err(PathsError::StableHome(_))),
            "{refused:?}"
        );
    }

    #[test]
    fn sem_home_e_erro() {
        assert_eq!(
            egeon_home(Flavor::Stable, None, None).unwrap_err(),
            PathsError::NoHome
        );
    }

    #[test]
    fn nunca_as_pastas_do_swift() {
        for raw in [
            "/Users/eu/.egeon",
            "/Users/eu/./.egeon",
            "/Users/eu/x/../.egeon",
            "/Users/eu/.egeon-dev",
            "/Users/eu/x/../.egeon-dev",
            "/Users/eu/.egeon/x",
            "/Users/eu/.egeon-dev/teste/sub",
        ] {
            assert!(
                matches!(
                    egeon_home(Flavor::Stable, Some(raw), HOME),
                    Err(PathsError::StableHome(_))
                ),
                "{raw}"
            );
        }
    }

    // FlavorTests.testConfigBuildsInsideOwnDirectory
    #[test]
    fn caminhos_dentro_da_pasta() {
        let paths = Paths::new(PathBuf::from("/tmp/x"));
        let at = |rel: &str| PathBuf::from("/tmp/x").join(rel);
        assert_eq!(paths.home(), Path::new("/tmp/x"));
        assert_eq!(paths.config("workbenches.json"), at("workbenches.json"));
        assert_eq!(paths.socket(), at("sock"));
        assert_eq!(paths.cli_dir(), at("bin"));
        assert_eq!(paths.workbenches_dir(), at("workbenches"));
        assert_eq!(paths.workbench_dir("1a2b3c4d"), at("workbenches/1a2b3c4d"));
        assert_eq!(paths.workspaces_dir(), at("workspaces"));
        assert_eq!(paths.workspace_dir("geral"), at("workspaces/geral"));
        assert_eq!(paths.multi_project_dir("9f8e"), at("projects/9f8e"));
    }
}
