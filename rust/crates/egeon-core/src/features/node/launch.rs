//! O que sobe num terminal: a linha de comando de cada nó, o texto que o agente
//! recebe como system prompt, o ambiente do processo e o gancho do shell.
//!
//! Porte do `launchPlan`, do `catalog(for:in:agents:)` e do
//! `conversationCommand` do `main.swift`, do ambiente que o `TerminalNode` monta
//! e do `ShellHook`. Tudo puro: quem lança o pty, escreve os arquivos e enfileira
//! o papel é o core (`terminal::model::launch_args` monta o `zsh -lc` em volta
//! do `command` daqui).
//!
//! O perfil do agente é do `agent::model::AgentProfile`; aqui só se decide como
//! ele é usado para este nó.

use std::collections::BTreeMap;
use std::path::Path;

use super::model::{NodeConfig, NodeKind};
use crate::features::agent::claude::hooks::{FLAVOR_VARIABLE, HOME_VARIABLE, TARGET_VARIABLE};
use crate::features::agent::model::AgentProfile;
use crate::features::agent::rules::agent_rules_block;
use crate::features::processes::mark;
use crate::features::terminal::model::TERM;
use crate::features::terminal::shell::ShellSyntax;

/// O comando de um nó de shell sem comando próprio no macOS. No Linux vem do
/// shell do usuário (`terminal::shell::LaunchShell::interactive`).
pub const DEFAULT_SHELL: &str = "exec /bin/zsh -l";

/// O que sobe: a linha, o papel que ainda precisa ser digitado na TUI e se o
/// gancho de relato foi instalado.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LaunchPlan {
    pub command: String,
    /// Papel, protocolo e regras para entrar na fila do Dispatcher quando o CLI
    /// não tem flag de system prompt. `None` quando já foram pela linha.
    pub prompt_to_inject: Option<String>,
    /// A linha leva o gancho que relata fim de turno e pedido de permissão
    /// (ADR-024).
    pub hooked: bool,
    /// Linhas de log para o core escrever.
    pub notes: Vec<String>,
}

/// A linha de comando do nó. `catalog` é [`catalog`], `rules` o bloco de
/// [`agent_rules_block`], `hook_file` o `claude-hooks.json`, `default_shell`
/// o que sobe no nó sem comando ([`DEFAULT_SHELL`] no macOS) e `syntax` a do
/// shell que vai rodar a linha (as aspas dos argumentos).
pub fn launch_plan(
    node: &NodeConfig,
    profile: Option<&AgentProfile>,
    catalog: Option<&str>,
    rules: Option<&str>,
    hook_file: &str,
    default_shell: &str,
    syntax: ShellSyntax,
) -> LaunchPlan {
    let plain = |command: String| LaunchPlan {
        command,
        prompt_to_inject: None,
        hooked: false,
        notes: Vec::new(),
    };
    let base = node
        .cmd
        .clone()
        .or_else(|| profile.map(|p| p.command.join(" ")))
        .unwrap_or_else(|| default_shell.to_owned());

    let (NodeKind::Agent, Some(profile)) = (node.kind, profile) else {
        return plain(base);
    };

    // Modelo e esforço são flags do binário do perfil: com `cmd` trocado por
    // outro programa, anexar `--model` mataria o terminal no arranque.
    let model_flags: Vec<String> = if profile.runs_own_binary(&base) {
        let mut flags = profile
            .model_arguments(node.model.as_deref())
            .unwrap_or_default();
        flags.extend(
            profile
                .effort_launch(node.effort.as_deref(), node.ultracode == Some(true))
                .arguments,
        );
        flags
    } else {
        Vec::new()
    };
    let quoted = |flags: &[String]| {
        flags
            .iter()
            .map(|f| syntax.quote(f))
            .collect::<Vec<_>>()
            .join(" ")
    };
    let suffix = if model_flags.is_empty() {
        String::new()
    } else {
        format!(" {}", quoted(&model_flags))
    };

    let Some(text) = profile.system_prompt_text(node.effective_prompt(), catalog, rules) else {
        return plain(format!("{base}{suffix}"));
    };

    if profile.runs_own_binary(&base)
        && let Some(arguments) = profile.system_prompt_arguments(&text)
    {
        let mut extras = model_flags;
        extras.extend(arguments);
        // O gancho de relato entra junto: é o que faz o app saber quando VOCÊ
        // troca de conversa dentro da TUI, e é por ele que chegam o fim de turno
        // e o pedido de permissão (ADR-024).
        let report = profile.report_arguments(hook_file);
        let hooked = report.is_some();
        extras.extend(report.into_iter().flatten());
        let flags = format!(" {}", quoted(&extras));
        return LaunchPlan {
            command: conversation_command(&base, &flags, node, profile, syntax),
            prompt_to_inject: None,
            hooked,
            notes: Vec::new(),
        };
    }

    // CLI sem flag de system prompt (ou `cmd` trocado por outro programa): resta
    // injetar como primeira mensagem. Vale a pena junto de um papel ou de
    // regras, que já iam ser injetados de qualquer jeito; só pelo protocolo não
    // — seria gastar um turno em toda bancada para um marcador que se dilui
    // depois de vinte mensagens. Aí o terminal fica só com o silêncio.
    let has_role = node.effective_prompt().is_some_and(|p| !p.is_empty())
        || rules.is_some_and(|r| !r.is_empty());
    let command = format!("{base}{suffix}");
    if !has_role {
        let mut plan = plain(command);
        if profile.attention_config().active_marker().is_some() {
            plan.notes.push(format!(
                "agente {}: sem flag de system prompt, o protocolo de marcador não sobe — a \
                 detecção fica só no silêncio",
                profile.display_name
            ));
        }
        return plan;
    }
    LaunchPlan {
        command,
        prompt_to_inject: Some(text),
        hooked: false,
        notes: Vec::new(),
    }
}

