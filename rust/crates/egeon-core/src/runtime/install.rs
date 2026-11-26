//! O que o app escreve em disco ao subir para os terminais funcionarem: o
//! binário `egeon` em `<pasta de dados>/bin` (o PATH dos nós já aponta para
//! lá), o `claude-hooks.json` com o caminho dele e as skills `egeon` e
//! `egeon-maestro` para o Claude Code. Porte de `EgeonCLI.install`,
//! `ClaudeHooks.install` e `ClaudeSkill.install`.
//!
//! Só escreve o que mudou: o Swift reescrevia tudo a cada arranque, e aqui o
//! binário tem alguns MB. O gancho do zsh é do `node::launch`, que o core já
//! instala na carga.
//!
//! Skills (decisão 36): até o corte o Egeon estável grava as mesmas skills em
//! `~/.claude*`, e os dois brigariam. Então, enquanto o identificador do app é
//! o novo (`egeon-next*`), elas só vão para uma pasta de configuração que o
//! app criou DENTRO da própria pasta de dados — nunca para fora dela, nem para
//! o `CLAUDE_CONFIG_DIR` herdado do shell (que num agente é a configuração real
//! do usuário). Depois do corte vale o comportamento do Swift.
//!
//! Bloqueia (lê e grava arquivos): o core chama de fora do ator, na carga.

use std::fs;
use std::path::{Path, PathBuf};

use crate::commons::paths::Paths;
use crate::features::agent::claude::{hooks, skill, write_atomic};
use crate::features::agent::model::{AgentProfile, expand_tilde};
use crate::features::agent::store::Profiles;
use crate::features::maestro::guide;
use crate::ports::links::FileLinks;

/// A pasta de configuração do Claude Code que o app novo cria dentro da pasta
/// de dados, onde as skills ficam até o corte.
pub const OWN_CONFIG: &str = "claude-config";

/// O que a instalação precisa saber, tudo emprestado da partida.
pub struct Installation<'a> {
    /// A pasta de dados: `bin/` e `claude-hooks.json` moram nela.
    pub paths: &'a Paths,
    /// O `egeon` que acompanha o app (`Config::cli_binary`); `None` se o
    /// executável não tem um ao lado (um `cargo run` sem o `egeon-cli` feito).
    pub bundled_egeon: Option<PathBuf>,
    /// O `agents.json`: o perfil `claude` diz onde ficam as configurações.
    pub profiles: &'a Profiles,
    /// O HOME do usuário, para o `~` dos padrões de configuração.
    pub user_home: &'a Path,
    /// O ambiente do app (`CLAUDE_CONFIG_DIR`).
    pub environment: &'a dyn Fn(&str) -> Option<String>,
    /// O bit de execução do binário copiado.
    pub links: &'a dyn FileLinks,
    /// O `Flavor::identifier()`: `egeon-next*` até o corte, `egeon*` depois.
    pub flavor: &'a str,
}

impl Installation<'_> {
    /// Antes do corte: o app novo não grava nas configurações do usuário.
    fn before_cutover(&self) -> bool {
        self.flavor.starts_with("egeon-next")
    }
}

/// Instala o que mudou e devolve os problemas, em texto para o log.
pub fn install(plan: &Installation<'_>) -> Vec<String> {
    let mut problems = Vec::new();
    let egeon = plan.paths.cli_binary();
    install_cli(plan, &egeon, &mut problems);
    install_hooks(plan, &egeon, &mut problems);
    install_skills(plan, &mut problems);
    problems
}

/// Copia o binário para `bin/egeon` se ele ainda não é igual.
fn install_cli(plan: &Installation<'_>, target: &Path, problems: &mut Vec<String>) {
    let Some(source) = &plan.bundled_egeon else {
        problems.push(
            "egeon: o binário não está ao lado do app; o comando dos terminais fica como estava"
                .to_owned(),
        );
        return;
    };
    let bytes = match fs::read(source) {
        Ok(bytes) => bytes,
        Err(error) => {
            problems.push(format!(
                "egeon: não consegui ler {} — {error}",
                source.display()
            ));
            return;
        }
    };
    if fs::read(target).is_ok_and(|current| current == bytes) {
        return;
    }
    let written = target
        .parent()
        .map_or(Ok(()), fs::create_dir_all)
        .and_then(|()| write_atomic(target, &bytes))
        .and_then(|()| plan.links.make_executable(target));
    match written {
        Ok(()) => crate::log!("egeon: instalado em {}", target.display()),
        Err(error) => problems.push(format!(
            "egeon: não consegui instalar {} — {error}",
            target.display()
        )),
    }
}

