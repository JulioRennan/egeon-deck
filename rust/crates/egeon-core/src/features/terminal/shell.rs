//! Em qual shell cada terminal sobe (decisão 53).
//!
//! No macOS é sempre o `/bin/zsh`, como no Swift. No Linux é o shell do
//! usuário, que o driver resolve (`PtyDriver::user_shell`): impor o zsh
//! deixava de fora o `~/.bashrc` e o `~/.profile` (PATH, nvm, o `claude` do
//! npm). Aqui só se decide, pelo nome do programa, como cada um é chamado e de
//! onde vem o registro de comandos na trilha:
//!
//! - zsh: a integração de hoje, por `ZDOTDIR` (ADR-036);
//! - bash: a mesma ideia por `--rcfile` ([`bash_hook_files`]);
//! - outro POSIX (`sh`, `dash`, `ksh`): abre nele, sem registro;
//! - fish: abre nele, sem registro; a linha que o Egeon monta (aspas, `||`) é
//!   de shell POSIX e roda num `sh` lançado pelo fish de login, que já montou
//!   o PATH do usuário;
//! - outro fora do POSIX (`nu`, `xonsh`…): abre nele, sem registro, e a linha
//!   roda pelo `/bin/sh`;
//! - PowerShell (o do Windows, decisão 54): abre nele, sem registro, com a
//!   linha no jeito dele — `Set-Location`, aspas do PowerShell e sem `exec`
//!   ([`ShellSyntax`]).

use std::path::{Path, PathBuf};

use super::model::{LAUNCH_SHELL, shell_quote};

/// As opções de todo PowerShell lançado: sem a faixa de abertura, e o
/// `Bypass` só para este processo — sem ele o 5.1 recusa os `.ps1`, e o
/// `claude` instalado pelo npm é um `claude.ps1`.
const POWERSHELL_OPTIONS: [&str; 3] = ["-NoLogo", "-ExecutionPolicy", "Bypass"];

/// Como o shell é chamado.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShellKind {
    Zsh,
    Bash,
    /// Entende a linha do Egeon e `-l`, mas não tem gancho de registro.
    Posix,
    /// Não entende a linha do Egeon, mas a repassa a um `sh` depois do login.
    Fish,
    /// Não entende a linha do Egeon: ela vai pelo `/bin/sh`.
    Other,
    /// O PowerShell: a linha é montada na sintaxe dele.
    PowerShell,
}

/// A sintaxe da linha que o shell roda: o que muda é a aspa de um argumento e
/// o "senão" de um comando que falhou.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShellSyntax {
    Posix,
    PowerShell,
}

impl ShellSyntax {
    /// Um argumento de programa, literal: nada dentro dele é expandido.
    pub fn quote(self, text: &str) -> String {
        match self {
            Self::Posix => shell_quote(text),
            Self::PowerShell => powershell_argument(text),
        }
    }

    /// `first`, e `then` se `first` sair com erro.
    pub fn or_else(self, first: &str, then: &str) -> String {
        match self {
            Self::Posix => format!("{first} || {then}"),
            // O PowerShell 5.1 não tem `||`; o `$LASTEXITCODE` é o código do
            // último programa.
            Self::PowerShell => format!("{first}; if ($LASTEXITCODE) {{ {then} }}"),
        }
    }
}

/// Texto literal do PowerShell: entre aspas simples nada é expandido, e a
/// aspa simples se escreve dobrada.
fn powershell_literal(text: &str) -> String {
    format!("'{}'", text.replace('\'', "''"))
}