/// A linha de comando que retoma a conversa deste terminal, ou cria a primeira.
///
/// Retomar e criar são flags diferentes no CLI: `--session-id` num id que já
/// existe é recusado com `already in use`. Então a primeira subida cria, e as
/// seguintes retomam.
///
/// O `||` é a rede: `--resume` de um id cujo arquivo de conversa não existe mais
/// — porque você limpou, ou porque a criação falhou antes de o CLI gravar — sai
/// com 1, e aí a mesma linha cria a conversa com aquele id em vez de deixar o
/// terminal morto.
pub fn conversation_command(
    base: &str,
    flags: &str,
    node: &NodeConfig,
    profile: &AgentProfile,
    syntax: ShellSyntax,
) -> String {
    let Some(id) = node
        .conversation_id
        .as_deref()
        .filter(|_| profile.keeps_conversation())
    else {
        return format!("{base}{flags}");
    };
    let (Some(resume), Some(fresh)) = (
        AgentProfile::conversation_arguments(&profile.resume, id),
        AgentProfile::conversation_arguments(&profile.new_session, id),
    ) else {
        return format!("{base}{flags}");
    };
    let line = |arguments: &[String]| {
        let quoted: Vec<String> = arguments.iter().map(|a| syntax.quote(a)).collect();
        format!("{base} {}{flags}", quoted.join(" "))
    };
    // `conversationStarted` diz se já houve uma primeira subida: sem isso a linha
    // de estreia mostraria "No conversation found" antes de criar.
    if node.has_started_conversation() {
        syntax.or_else(&line(&resume), &line(&fresh))
    } else {
        line(&fresh)
    }
}

// ── O catálogo de cada nó ──────────────────────────────────────────────────

fn paragraphs(parts: &[&str]) -> String {
    parts.join("\n\n")
}

/// Como este nó fala com os outros, para o system prompt.
///
/// Não lista os vizinhos: a lista envelhece. O catálogo antigo era montado no
/// arranque, então uma aresta criada depois nunca chegava — a seta aparecia no
/// canvas e a ligação estava morta até você recriar o nó. Aqui vai só o caminho
/// para PERGUNTAR, e a resposta é sempre a de agora.
///
/// Vai em todo nó de agente, com ou sem aresta hoje, pelo mesmo motivo: quem
/// sobe sem vizinho pode ganhar um no minuto seguinte. O texto é curto de
/// propósito: ele entra em toda conversa deste terminal, e é prefixo de cache —
/// quanto menos muda, melhor.
///
/// `syntax` é a do shell em que o agente roda os comandos: no PowerShell o
/// texto vai por here-string, e não por heredoc (decisão 54).
pub fn catalog(node: &NodeConfig, syntax: ShellSyntax) -> Option<String> {
    if node.kind != NodeKind::Agent {
        return None;
    }
    let mut out = match syntax {
        ShellSyntax::Posix => CATALOG.to_owned(),
        ShellSyntax::PowerShell => POWERSHELL_CATALOG.to_owned(),
    };
    if node.is_maestro() {
        out.push_str("\n\n");
        out.push_str(MAESTRO_SECTION);
    }
    if node.approves_team_permissions() {
        out.push_str("\n\n");
        out.push_str(APPROVER_SECTION);
    }
    Some(out)
}

