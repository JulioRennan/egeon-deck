//! O bash de verdade com os rcfiles do Egeon (decisão 53), num `HOME`
//! temporário que imita o do Ubuntu: o `~/.profile` carrega o `~/.bashrc`, e o
//! `~/.bashrc` sai logo no começo fora do modo interativo — é depois dessa
//! saída que o nvm põe o `claude` no PATH. O `egeon` é um script que anota o
//! que recebeu.
#![cfg(unix)]

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use egeon_core::features::terminal::shell::{LaunchShell, Role, install_bash_hook};
use egeon_core::ports::pty::{PtyDriver, PtyEvent, PtySize, PtySpec};
use egeon_driver::SystemPty;

const LIMIT: Duration = Duration::from_secs(15);

struct Home {
    dir: tempfile::TempDir,
}

impl Home {
    fn new() -> Result<Self, String> {
        let dir = tempfile::tempdir().map_err(|e| e.to_string())?;
        let home = Home { dir };
        let root = home.path();
        write(&root.join(".profile"), UBUNTU_PROFILE, false)?;
        write(&root.join(".bashrc"), UBUNTU_BASHRC, false)?;
        write(
            &root.join(".nvm/bin/claude"),
            "#!/bin/sh\necho claude-do-nvm \"$@\"\n",
            true,
        )?;
        write(
            &root.join("egeon-bin/egeon"),
            &format!(
                "#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{}'\necho \"$PPID\" >> '{}'\n",
                root.join("trilha").display(),
                root.join("pais").display()
            ),
            true,
        )?;
        install_bash_hook(&root.join("dados/bash"))
            .into_iter()
            .next()
            .map_or(Ok(()), Err)?;
        Ok(home)
    }

    fn path(&self) -> &Path {
        self.dir.path()
    }

    fn trail(&self) -> String {
        fs::read_to_string(self.path().join("trilha")).unwrap_or_default()
    }

    /// O pai de cada `egeon` que rodou: o app só aceita o registro de quem
    /// descende do terminal.
    fn parents(&self) -> Vec<u32> {
        fs::read_to_string(self.path().join("pais"))
            .unwrap_or_default()
            .lines()
            .filter_map(|l| l.trim().parse().ok())
            .collect()
    }

    /// O ambiente que o core dá ao filho, em miniatura: o `egeon` na frente.
    fn env(&self) -> Vec<(String, String)> {
        vec![
            ("HOME".into(), self.path().display().to_string()),
            (
                "PATH".into(),
                format!("{}:/usr/bin:/bin", self.path().join("egeon-bin").display()),
            ),
            ("TERM".into(), "xterm-256color".into()),
        ]
    }
}

const UBUNTU_PROFILE: &str = r#"# o ~/.profile do Ubuntu, resumido
export PROFILE_VEZES=$((${PROFILE_VEZES:-0} + 1))
if [ -n "$BASH_VERSION" ]; then
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi
export DO_PROFILE=1
"#;

const UBUNTU_BASHRC: &str = r#"# o ~/.bashrc do Ubuntu, resumido
case $- in
    *i*) ;;
      *) return;;
esac
export BASHRC_VEZES=$((${BASHRC_VEZES:-0} + 1))
export PATH="$HOME/.nvm/bin:$PATH"
PS1='pronto$ '
"#;

fn write(path: &Path, body: &str, executable: bool) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    fs::write(path, body).map_err(|e| e.to_string())?;
    if executable {
        fs::set_permissions(path, fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())?;
    }
    Ok(())
}

fn bash() -> LaunchShell {
    LaunchShell::new(PathBuf::from("/bin/bash"))
}

struct Child {
    session: Box<dyn egeon_core::ports::pty::PtySession>,
    events: tokio::sync::mpsc::Receiver<PtyEvent>,
    output: String,
}

impl Child {
    fn spawn(home: &Home, command: Option<&str>, role: Role) -> Result<Child, String> {
        let launch = bash().launch(home.path(), command, role, &home.path().join("dados/bash"));
        let child = SystemPty
            .spawn(PtySpec {
                program: launch.program,
                args: launch.args,
                env: home.env(),
                cwd: None,
                size: PtySize {
                    cols: 200,
                    rows: 50,
                },
            })
            .map_err(|e| e.to_string())?;
        Ok(Child {
            session: child.session,
            events: child.events,
            output: String::new(),
        })
    }