/// Um argumento para um programa (o `claude`), lançado pelo PowerShell 5.1.
///
/// O 5.1 monta a linha do programa sem escapar as aspas duplas de dentro do
/// argumento (só põe aspas em volta quando há espaço), e o programa a parte
/// pelas regras do C: um `"` do texto fecharia o argumento. Então o texto vai
/// já escapado para essas regras — `"` vira `\"`, as barras antes dele dobram,
/// e as do fim também quando o 5.1 vai pôr aspas em volta.
fn powershell_argument(text: &str) -> String {
    let mut escaped = String::with_capacity(text.len());
    let mut slashes = 0usize;
    for c in text.chars() {
        match c {
            '\\' => slashes += 1,
            '"' => {
                escaped.extend(std::iter::repeat_n('\\', slashes * 2 + 1));
                escaped.push('"');
                slashes = 0;
                continue;
            }
            _ => {}
        }
        if c != '\\' {
            escaped.extend(std::iter::repeat_n('\\', slashes));
            slashes = 0;
            escaped.push(c);
        }
    }
    let wrapped = text.chars().any(char::is_whitespace);
    escaped.extend(std::iter::repeat_n(
        '\\',
        if wrapped { slashes * 2 } else { slashes },
    ));
    powershell_literal(&escaped)
}

/// O que lança o filho: o processo do pty e o seu primeiro argumento.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Launch {
    pub program: PathBuf,
    pub args: Vec<String>,
}

/// Quem sobe no terminal: muda o rcfile do bash e se a linha é interativa.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    /// Terminal aberto pela rota (`/terminals`), com comando ou sem: sem o
    /// registro na trilha, como no Swift.
    Raw,
    /// O nó `shell` da bancada: registra cada comando (ADR-036).
    Shell,
    /// O nó de agente.
    Agent,
}

/// A pasta dos rcfiles do bash, dentro da pasta de dados (como a `zsh/`).
pub const BASH_DIR: &str = "bash";
/// O lançador POSIX de quem não entende a linha do Egeon.
const POSIX_LAUNCHER: &str = "/bin/sh";
/// O rcfile do bash para o nó `shell`, com o registro.
pub const BASH_SHELL_RC: &str = "shell.bashrc";
/// O rcfile do bash para o agente, sem o registro.
pub const BASH_AGENT_RC: &str = "agent.bashrc";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LaunchShell {
    pub path: PathBuf,
    pub kind: ShellKind,
}

impl LaunchShell {
    pub fn new(path: PathBuf) -> Self {
        let name = path
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        // O `.exe` do Windows não muda o tipo.
        let name = match name.len().checked_sub(4) {
            Some(cut) if name.is_char_boundary(cut) && name[cut..].eq_ignore_ascii_case(".exe") => {
                name[..cut].to_owned()
            }
            _ => name,
        };
        let kind = match name.as_str() {
            "zsh" => ShellKind::Zsh,
            "bash" => ShellKind::Bash,
            "sh" | "dash" | "ash" | "ksh" | "mksh" | "pdksh" | "yash" => ShellKind::Posix,
            "fish" => ShellKind::Fish,
            "powershell" | "pwsh" => ShellKind::PowerShell,
            _ => ShellKind::Other,
        };
        LaunchShell { path, kind }
    }

    /// O do macOS, e o de antes da decisão 53.
    pub fn zsh() -> Self {
        Self::new(PathBuf::from(LAUNCH_SHELL))
    }

    fn path_text(&self) -> String {
        self.path.to_string_lossy().into_owned()
    }

    /// A sintaxe da linha que este shell roda.
    pub fn syntax(&self) -> ShellSyntax {
        match self.kind {
            ShellKind::PowerShell => ShellSyntax::PowerShell,
            _ => ShellSyntax::Posix,
        }
    }

    /// O shell interativo do usuário, que a linha deixa no terminal quando o
    /// nó não tem comando. `bash_dir` é a pasta dos rcfiles do bash.
    pub fn interactive(&self, role: Role, bash_dir: &Path) -> String {
        let path = self.path_text();
        match (self.kind, role) {
            // Sem `exec` no PowerShell: o próprio processo fica aberto
            // (`-NoExit`) quando a linha não traz comando.
            (ShellKind::PowerShell, _) => String::new(),
            // O rcfile só vale em shell interativo que não é de login: é ele
            // que faz as vezes do login (veja `bash_hook_files`).
            (ShellKind::Bash, Role::Shell) => format!(
                "exec {path} --rcfile {} -i",
                shell_quote(&bash_dir.join(BASH_SHELL_RC).to_string_lossy())
            ),
            _ => format!("exec {path} -l"),
        }
    }