const COMMANDS: &str = "  egeon peers                     quem você pode acionar agora
  egeon status                    quem VOCÊ é: endereço, papel, bancada
  egeon peek <endereço> [linhas]  o que ele mostra agora, sem interromper
  egeon send <endereço> <<'MB'    manda o texto para ele
  (o que você quer dizer)
  MB
  egeon trace <<'MB'              registra na trilha da bancada
  pedido: … — entrega: …
  MB";

/// O padrão do PowerShell 5.1 para o que vai a um programa pelo pipe é
/// ASCII, que troca acento por `?`; o `'@` que fecha o here-string só vale
/// no começo da linha, por isso o exemplo não tem recuo.
const POWERSHELL_COMMANDS: &str = "  egeon peers                     quem você pode acionar agora
  egeon status                    quem VOCÊ é: endereço, papel, bancada
  egeon peek <endereço> [linhas]  o que ele mostra agora, sem interromper
  egeon send <endereço>           manda para ele o texto do stdin
  egeon trace                     registra o texto do stdin na trilha da bancada

No PowerShell, defina o UTF-8 sem BOM antes de passar texto ao `egeon` (o padrão troca \
acento por `?`) e mande o texto por here-string, com o `'@` que fecha no começo da linha:

$OutputEncoding = [Text.UTF8Encoding]::new($false)
@'
(o que você quer dizer)
'@ | egeon send <endereço>
@'
pedido: … — entrega: …
'@ | egeon trace";

static CATALOG: std::sync::LazyLock<String> = std::sync::LazyLock::new(|| catalog_with(COMMANDS));

static POWERSHELL_CATALOG: std::sync::LazyLock<String> =
    std::sync::LazyLock::new(|| catalog_with(POWERSHELL_COMMANDS));

fn catalog_with(commands: &str) -> String {
    paragraphs(&[
        "Este terminal é um nó do Egeon Deck e tem vizinhos endereçáveis. Use o comando `egeon`:",
        commands,
        "Mensagem que chega marcada com `[ED] mensagem de <alguém>` veio de um terminal que \
         parou e espera o seu resultado — ele não vê a sua tela. Termine respondendo a ele com \
         `egeon send`, uma ou duas linhas: o que você entregou, ou por que não deu. E se você \
         parar para perguntar algo ao usuário no meio, avise o remetente ANTES de parar: quem \
         para calado deixa o outro esperando sem saber de nada.",
        "Lista vazia significa que ninguém está ligado a você neste momento; ela muda enquanto \
         você trabalha, então consulte na hora em vez de confiar na memória. Quando o pedido \
         for para outro agente, olhe os vizinhos ANTES de abrir um subagente do seu próprio \
         CLI: o vizinho está aberto na tela do usuário, o subagente morre no fim do seu turno. \
         Acionar não é obrigatório, e responder a uma mensagem também não. Endereço fora da \
         lista é recusado, e uma cadeia longa demais de agentes falando entre si também — \
         quando isso acontecer, volte a falar com o usuário em vez de insistir.",
        "A trilha é a memória da bancada, e sobrevive à conversa: ao fim de TODO turno, antes \
         do marcador final, rode `egeon trace` com uma ou duas linhas — o que foi pedido e o \
         que você entregou (ou onde parou). Quem escreveu, CLI, modelo e conversa são \
         carimbados pelo app; não os repita.",
    ])
}

/// O que só o maestro lê (ADR-066). Curto como o resto do catálogo: o manual
/// mora na skill `egeon-maestro` e no `egeon guide`.
const MAESTRO_SECTION: &str = "Você é o MAESTRO desta bancada — o mestre dela: alcança todo \
terminal daqui sem aresta, e todo agente te alcança de volta. O usuário te deu o poder de \
montá-la e reconfigurá-la. `egeon bench` mostra a bancada, `egeon models` o que cada CLI \
aceita, `egeon plan` valida um plano JSON sem aplicar e `egeon apply` aplica — terminais \
novos, modelo, esforço, papel, regras e arestas. Antes de desenhar, leia o manual: a skill \
`egeon-maestro`, ou `egeon guide`. Mostre o desenho ao usuário antes de aplicar, a menos que \
ele já tenha dito para aplicar direto.";