    async fn until(&mut self, needle: &str) -> Result<(), String> {
        let deadline = Instant::now() + LIMIT;
        while !self.output.contains(needle) {
            let left = deadline.saturating_duration_since(Instant::now());
            match tokio::time::timeout(left, self.events.recv()).await {
                Ok(Some(PtyEvent::Output(bytes))) => {
                    self.output.push_str(&String::from_utf8_lossy(&bytes));
                }
                _ => return Err(format!("esperava {needle:?}; veio {:?}", self.output)),
            }
        }
        Ok(())
    }

    fn type_line(&self, line: &str) -> Result<(), String> {
        self.session
            .write(format!("{line}\r").as_bytes())
            .map_err(|e| e.to_string())
    }
}

async fn wait_trail(home: &Home, needle: &str) -> Result<String, String> {
    let deadline = Instant::now() + LIMIT;
    loop {
        let trail = home.trail();
        if trail.contains(needle) {
            return Ok(trail);
        }
        if Instant::now() > deadline {
            return Err(format!("esperava {needle:?} na trilha; veio {trail:?}"));
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}

#[tokio::test]
async fn agente_no_bash_ve_o_path_do_bashrc_inteiro() -> Result<(), String> {
    let home = Home::new()?;
    let mut agent = Child::spawn(
        &home,
        Some("echo \"login=$DO_PROFILE vezes=$BASHRC_VEZES\"; claude --model 'opus'"),
        Role::Agent,
    )?;
    agent.until("claude-do-nvm --model opus").await?;
    // O profile carregou o .bashrc uma vez só, e no modo interativo.
    assert!(agent.output.contains("login=1 vezes=1"), "{}", agent.output);
    // O agente não registra comando na trilha.
    assert_eq!(home.trail(), "");
    Ok(())
}

#[tokio::test]
async fn shell_no_bash_registra_cada_comando_e_so_o_comando() -> Result<(), String> {
    let home = Home::new()?;
    let mut shell = Child::spawn(&home, None, Role::Shell)?;
    shell.until("pronto$ ").await?;
    shell
        .type_line("echo \"vezes=$BASHRC_VEZES profile=$PROFILE_VEZES\"; echo saida-que-nao-vai")?;
    // O ~/.profile e o ~/.bashrc rodaram uma vez só.
    shell.until("vezes=1 profile=1").await?;
    let trail = wait_trail(&home, "echo saida-que-nao-vai").await?;
    assert_eq!(
        trail.lines().collect::<Vec<_>>(),
        vec!["trace $ echo \"vezes=$BASHRC_VEZES profile=$PROFILE_VEZES\"; echo saida-que-nao-vai"]
    );
    // O próprio `egeon trace` não entra, e o prompt não vira comando.
    shell.type_line("egeon trace manual")?;
    wait_trail(&home, "trace manual").await?;
    shell.type_line(" echo com-espaco-fora-do-historico")?;
    wait_trail(&home, "com-espaco-fora-do-historico").await?;
    let trail = home.trail();
    assert!(!trail.contains("$ egeon trace"), "{trail}");
    assert!(!trail.contains("__egeon"), "{trail}");
    assert_eq!(trail.lines().count(), 3, "{trail}");
    // Filho do próprio shell (que fez `exec` no pid da sessão), não órfão.
    let shell_pid = shell.session.pid();
    assert_eq!(home.parents(), vec![shell_pid; 3]);
    // Sem o aviso de job ("[1] 1234") na tela.
    assert!(!shell.output.contains("[1]"), "{}", shell.output);
    Ok(())
}

#[tokio::test]
async fn bash_aberto_a_mao_le_o_home_normal() -> Result<(), String> {
    let home = Home::new()?;
    let mut shell = Child::spawn(&home, None, Role::Shell)?;
    shell.until("pronto$ ").await?;
    // Um bash filho não herda o rcfile nem o registro: lê o ~/.bashrc normal.
    // As aspas vazias separam a saída do eco da linha digitada.
    shell.type_line(
        "bash -ic 'echo filho-vezes\"\"=$BASHRC_VEZES; type __egeon_debug >/dev/null 2>&1 || echo sem\"\"-gancho'",
    )?;
    shell.until("sem-gancho").await?;
    assert!(shell.output.contains("filho-vezes=2"), "{}", shell.output);
    Ok(())
}