    /// O processo e os argumentos que rodam `command` em `cwd`: `cd '<cwd>';
    /// clear; <command>`, e o shell interativo quando não há comando.
    ///
    /// O `clear` vem do Swift: o `cd` e o perfil do login podem escrever antes
    /// do programa, e a tela começa limpa.
    pub fn launch(&self, cwd: &Path, command: Option<&str>, role: Role, bash_dir: &Path) -> Launch {
        if self.kind == ShellKind::PowerShell {
            return self.powershell_launch(cwd, command);
        }
        let interactive;
        let given = command.map(str::trim).filter(|c| !c.is_empty());
        let command = match given {
            Some(command) => command,
            None => {
                interactive = self.interactive(role, bash_dir);
                &interactive
            }
        };
        let line = format!(
            "cd {}; clear; {command}",
            shell_quote(&cwd.to_string_lossy())
        );
        match (self.kind, role) {
            // O agente no bash sobe interativo, com o rcfile que faz as vezes
            // do login: o `~/.bashrc` do Ubuntu sai logo no começo fora do modo
            // interativo, e é lá que o nvm põe o `claude` no PATH.
            (ShellKind::Bash, Role::Agent) => Launch {
                program: self.path.clone(),
                args: vec![
                    "--rcfile".to_owned(),
                    bash_dir.join(BASH_AGENT_RC).to_string_lossy().into_owned(),
                    "-ic".to_owned(),
                    line,
                ],
            },
            // O rcfile do nó shell já faz as vezes do login: com `-l` também
            // aqui fora, o ~/.profile rodaria duas vezes e o PATH dele entraria
            // em dobro.
            (ShellKind::Bash, Role::Shell) if given.is_none() => Launch {
                program: self.path.clone(),
                args: vec!["-c".to_owned(), line],
            },
            // O fish trata `\\` dentro de aspas simples de outro jeito, e a
            // linha do Egeon é POSIX: ela vai a um `sh`, mas pelo fish de
            // login, para o PATH do `config.fish` (nvm.fish, `fish_add_path`)
            // valer — pelo `sh -l` só o ~/.profile entraria, e o `claude` do
            // npm podia não achar. O fish passa o que vem depois do `-c` em
            // `$argv`. Sem comando, o nó só abre o fish, que lê o config dele.
            (ShellKind::Fish, _) if given.is_some() => Launch {
                program: self.path.clone(),
                args: vec![
                    "-l".to_owned(),
                    "-c".to_owned(),
                    format!("exec {POSIX_LAUNCHER} -c $argv[1]"),
                    line,
                ],
            },
            (ShellKind::Fish | ShellKind::Other, _) => Launch {
                program: PathBuf::from(POSIX_LAUNCHER),
                args: vec!["-lc".to_owned(), line],
            },
            _ => Launch {
                program: self.path.clone(),
                args: vec!["-lc".to_owned(), line],
            },
        }
    }
}

impl LaunchShell {
    /// `Set-Location` em vez de `cd` (o `-LiteralPath` não lê `[` e `]` da
    /// pasta como curinga) e `Clear-Host` em vez de `clear`. Sem comando, o
    /// PowerShell fica aberto depois da linha (`-NoExit`), com o perfil do
    /// usuário carregado, que é o login dele.
    fn powershell_launch(&self, cwd: &Path, command: Option<&str>) -> Launch {
        let given = command.map(str::trim).filter(|c| !c.is_empty());
        let mut line = format!(
            "Set-Location -LiteralPath {}; Clear-Host",
            powershell_literal(&cwd.to_string_lossy())
        );
        if let Some(command) = given {
            line.push_str("; ");
            line.push_str(command);
        }
        let mut args: Vec<String> = POWERSHELL_OPTIONS.map(str::to_owned).to_vec();
        if given.is_none() {
            args.push("-NoExit".to_owned());
        }
        args.push("-Command".to_owned());
        args.push(line);
        Launch {
            program: self.path.clone(),
            args,
        }
    }
}