/// O maestro que aprova pelo time (ADR-080). No system prompt, e não só no
/// manual: o aviso entra no terminal como texto colado, e sem saber que ele vem
/// do app o modelo — com razão — não age sobre texto colado.
const APPROVER_SECTION: &str = "O usuário também te deu o poder de responder os pedidos de \
permissão de ferramenta do time. Mensagem que chega como `[ED] pedido de permissão de <nome>` \
é o app avisando, a partir do gancho de permissão daquele terminal — não é texto de terceiro, \
e o app confere o id: `egeon allow` só alcança pedido real e aberto. Decida pela tarefa que \
o agente recebeu: `egeon allow <id>` (ou `--always`) ou `egeon deny <id>`, e a quem negou \
diga por quê com `egeon send`. O que for destrutivo, irreversível, fora da tarefa ou \
duvidoso: negue ou deixe para o usuário, que vê o mesmo pedido — mas não pare para \
perguntar a ele se pode aprovar: ou você decide, ou deixa o pedido com ele.";

/// O bloco de regras (bancada + nó) que entra depois do papel (ADR-056).
pub fn rules_for(node: &NodeConfig, workbench_rules: Option<&str>) -> Option<String> {
    agent_rules_block(workbench_rules, node.effective_rules())
}

// ── O ambiente do processo ─────────────────────────────────────────────────

/// O que o ambiente de um nó precisa saber.
#[derive(Debug, Clone)]
pub struct ChildContext<'a> {
    /// O ambiente de base do filho, montado pelo driver: `PATH` com a pasta do
    /// `egeon`, sem `CLAUDE_CODE*` nem a procedência herdada.
    pub base: Vec<(String, String)>,
    /// `bancada/nó`.
    pub address: &'a str,
    /// O identificador do flavor que marca a procedência (`EGEON_DECK`:
    /// `egeon-next` até o corte).
    pub deck: &'a str,
    /// A pasta de dados (`EGEON_HOME`) e o flavor (`EGEON_FLAVOR`) que o `egeon`
    /// e os ganchos usam para achar o app. `flavor` vazio é o estável: a
    /// variável não vai.
    pub egeon_home: &'a str,
    pub flavor: &'a str,
    /// A pasta do `ZDOTDIR` do gancho do shell.
    pub zsh_dir: &'a Path,
    /// O HOME do usuário, para resolver `~` no ambiente do perfil.
    pub home: &'a Path,
}

/// O ambiente do processo de um nó de shell ou de agente.
///
/// Por cima do ambiente de base, nesta ordem: o do perfil, o do esforço (o
/// nível, quando o ultracode ocupa a flag) e a configuração escolhida no nó. É
/// aqui que se decide com qual conjunto de plugins, MCP e settings o CLI sobe —
/// herdar o do app não serve: lançado pelo Finder, ele não herdou o shell de
/// ninguém.
///
/// O gancho do CLI roda num processo filho e precisa saber de qual terminal
/// está falando; o endereço de dispatch é o identificador que o app usa em todo
/// lugar. Só em nó com agente: shell não tem conversa para rastrear, e a
/// variável ali seria lixo no ambiente de tudo que você rodar à mão. A procedência
/// vai em todo nó, shell incluído: é o que diz de onde veio o processo que ficou
/// de pé quando o terminal fechou (ADR-083). Shell não tem modelo para instruir:
/// quem registra na trilha é o `preexec` do zsh, que entra por `ZDOTDIR`
/// (ADR-036).
pub fn node_environment(
    node: &NodeConfig,
    profile: Option<&AgentProfile>,
    ctx: &ChildContext<'_>,
) -> (Vec<(String, String)>, Vec<String>) {
    let mut notes = Vec::new();
    let mut environment: BTreeMap<String, String> = ctx.base.iter().cloned().collect();
    environment.insert("TERM".to_owned(), TERM.to_owned());

    if let Some(profile) = profile {
        environment.extend(profile.resolved_environment(ctx.home));
        environment.extend(
            profile
                .effort_launch(node.effort.as_deref(), node.ultracode == Some(true))
                .environment,
        );
        if let (Some(config), Some(variable)) = (&node.config, &profile.config_env) {
            environment.insert(variable.clone(), config.clone());
            notes.push(format!("terminal[{}]: {variable}={config}", ctx.address));
        }
        environment.insert(TARGET_VARIABLE.to_owned(), ctx.address.to_owned());
    }
    environment.insert(HOME_VARIABLE.to_owned(), ctx.egeon_home.to_owned());
    // Só o dev acende a variável: o `egeon` sem ela já fala com o estável, e uma
    // variável vazia seria lixo no ambiente de tudo que se roda à mão.
    if ctx.flavor.is_empty() {
        environment.remove(FLAVOR_VARIABLE);
    } else {
        environment.insert(FLAVOR_VARIABLE.to_owned(), ctx.flavor.to_owned());
    }

    let mut stamped: Vec<(String, String)> = environment.into_iter().collect();
    mark::stamp(&mut stamped, ctx.address, ctx.deck);
    if profile.is_none() {
        stamped.retain(|(k, _)| k != "ZDOTDIR");
        stamped.push((
            "ZDOTDIR".to_owned(),
            ctx.zsh_dir.to_string_lossy().into_owned(),
        ));
    }
    (stamped, notes)
}