/// Grava o `claude-hooks.json` apontando para o `egeon` instalado.
fn install_hooks(plan: &Installation<'_>, egeon: &Path, problems: &mut Vec<String>) {
    let directory = plan.paths.home();
    let current = fs::read_to_string(hooks::settings_file(directory)).ok();
    if current.as_deref() == Some(hooks::settings_body(egeon).as_str()) {
        return;
    }
    match hooks::install(directory, egeon) {
        Ok(()) => crate::log!("ganchos: claude-hooks.json atualizado"),
        Err(error) => problems.push(format!("ganchos: não consegui escrever — {error}")),
    }
}

/// Onde as skills vão. Antes do corte: só a pasta própria do app e, se o
/// ambiente nomear uma, o `CLAUDE_CONFIG_DIR` que fica DENTRO da pasta de
/// dados — o resto é pulado com uma nota. Depois do corte: o `~/.claude*` e o
/// `CLAUDE_CONFIG_DIR`, como o Swift.
fn config_directories(
    plan: &Installation<'_>,
    profile: &AgentProfile,
    problems: &mut Vec<String>,
) -> Vec<PathBuf> {
    if !plan.before_cutover() {
        return skill::config_directories(profile, plan.user_home, plan.environment);
    }
    let mut out = vec![plan.paths.config(OWN_CONFIG)];
    let named = profile
        .config_env
        .as_deref()
        .and_then(plan.environment)
        .filter(|named| !named.is_empty());
    if let Some(named) = named {
        let directory = expand_tilde(&named, plan.user_home);
        if under(&directory, plan.paths.home()) {
            if !out.contains(&directory) {
                out.push(directory);
            }
        } else {
            problems.push(format!(
                "skill: {} fica fora da pasta de dados do app; pulei (decisão 36)",
                directory.display()
            ));
        }
    }
    out
}

/// `path` está dentro de `home`, com os links resolvidos: um link para dentro
/// de `home` não passa por fora, e um para fora não passa por dentro. Caminho
/// que ainda não existe resolve o maior ancestral que existe (`/tmp` é
/// `/private/tmp` no macOS) e mantém o resto.
fn under(path: &Path, home: &Path) -> bool {
    resolve(path).starts_with(resolve(home))
}

fn resolve(path: &Path) -> PathBuf {
    let mut rest = Vec::new();
    let mut current = path;
    loop {
        if let Ok(real) = crate::commons::paths::canonicalize(current) {
            return rest.iter().rev().fold(real, |acc, part| acc.join(part));
        }
        match (current.parent(), current.file_name()) {
            (Some(parent), Some(name)) => {
                rest.push(name.to_owned());
                current = parent;
            }
            _ => return path.to_owned(),
        }
    }
}