// ── O gancho do bash ───────────────────────────────────────────────────────

/// O `--rcfile` do bash, gerado na pasta de dados (`bash/`) a cada arranque:
/// a técnica da integração de shell do VS Code, a mesma ideia do `ZDOTDIR` do
/// zsh.
///
/// Com `--rcfile` o bash não lê nada de login, então o arquivo faz as vezes
/// dele: carrega o `/etc/profile` e o primeiro de `~/.bash_profile`,
/// `~/.bash_login` e `~/.profile`, e o `~/.bashrc` se o profile não o carrega.
/// O do nó `shell` acrescenta o registro de cada comando na trilha. Um `bash`
/// que você abra à mão dentro do terminal não herda o rcfile e lê o seu `~`
/// normal.
pub fn bash_hook_files() -> Vec<(&'static str, String)> {
    vec![
        (BASH_SHELL_RC, format!("{BASH_LOGIN}\n{BASH_TRACE}")),
        (BASH_AGENT_RC, format!("{BASH_LOGIN}\n{BASH_AGENT}")),
    ]
}

const BASH_LOGIN: &str = r#"# Egeon Deck — carrega o seu login e o seu .bashrc. Gerado a cada arranque;
# não edite.
[ -r /etc/profile ] && . /etc/profile
__egeon_profile=
for __egeon_file in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
  if [ -r "$__egeon_file" ]; then
    __egeon_profile=$__egeon_file
    . "$__egeon_file"
    break
  fi
done
# O ~/.profile do Ubuntu e o ~/.bash_profile do Fedora já carregam o .bashrc:
# carregar duas vezes duplicaria o PATH e a partida do nvm.
if [ -r "$HOME/.bashrc" ] && ! { [ -n "$__egeon_profile" ] && grep -qs '\.bashrc' "$__egeon_profile"; }; then
  . "$HOME/.bashrc"
fi
unset __egeon_file __egeon_profile
"#;

const BASH_AGENT: &str = r#"# Sem controle de jobs: o agente fica no grupo do terminal, e remover o nó o
# encerra junto.
set +m
"#;

const BASH_TRACE: &str = r#"# O comando, não a saída: saída pode ser enorme. Em segundo plano e sem
# esperar, para não atrasar o prompt. O próprio `egeon trace` não entra — já
# está indo para a trilha. Filho do shell, e não órfão de um `( … & )`: o app
# reconhece o terminal subindo os pais de quem conecta. O `disown` e o
# `2>/dev/null` calam o aviso do job, como o `&!` do zsh.
__egeon_trace_line() {
  case "$1" in
    egeon\ trace*) return ;;
  esac
  { command egeon trace "\$ $1" >/dev/null 2>&1 & disown; } 2>/dev/null
}

if declare -p preexec_functions >/dev/null 2>&1; then
  # O bash-preexec já está no seu .bashrc: o registro entra nele.
  preexec_functions+=(__egeon_trace_line)