// ── O gancho do shell ──────────────────────────────────────────────────────

/// Faz o terminal comum registrar na trilha cada comando que você roda — o
/// comando, nunca a saída (ADR-036).
///
/// Um shell não tem modelo para instruir, então o registro vem do `preexec` do
/// zsh. O gancho entra por `ZDOTDIR`: o nó `shell` sobe com a variável apontando
/// para a pasta `zsh/`, e os quatro arquivos só carregam os seus de `$HOME` e, no
/// `.zshrc`, acrescentam o hook. É a técnica da integração de shell do VS Code —
/// o único jeito de enfiar um `preexec` sem editar o `.zshrc` de ninguém.
/// `ZDOTDIR` é desfeito ao fim, para um `zsh` que você abra à mão dentro do
/// terminal ler o seu `$HOME` normal.
pub fn shell_hook_files() -> Vec<(&'static str, String)> {
    let forward = |name: &str| {
        format!(
            "# Egeon Deck — repassa ao seu {name}. Gerado a cada arranque; não edite.\n\
             [ -f \"$HOME/{name}\" ] && source \"$HOME/{name}\"\n"
        )
    };
    vec![
        (".zshenv", forward(".zshenv")),
        (".zprofile", forward(".zprofile")),
        (".zlogin", forward(".zlogin")),
        (".zshrc", ZSHRC.to_owned()),
    ]
}

const ZSHRC: &str = "# Egeon Deck — repassa ao seu .zshrc e registra cada comando na trilha da
# bancada. Gerado a cada arranque; não edite.
[ -f \"$HOME/.zshrc\" ] && source \"$HOME/.zshrc\"

# O comando, não a saída: saída pode ser enorme. Em segundo plano e sem
# esperar, para não atrasar o prompt. O próprio `egeon trace` não entra —
# já está indo para a trilha.
_egeon_trace_preexec() {
    case \"$1\" in
      egeon\\ trace*) return ;;
    esac
    command egeon trace \"\\$ $1\" >/dev/null 2>&1 &!
}
autoload -Uz add-zsh-hook
add-zsh-hook preexec _egeon_trace_preexec

# Daqui em diante o zsh já leu o que precisava: filhos usam o seu $HOME.
unset ZDOTDIR
";

/// Escreve os quatro arquivos em `directory` (`<pasta de dados>/zsh`), a cada
/// arranque. Devolve o que não deu para escrever, em texto para o log.
pub fn install_shell_hook(directory: &Path) -> Vec<String> {
    let mut problems = Vec::new();
    if let Err(error) = std::fs::create_dir_all(directory) {
        problems.push(format!(
            "zsh: não consegui criar {} — {error}",
            directory.display()
        ));
        return problems;
    }
    for (name, body) in shell_hook_files() {
        if let Err(error) = std::fs::write(directory.join(name), body) {
            problems.push(format!("zsh: não consegui escrever {name} — {error}"));
        }
    }
    problems
}