/// Publica as duas skills em cada configuração do Claude Code que vale.
fn install_skills(plan: &Installation<'_>, problems: &mut Vec<String>) {
    // A primeira tentativa entregava a skill por `--add-dir`, de uma pasta
    // nossa: deixá-la é ter duas cópias que um dia divergem.
    let _ = fs::remove_dir_all(plan.paths.config("claude"));
    let Some(profile) = plan.profiles.get("claude") else {
        return;
    };
    let maestro = skill::PublishedSkill {
        name: guide::SKILL_NAME.to_owned(),
        body: guide::skill(),
    };
    let published = skill::published(&maestro);
    for config in config_directories(plan, profile, problems) {
        for one in &published {
            let file = skill::skill_file(&config, &one.name);
            if fs::read_to_string(&file).is_ok_and(|current| current == one.body) {
                continue;
            }
            let written = skill::install(
                std::slice::from_ref(&config),
                std::slice::from_ref(one),
                None,
            );
            if written.is_empty() {
                problems.push(format!("skill: não consegui escrever {}", file.display()));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use std::io;
    use std::sync::Mutex;
    use std::time::{Duration, SystemTime};

    use super::*;
    use crate::features::agent::claude::profile::claude_code;

    const NEXT: &str = "egeon-next";
    const AFTER_CUTOVER: &str = "egeon";
    /// Os dois identificadores do app depois do corte: o Swift.
    const SWIFT_FLAVORS: [&str; 2] = ["egeon", "egeon-dev"];

    #[derive(Default)]
    struct Links {
        executable: Mutex<Vec<PathBuf>>,
    }

    impl FileLinks for Links {
        fn symlink(&self, _target: &Path, _link: &Path) -> io::Result<()> {
            Ok(())
        }
        fn make_executable(&self, path: &Path) -> io::Result<()> {
            self.executable.lock().unwrap().push(path.to_owned());
            Ok(())
        }
    }

    /// Uma pasta de dados e um HOME de mentira, ambos temporários: nada aqui
    /// toca `~/.egeon` nem `~/.claude*` de verdade.
    struct World {
        dir: tempfile::TempDir,
        paths: Paths,
        home: PathBuf,
        source: PathBuf,
        profiles: Profiles,
        links: Links,
    }

    impl World {
        fn new() -> World {
            let dir = tempfile::tempdir().unwrap();
            let data = dir.path().join("data");
            let home = dir.path().join("home");
            fs::create_dir_all(&home).unwrap();
            let source = dir.path().join("bundle-egeon");
            fs::write(&source, b"binario v1").unwrap();
            World {
                paths: Paths::new(data),
                profiles: Profiles::from([("claude".to_owned(), claude_code())]),
                home,
                source,
                dir,
                links: Links::default(),
            }
        }

        fn run_as(
            &self,
            source: Option<PathBuf>,
            env: &dyn Fn(&str) -> Option<String>,
            flavor: &str,
        ) -> Vec<String> {
            install(&Installation {
                paths: &self.paths,
                bundled_egeon: source,
                profiles: &self.profiles,
                user_home: &self.home,
                environment: env,
                links: &self.links,
                flavor,
            })
        }

        /// O app novo, sem `CLAUDE_CONFIG_DIR` no ambiente.
        fn run(&self) -> Vec<String> {
            self.run_as(Some(self.source.clone()), &|_| None, NEXT)
        }

        fn egeon(&self) -> PathBuf {
            self.paths.cli_binary()
        }

        /// A pasta de configuração que o app novo cria.
        fn own(&self) -> PathBuf {
            self.paths.config(OWN_CONFIG)
        }

        fn skill(config: &Path, name: &str) -> PathBuf {
            config.join("skills").join(name).join("SKILL.md")
        }
    }

    fn old(path: &Path) -> SystemTime {
        let when = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000_000);
        let file = fs::OpenOptions::new().write(true).open(path).unwrap();
        file.set_modified(when).unwrap();
        when
    }

    fn mtime(path: &Path) -> SystemTime {
        fs::metadata(path).unwrap().modified().unwrap()
    }

    fn env_of(named: &Path) -> impl Fn(&str) -> Option<String> {
        let named = named.to_string_lossy().into_owned();
        move |key: &str| (key == "CLAUDE_CONFIG_DIR").then(|| named.clone())
    }

    #[test]
    fn a_primeira_vez_copia_o_binario_grava_os_ganchos_e_publica_as_skills_so_na_pasta_do_app() {
        let w = World::new();
        // O usuário tem configurações do Claude Code; o app novo não as toca.
        fs::create_dir_all(w.home.join(".claude")).unwrap();
        fs::create_dir_all(w.home.join(".claude-agro")).unwrap();
        assert_eq!(w.run(), Vec::<String>::new());

        assert_eq!(fs::read(w.egeon()).unwrap(), b"binario v1");
        assert_eq!(*w.links.executable.lock().unwrap(), [w.egeon()]);

        // Os ganchos chamam o binário instalado, como o `hooks` o escreve em
        // cada sistema (com aspas no unix; no Windows, sem elas).
        let hooks = fs::read_to_string(w.paths.home().join("claude-hooks.json")).unwrap();
        let value: serde_json::Value = serde_json::from_str(&hooks).unwrap();
        let command = crate::features::agent::claude::hooks::command(&w.egeon(), "stop");
        assert_eq!(
            value["hooks"]["Stop"][0]["hooks"][0]["command"],
            command.as_str()
        );
        assert_eq!(
            value["hooks"]["PermissionRequest"][0]["hooks"][0]["timeout"],
            600
        );

        // As duas skills, na pasta que o app criou, e só nela (decisão 36).
        assert_eq!(
            fs::read_to_string(World::skill(&w.own(), "egeon")).unwrap(),
            skill::body()
        );
        assert_eq!(
            fs::read_to_string(World::skill(&w.own(), "egeon-maestro")).unwrap(),
            guide::skill()
        );
        assert!(!w.home.join(".claude/skills").exists());
        assert!(!w.home.join(".claude-agro/skills").exists());
    }

    #[test]
    fn so_reescreve_o_que_mudou() {
        let w = World::new();
        assert!(w.run().is_empty());
        let files = [
            w.egeon(),
            w.paths.home().join("claude-hooks.json"),
            World::skill(&w.own(), "egeon"),
            World::skill(&w.own(), "egeon-maestro"),
        ];
        let stamps: Vec<SystemTime> = files.iter().map(|f| old(f)).collect();
        w.links.executable.lock().unwrap().clear();

        assert!(w.run().is_empty());
        let after: Vec<SystemTime> = files.iter().map(|f| mtime(f)).collect();
        assert_eq!(after, stamps, "nada mudou, nada foi regravado");
        assert!(w.links.executable.lock().unwrap().is_empty());
    }

    #[test]
    fn binario_novo_ou_skill_editada_a_mao_voltam_ao_que_o_app_traz() {
        let w = World::new();
        w.run();

        fs::write(&w.source, b"binario v2").unwrap();
        fs::write(World::skill(&w.own(), "egeon"), "editada à mão").unwrap();
        assert!(w.run().is_empty());
        assert_eq!(fs::read(w.egeon()).unwrap(), b"binario v2");
        assert_eq!(
            fs::read_to_string(World::skill(&w.own(), "egeon")).unwrap(),
            skill::body()
        );
        // Ganchos estragados voltam ao texto certo.
        let good = fs::read_to_string(w.paths.home().join("claude-hooks.json")).unwrap();
        fs::write(w.paths.home().join("claude-hooks.json"), "{}").unwrap();
        assert!(w.run().is_empty());
        assert_eq!(
            fs::read_to_string(w.paths.home().join("claude-hooks.json")).unwrap(),
            good
        );
    }

    // O shell de um agente tem `CLAUDE_CONFIG_DIR` apontando para a configuração
    // REAL do usuário. O app novo não escreve nela: nem sob o HOME, nem em
    // qualquer pasta fora da sua pasta de dados.
    #[cfg(unix)]
    #[test]
    fn config_dir_herdado_do_shell_nao_recebe_skill() {
        let w = World::new();
        let under_home = w.home.join(".claude-agro");
        let outside_everything = w.dir.path().join("fora-de-tudo");
        fs::create_dir_all(&under_home).unwrap();
        fs::create_dir_all(&outside_everything).unwrap();
        let link = w.dir.path().join("atalho");
        std::os::unix::fs::symlink(&under_home, &link).unwrap();

        for named in [under_home.clone(), outside_everything.clone(), link.clone()] {
            let problems = w.run_as(Some(w.source.clone()), &env_of(&named), NEXT);
            assert_eq!(problems.len(), 1, "{}: {problems:?}", named.display());
            assert!(
                problems[0].contains("fora da pasta de dados"),
                "{problems:?}"
            );
        }
        assert!(!under_home.join("skills").exists());
        assert!(!outside_everything.join("skills").exists());
        // E "~/.claude-agro" escrito com til também não.
        let problems = w.run_as(
            Some(w.source.clone()),
            &|key| (key == "CLAUDE_CONFIG_DIR").then(|| "~/.claude-agro".to_owned()),
            NEXT,
        );
        assert_eq!(problems.len(), 1);
        assert!(!under_home.join("skills").exists());
        // A pasta do próprio app recebeu normalmente.
        assert!(World::skill(&w.own(), "egeon").is_file());
    }

    // Um `CLAUDE_CONFIG_DIR` que ainda não existe, dentro da pasta de dados que
    // é alcançada por um link, ainda é "dentro".
    #[cfg(unix)]
    #[test]
    fn config_dir_ainda_nao_criado_atras_de_um_link_conta_como_dentro() {
        let w = World::new();
        let real = w.dir.path().join("real");
        fs::create_dir_all(&real).unwrap();
        let door = w.dir.path().join("porta");
        std::os::unix::fs::symlink(&real, &door).unwrap();
        let paths = Paths::new(door.join("dados"));
        fs::create_dir_all(paths.home()).unwrap();
        let future = real.join("dados/novo/config");
        assert!(under(&future, paths.home()));
        assert!(!under(&real.join("outro/config"), paths.home()));
    }

    #[test]
    fn config_dir_que_fica_dentro_da_pasta_de_dados_do_app_tambem_recebe() {
        let w = World::new();
        let inside = w.paths.home().join("config-do-agente");
        fs::create_dir_all(&inside).unwrap();
        let problems = w.run_as(Some(w.source.clone()), &env_of(&inside), NEXT);
        assert!(problems.is_empty(), "{problems:?}");
        assert!(World::skill(&inside, "egeon").is_file());
        assert!(World::skill(&inside, "egeon-maestro").is_file());
        assert!(World::skill(&w.own(), "egeon").is_file());
    }

    // Os dois flavors de cada lado: depois do corte ("egeon", "egeon-dev") vale
    // o Swift; antes dele ("egeon-next", "egeon-next-dev") o app não toca nas
    // configurações do usuário.
    #[test]
    fn depois_do_corte_vale_o_comportamento_do_swift() {
        for flavor in SWIFT_FLAVORS {
            let w = World::new();
            fs::create_dir_all(w.home.join(".claude")).unwrap();
            fs::create_dir_all(w.home.join(".claude-agro")).unwrap();
            let outside = w.dir.path().join("fora-do-padrao");
            fs::create_dir_all(&outside).unwrap();
            let problems = w.run_as(Some(w.source.clone()), &env_of(&outside), flavor);
            assert!(problems.is_empty(), "{flavor}: {problems:?}");
            for config in [w.home.join(".claude"), w.home.join(".claude-agro"), outside] {
                assert!(
                    World::skill(&config, "egeon").is_file(),
                    "{flavor} {}",
                    config.display()
                );
                assert!(World::skill(&config, "egeon-maestro").is_file());
            }
            assert!(
                !World::skill(&w.own(), "egeon").exists(),
                "{flavor}: a pasta do app novo não é usada"
            );
        }
        for flavor in ["egeon-next", "egeon-next-dev"] {
            let w = World::new();
            fs::create_dir_all(w.home.join(".claude")).unwrap();
            let outside = w.dir.path().join("fora-do-padrao");
            fs::create_dir_all(&outside).unwrap();
            let problems = w.run_as(Some(w.source.clone()), &env_of(&outside), flavor);
            assert_eq!(problems.len(), 1, "{flavor}: {problems:?}");
            assert!(!w.home.join(".claude/skills").exists(), "{flavor}");
            assert!(!outside.join("skills").exists(), "{flavor}");
            assert!(World::skill(&w.own(), "egeon").is_file(), "{flavor}");
        }
    }

    // O ramo do Swift (decisão 36, depois do corte): as skills vão a todo
    // `~/.claude*` descoberto e ao `CLAUDE_CONFIG_DIR`. O HOME é temporário.
    fn swift_world() -> (World, Vec<PathBuf>) {
        let w = World::new();
        let configs = vec![w.home.join(".claude"), w.home.join(".claude-agro")];
        for config in &configs {
            fs::create_dir_all(config).unwrap();
        }
        (w, configs)
    }

    #[test]
    fn ramo_swift_a_primeira_vez_copia_o_binario_grava_os_ganchos_e_publica_nas_configs() {
        for flavor in SWIFT_FLAVORS {
            let (w, configs) = swift_world();
            let problems = w.run_as(Some(w.source.clone()), &|_| None, flavor);
            assert!(problems.is_empty(), "{flavor}: {problems:?}");
            assert_eq!(fs::read(w.egeon()).unwrap(), b"binario v1");
            assert_eq!(*w.links.executable.lock().unwrap(), [w.egeon()]);
            assert!(w.paths.home().join("claude-hooks.json").is_file());
            for config in &configs {
                assert_eq!(
                    fs::read_to_string(World::skill(config, "egeon")).unwrap(),
                    skill::body(),
                    "{flavor} {}",
                    config.display()
                );
                assert_eq!(
                    fs::read_to_string(World::skill(config, "egeon-maestro")).unwrap(),
                    guide::skill()
                );
            }
            assert!(!World::skill(&w.own(), "egeon").exists(), "{flavor}");
        }
    }

    #[test]
    fn ramo_swift_so_reescreve_o_que_mudou() {
        let (w, configs) = swift_world();
        let run = |w: &World| w.run_as(Some(w.source.clone()), &|_| None, AFTER_CUTOVER);
        assert!(run(&w).is_empty());
        let mut files = vec![w.egeon(), w.paths.home().join("claude-hooks.json")];
        for config in &configs {
            files.push(World::skill(config, "egeon"));
            files.push(World::skill(config, "egeon-maestro"));
        }
        let stamps: Vec<SystemTime> = files.iter().map(|f| old(f)).collect();
        w.links.executable.lock().unwrap().clear();

        assert!(run(&w).is_empty());
        let after: Vec<SystemTime> = files.iter().map(|f| mtime(f)).collect();
        assert_eq!(after, stamps, "nada mudou, nada foi regravado");
        assert!(w.links.executable.lock().unwrap().is_empty());
    }

    #[test]
    fn ramo_swift_binario_novo_ou_skill_editada_a_mao_voltam_ao_que_o_app_traz() {
        let (w, configs) = swift_world();
        let run = |w: &World| w.run_as(Some(w.source.clone()), &|_| None, AFTER_CUTOVER);
        run(&w);
        fs::write(&w.source, b"binario v2").unwrap();
        fs::write(World::skill(&configs[1], "egeon"), "editada à mão").unwrap();
        assert!(run(&w).is_empty());
        assert_eq!(fs::read(w.egeon()).unwrap(), b"binario v2");
        assert_eq!(
            fs::read_to_string(World::skill(&configs[1], "egeon")).unwrap(),
            skill::body()
        );
    }

    #[test]
    fn ramo_swift_sem_binario_ao_lado_do_app_avisa_mas_grava_o_resto() {
        let (w, configs) = swift_world();
        let problems = w.run_as(None, &|_| None, AFTER_CUTOVER);
        assert_eq!(problems.len(), 1);
        assert!(problems[0].starts_with("egeon: o binário não está ao lado do app"));
        assert!(!w.egeon().exists());
        assert!(w.paths.home().join("claude-hooks.json").is_file());
        for config in &configs {
            assert!(World::skill(config, "egeon").is_file());
        }
    }

    #[test]
    fn sem_binario_ao_lado_do_app_avisa_mas_grava_o_resto() {
        let w = World::new();
        let problems = w.run_as(None, &|_| None, NEXT);
        assert_eq!(problems.len(), 1);
        assert!(problems[0].starts_with("egeon: o binário não está ao lado do app"));
        assert!(!w.egeon().exists());
        assert!(w.paths.home().join("claude-hooks.json").is_file());
        assert!(World::skill(&w.own(), "egeon").is_file());
        // Binário que sumiu depois de apontado: avisa, não derruba.
        let problems = w.run_as(Some(w.dir.path().join("sumiu")), &|_| None, NEXT);
        assert!(problems[0].starts_with("egeon: não consegui ler"));
    }

    #[test]
    fn sem_perfil_claude_nao_ha_skill_e_pasta_antiga_da_skill_some() {
        let mut w = World::new();
        w.profiles.clear();
        let legacy = w.paths.config("claude");
        fs::create_dir_all(legacy.join("skills/egeon")).unwrap();
        assert!(w.run().is_empty());
        assert!(!World::skill(&w.own(), "egeon").exists());
        assert!(!legacy.exists(), "a pasta da primeira tentativa não fica");
    }

    #[test]
    fn pasta_que_nao_da_para_escrever_vira_aviso_e_nao_derruba() {
        let w = World::new();
        // `bin` é um arquivo: não dá para criar `bin/egeon` dentro dele.
        fs::create_dir_all(w.paths.home()).unwrap();
        fs::write(w.paths.cli_dir(), "arquivo no lugar da pasta").unwrap();
        let problems = w.run();
        assert_eq!(problems.len(), 1);
        assert!(
            problems[0].starts_with("egeon: não consegui instalar"),
            "{problems:?}"
        );
        assert!(w.paths.home().join("claude-hooks.json").is_file());
    }
}