elif [ -z "$(trap -p DEBUG)" ]; then
  # O preexec do bash: o trap DEBUG roda antes de cada comando simples, e só o
  # primeiro depois do prompt é a linha que você digitou. A linha inteira vem
  # do histórico; se ela não entrou nele (HISTCONTROL, espaço na frente), vai
  # o comando simples.
  __egeon_at_prompt=
  __egeon_seen=
  __egeon_prompt() {
    __egeon_at_prompt=1
    __egeon_seen=$(HISTTIMEFORMAT= builtin history 1)
  }
  __egeon_debug() {
    [ -n "$__egeon_at_prompt" ] || return 0
    [ -z "${COMP_LINE:-}" ] || return 0
    __egeon_at_prompt=
    local entry line
    entry=$(HISTTIMEFORMAT= builtin history 1)
    if [ -n "$entry" ] && [ "$entry" != "$__egeon_seen" ]; then
      line=$(printf '%s\n' "$entry" | sed 's/^ *[0-9]*\*\{0,1\} *//')
    else
      line=$BASH_COMMAND
    fi
    __egeon_trace_line "$line"
  }
  trap '__egeon_debug' DEBUG
  # Por último no PROMPT_COMMAND: o que vem antes dele roda com o trap ainda
  # desarmado, e o prompt do seu .bashrc (starship, direnv) não vira comando.
  if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
    PROMPT_COMMAND+=(__egeon_prompt)
  else
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND
}__egeon_prompt"
  fi
fi
"#;

/// Escreve os rcfiles em `directory` (`<pasta de dados>/bash`). Devolve o que
/// não deu para escrever, em texto para o log.
pub fn install_bash_hook(directory: &Path) -> Vec<String> {
    if let Err(error) = std::fs::create_dir_all(directory) {
        return vec![format!(
            "bash: não consegui criar {} — {error}",
            directory.display()
        )];
    }
    bash_hook_files()
        .into_iter()
        .filter_map(|(name, body)| {
            std::fs::write(directory.join(name), body)
                .err()
                .map(|error| format!("bash: não consegui escrever {name} — {error}"))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(launch: &Launch) -> Vec<&str> {
        launch.args.iter().map(String::as_str).collect()
    }

    const BASH_DIR: &str = "/d/bash";

    #[test]
    fn o_tipo_vem_do_nome_do_programa() {
        let kind = |p: &str| LaunchShell::new(PathBuf::from(p)).kind;
        assert_eq!(kind("/bin/zsh"), ShellKind::Zsh);
        assert_eq!(kind("/usr/local/bin/zsh"), ShellKind::Zsh);
        assert_eq!(kind("/bin/bash"), ShellKind::Bash);
        assert_eq!(kind("/bin/sh"), ShellKind::Posix);
        assert_eq!(kind("/usr/bin/dash"), ShellKind::Posix);
        assert_eq!(kind("/usr/bin/fish"), ShellKind::Fish);
        assert_eq!(kind("/usr/bin/nu"), ShellKind::Other);
        assert_eq!(
            kind("C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"),
            ShellKind::PowerShell
        );
        assert_eq!(kind("pwsh.EXE"), ShellKind::PowerShell);
        assert_eq!(kind("/bin/zsh.exe"), ShellKind::Zsh);
    }

    #[test]
    fn powershell_sobe_com_a_linha_dele_e_fica_aberto_sem_comando() {
        let ps = LaunchShell::new(PathBuf::from("powershell.exe"));
        let dir = Path::new(BASH_DIR);
        assert_eq!(ps.interactive(Role::Shell, dir), "");
        let launch = ps.launch(
            Path::new("C:/Users/eu/o'projeto [1]"),
            None,
            Role::Shell,
            dir,
        );
        assert_eq!(launch.program, PathBuf::from("powershell.exe"));
        assert_eq!(
            args(&launch),
            vec![
                "-NoLogo",
                "-ExecutionPolicy",
                "Bypass",
                "-NoExit",
                "-Command",
                "Set-Location -LiteralPath 'C:/Users/eu/o''projeto [1]'; Clear-Host"
            ]
        );
        let agent = ps.launch(Path::new("C:/p"), Some(" claude "), Role::Agent, dir);
        assert_eq!(
            args(&agent),
            vec![
                "-NoLogo",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                "Set-Location -LiteralPath 'C:/p'; Clear-Host; claude"
            ]
        );
        // A linha vazia que o `interactive` devolve é "sem comando".
        let empty = ps.launch(Path::new("C:/p"), Some(""), Role::Shell, dir);
        assert!(args(&empty).contains(&"-NoExit"));
    }

    #[test]
    fn aspas_e_senao_de_cada_sintaxe() {
        let posix = LaunchShell::zsh().syntax();
        assert_eq!(posix, ShellSyntax::Posix);
        assert_eq!(posix.quote("o'brien"), r"'o'\''brien'");
        assert_eq!(posix.or_else("a", "b"), "a || b");
        let ps = LaunchShell::new(PathBuf::from("powershell.exe")).syntax();
        assert_eq!(ps.quote("simples"), "'simples'");
        assert_eq!(ps.quote("o'brien $HOME"), "'o''brien $HOME'");
        // As aspas duplas vão escapadas para o programa as ler como texto.
        assert_eq!(ps.quote(r#"diz "oi""#), r#"'diz \"oi\"'"#);
        assert_eq!(ps.quote(r#"a\"b"#), r#"'a\\\"b'"#);
        // Barra no fim: dobrada só quando o 5.1 vai pôr aspas em volta.
        assert_eq!(
            ps.quote(r"C:\pasta com espaço\"),
            r"'C:\pasta com espaço\\'"
        );
        assert_eq!(ps.quote(r"C:\pasta\"), r"'C:\pasta\'");
        assert_eq!(ps.or_else("a", "b"), "a; if ($LASTEXITCODE) { b }");
    }

    #[test]
    fn zsh_continua_como_no_swift() {
        let zsh = LaunchShell::zsh();
        let dir = Path::new(BASH_DIR);
        for role in [Role::Raw, Role::Shell, Role::Agent] {
            let launch = zsh.launch(Path::new("/Users/eu/meu projeto"), None, role, dir);
            assert_eq!(launch.program, PathBuf::from("/bin/zsh"));
            assert_eq!(
                args(&launch),
                vec!["-lc", "cd '/Users/eu/meu projeto'; clear; exec /bin/zsh -l"]
            );
        }
        let launch = zsh.launch(Path::new("/tmp"), Some("  "), Role::Raw, dir);
        assert_eq!(
            args(&launch),
            vec!["-lc", "cd '/tmp'; clear; exec /bin/zsh -l"]
        );
        let launch = zsh.launch(Path::new("/tmp"), Some("claude"), Role::Agent, dir);
        assert_eq!(args(&launch), vec!["-lc", "cd '/tmp'; clear; claude"]);
    }

    #[test]
    fn bash_shell_sobe_com_o_rcfile_do_registro() {
        let bash = LaunchShell::new(PathBuf::from("/bin/bash"));
        let launch = bash.launch(Path::new("/tmp"), None, Role::Shell, Path::new(BASH_DIR));
        assert_eq!(launch.program, PathBuf::from("/bin/bash"));
        assert_eq!(
            args(&launch),
            vec![
                "-c",
                "cd '/tmp'; clear; exec /bin/bash --rcfile '/d/bash/shell.bashrc' -i"
            ]
        );
        // Com comando próprio não há rcfile: o login vem do `-l`.
        let make = bash.launch(
            Path::new("/tmp"),
            Some("make"),
            Role::Shell,
            Path::new(BASH_DIR),
        );
        assert_eq!(args(&make), vec!["-lc", "cd '/tmp'; clear; make"]);
        // Terminal da rota: o login normal, sem registro.
        let raw = bash.launch(Path::new("/tmp"), None, Role::Raw, Path::new(BASH_DIR));
        assert_eq!(
            args(&raw),
            vec!["-lc", "cd '/tmp'; clear; exec /bin/bash -l"]
        );
    }

    #[test]
    fn bash_agente_sobe_interativo_com_o_rcfile_do_login() {
        let bash = LaunchShell::new(PathBuf::from("/bin/bash"));
        let launch = bash.launch(
            Path::new("/p"),
            Some("claude --model 'opus'"),
            Role::Agent,
            Path::new(BASH_DIR),
        );
        assert_eq!(launch.program, PathBuf::from("/bin/bash"));
        assert_eq!(
            args(&launch),
            vec![
                "--rcfile",
                "/d/bash/agent.bashrc",
                "-ic",
                "cd '/p'; clear; claude --model 'opus'"
            ]
        );
    }

    #[test]
    fn fish_abre_nele_e_a_linha_vai_a_um_sh_pelo_fish_de_login() {
        let fish = LaunchShell::new(PathBuf::from("/usr/bin/fish"));
        let launch = fish.launch(Path::new("/tmp"), None, Role::Shell, Path::new(BASH_DIR));
        assert_eq!(launch.program, PathBuf::from("/bin/sh"));
        assert_eq!(
            args(&launch),
            vec!["-lc", "cd '/tmp'; clear; exec /usr/bin/fish -l"]
        );
        let agent = fish.launch(
            Path::new("/tmp"),
            Some("claude --model 'opus'"),
            Role::Agent,
            Path::new(BASH_DIR),
        );
        assert_eq!(agent.program, PathBuf::from("/usr/bin/fish"));
        assert_eq!(
            args(&agent),
            vec![
                "-l",
                "-c",
                "exec /bin/sh -c $argv[1]",
                "cd '/tmp'; clear; claude --model 'opus'"
            ]
        );
    }

    #[test]
    fn fora_do_posix_abre_no_shell_mas_a_linha_vai_pelo_sh() {
        let nu = LaunchShell::new(PathBuf::from("/usr/bin/nu"));
        let launch = nu.launch(Path::new("/tmp"), None, Role::Shell, Path::new(BASH_DIR));
        assert_eq!(launch.program, PathBuf::from("/bin/sh"));
        assert_eq!(
            args(&launch),
            vec!["-lc", "cd '/tmp'; clear; exec /usr/bin/nu -l"]
        );
        let agent = nu.launch(
            Path::new("/tmp"),
            Some("claude"),
            Role::Agent,
            Path::new(BASH_DIR),
        );
        assert_eq!(agent.program, PathBuf::from("/bin/sh"));
        let dash = LaunchShell::new(PathBuf::from("/bin/sh"));
        let launch = dash.launch(Path::new("/tmp"), None, Role::Shell, Path::new(BASH_DIR));
        assert_eq!(launch.program, PathBuf::from("/bin/sh"));
        assert_eq!(
            args(&launch),
            vec!["-lc", "cd '/tmp'; clear; exec /bin/sh -l"]
        );
    }

    #[test]
    fn rcfiles_carregam_o_login_e_so_o_do_shell_registra() {
        let files = bash_hook_files();
        let get = |name: &str| {
            files
                .iter()
                .find(|(n, _)| *n == name)
                .map(|(_, body)| body.clone())
                .unwrap_or_default()
        };
        let (shell, agent) = (get(BASH_SHELL_RC), get(BASH_AGENT_RC));
        for body in [&shell, &agent] {
            assert!(body.contains(". /etc/profile"));
            assert!(body.contains(r#""$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile""#));
            assert!(body.contains(r#". "$HOME/.bashrc""#));
        }
        assert!(shell.contains("command egeon trace"));
        assert!(shell.contains("egeon\\ trace*) return"));
        assert!(!agent.contains("egeon trace"));
        assert!(agent.contains("set +m"));
    }

    #[test]
    fn instala_os_dois_rcfiles_e_diz_o_que_falhou() -> std::io::Result<()> {
        let dir = tempfile::tempdir()?;
        let target = dir.path().join("bash");
        assert!(install_bash_hook(&target).is_empty());
        assert!(target.join(BASH_SHELL_RC).is_file());
        assert!(target.join(BASH_AGENT_RC).is_file());
        std::fs::write(dir.path().join("arquivo"), "")?;
        assert_eq!(install_bash_hook(&dir.path().join("arquivo/bash")).len(), 1);
        Ok(())
    }
}
