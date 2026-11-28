//! Quem é do Egeon entre os processos do usuário, a ordem em que a lista os
//! mostra e quais órfãos a limpeza leva.

use std::collections::{HashMap, HashSet};
use std::time::SystemTime;

use serde::Deserialize;
use serde_json::{Value, json};

use super::mark;
use crate::ports::procs::RawProcess;

/// Nomes (`p_comm`) de outro Egeon de pé: o Swift de hoje e o core novo.
/// Processo debaixo de outro Egeon é daquele.
pub const APP_NAMES: [&str; 2] = ["EgeonDeck", "egeon-app"];

/// Um processo lançado pelo Egeon: debaixo do app, ou órfão.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EgeonProcess {
    pub pid: u32,
    pub ppid: u32,
    pub started: SystemTime,
    pub command: String,
    /// O endereço do nó (`bancada/id`). `None` é do próprio app, fora de
    /// terminal.
    pub node: Option<String>,
    /// O pai morreu e o processo ficou de pé — o que ninguém mais vai
    /// encerrar.
    pub orphan: bool,
}

impl EgeonProcess {
    fn from_raw(raw: &RawProcess, node: Option<String>, orphan: bool) -> Self {
        Self {
            pid: raw.pid,
            ppid: raw.ppid,
            started: raw.started,
            command: raw.command.clone(),
            node,
            orphan,
        }
    }

    pub fn json(&self, now: SystemTime) -> Value {
        json!({
            "pid": self.pid,
            "ppid": self.ppid,
            "node": self.node.as_deref().unwrap_or("app"),
            "orphan": self.orphan,
            "age": seconds_between(self.started, now).max(0.0) as u64,
            "command": self.command,
        })
    }
}

fn seconds_between(from: SystemTime, to: SystemTime) -> f64 {
    match to.duration_since(from) {
        Ok(d) => d.as_secs_f64(),
        Err(e) => -e.duration().as_secs_f64(),
    }
}

/// `ProcessTable.classify`. Dois caminhos, porque um só não basta: o que
/// descende deste app é dele pela árvore, mesmo que tenha limpado o
/// ambiente; o que perdeu o pai só se reconhece pela marca. Processo debaixo
/// de outro Egeon (o dev, visto do estável) é daquele, e não aparece aqui nem
/// como órfão.
pub fn classify(all: &[RawProcess], app: u32, deck: &str) -> Vec<EgeonProcess> {
    let mut children: HashMap<u32, Vec<&RawProcess>> = HashMap::new();
    for process in all.iter().filter(|p| p.pid != p.ppid) {
        children.entry(process.ppid).or_default().push(process);
    }
    let mut result = Vec::new();
    let mut seen = HashSet::from([app]);

    walk(&children, &mut seen, &mut result, app, None, false);

    // Os outros apps e tudo debaixo deles saem antes de procurar órfão.
    for other in all
        .iter()
        .filter(|p| APP_NAMES.contains(&p.name.as_str()) && p.pid != app)
    {
        let mut stack = vec![other.pid];
        while let Some(pid) = stack.pop() {
            if !seen.insert(pid) {
                continue;
            }
            stack.extend(children.get(&pid).into_iter().flatten().map(|p| p.pid));
        }
    }

    // Do mais velho para o mais novo: o primeiro marcado de uma árvore órfã
    // leva os filhos, que entram com a marca dele se não tiverem a própria.
    let mut by_age: Vec<&RawProcess> = all.iter().collect();
    by_age.sort_by_key(|p| p.started);
    for process in by_age {
        if seen.contains(&process.pid) {
            continue;
        }
        let Some(node) = mark::node_in(&process.environment) else {
            continue;
        };
        // App aberto com `open` de um terminal do Egeon (o Docker Desktop que
        // um agente subiu) leva o ambiente de quem pediu — a marca inclusa —,
        // mas é outro app, de pé por conta própria. O bundle o distingue.
        if let Some(bundle) = process.environment.get(mark::BUNDLE_VARIABLE)
            && !bundle.starts_with(mark::BUNDLE_PREFIX)
        {
            continue;
        }
        // Sem `EGEON_DECK` é de antes da marca: não dá para saber o flavor, e
        // esconder seria pior que mostrar a mais.
        if let Some(owner) = process.environment.get(mark::DECK)
            && owner != deck
        {
            continue;
        }
        let node = node.to_owned();
        seen.insert(process.pid);
        result.push(EgeonProcess::from_raw(process, Some(node.clone()), true));
        walk(
            &children,
            &mut seen,
            &mut result,
            process.pid,
            Some(node),
            true,
        );
    }

    // O laço que relança o filho (`while true; do aws ssm …; done`) é o dono
    // da árvore, mas a marca dele às vezes não se lê; só os filhos a mostram,
    // e eles renascem a cada queda. Pai sem marca legível, solto no launchd,
    // que não é app, vira órfão junto com a família.
    let by_pid: HashMap<u32, &RawProcess> = all.iter().rev().map(|p| (p.pid, p)).collect();
    // Só os que já estavam: o Swift percorre `result.indices` de antes do
    // laço, e quem entra agora não adota mais ninguém.
    for index in 0..result.len() {
        if result[index].orphan {
            let mut chain: Vec<&RawProcess> = Vec::new();
            let mut parent = by_pid.get(&result[index].ppid).copied();
            while let Some(candidate) = parent {
                if seen.contains(&candidate.pid)
                    || candidate.pid <= 1
                    || mark::node_in(&candidate.environment).is_some()
                    || is_app(candidate)
                {
                    break;
                }
                chain.push(candidate);
                parent = by_pid.get(&candidate.ppid).copied();
            }
            if chain.last().is_some_and(|top| top.ppid == 1) {
                let node = result[index].node.clone();
                for process in chain.iter().rev() {
                    if seen.insert(process.pid) {
                        result.push(EgeonProcess::from_raw(process, node.clone(), true));
                    }
                }
            }
        }
    }

    // O `zsh -lc` de um agente leva o system prompt na linha de comando, e o
    // kernel corta o buffer antes de chegar ao ambiente. Os filhos dele têm a
    // marca; de baixo para cima, o pai a pega deles (filho sempre entra depois
    // do pai).
    let mut by_parent: HashMap<u32, String> = HashMap::new();
    for process in result.iter_mut().rev() {
        if process.node.is_none() {
            process.node = by_parent.get(&process.pid).cloned();
        }
        if let Some(node) = &process.node {
            by_parent.insert(process.ppid, node.clone());
        }
    }
    result
}

fn walk(
    children: &HashMap<u32, Vec<&RawProcess>>,
    seen: &mut HashSet<u32>,
    result: &mut Vec<EgeonProcess>,
    parent: u32,
    node: Option<String>,
    orphan: bool,
) {
    for child in children.get(&parent).into_iter().flatten() {
        if !seen.insert(child.pid) {
            continue;
        }
        let own = mark::node_in(&child.environment)
            .map(str::to_owned)
            .or_else(|| node.clone());
        result.push(EgeonProcess::from_raw(child, own.clone(), orphan));
        walk(children, seen, result, child.pid, own, orphan);
    }
}

/// App de pé por conta própria: outro Egeon, bundle que não é o nosso, ou
/// executável de dentro de um `.app`.
fn is_app(process: &RawProcess) -> bool {
    if APP_NAMES.contains(&process.name.as_str()) {
        return true;
    }
    if let Some(bundle) = process.environment.get(mark::BUNDLE_VARIABLE)
        && !bundle.starts_with(mark::BUNDLE_PREFIX)
    {
        return true;
    }
    process.command.contains(".app/Contents/MacOS/")
}

/// Órfãos primeiro, que é o que se veio procurar; dentro de cada grupo por
/// nó, e no nó do mais velho para o mais novo — o pai antes dos filhos.
pub fn ordered(mut processes: Vec<EgeonProcess>) -> Vec<EgeonProcess> {
    processes.sort_by(|a, b| {
        b.orphan
            .cmp(&a.orphan)
            .then_with(|| {
                a.node
                    .as_deref()
                    .unwrap_or("")
                    .cmp(b.node.as_deref().unwrap_or(""))
            })
            .then_with(|| a.started.cmp(&b.started))
            .then_with(|| a.pid.cmp(&b.pid))
    });
    processes
}

/// Idade com a unidade que importa: o órfão de 19 dias tem que gritar
/// diferente do de 40 segundos.
pub fn age(seconds: f64) -> String {
    let s = seconds.max(0.0) as u64;
    match s {
        0..60 => format!("{s} s"),
        60..3600 => format!("{} min", s / 60),
        3600..86_400 => format!("{} h {} min", s / 3600, s % 3600 / 60),
        _ => format!("{} d {} h", s / 86_400, s % 86_400 / 3600),
    }
}

/// A limpeza periódica dos órfãos: de quanto em quanto tempo, a partir de
/// que idade, e quem nunca entra. Em `processes.json`, editável à mão; chave
/// que faltar fica no padrão.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(from = "ReapPolicyFile")]
pub struct ReapPolicy {
    pub enabled: bool,
    pub interval_minutes: f64,
    /// A idade é a do processo, não a de órfão — o kernel não diz quando o
    /// pai morreu. Uma hora deixa de fora o que acabou de se soltar de um
    /// build.
    pub min_age_minutes: f64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReapPolicyFile {
    enabled: Option<bool>,
    interval_minutes: Option<f64>,
    min_age_minutes: Option<f64>,
}

impl From<ReapPolicyFile> for ReapPolicy {
    fn from(file: ReapPolicyFile) -> Self {
        Self {
            enabled: file.enabled.unwrap_or(true),
            interval_minutes: file.interval_minutes.unwrap_or(10.0).max(1.0),
            min_age_minutes: file.min_age_minutes.unwrap_or(60.0).max(0.0),
        }
    }
}

impl Default for ReapPolicy {
    fn default() -> Self {
        Self {
            enabled: true,
            interval_minutes: 10.0,
            min_age_minutes: 60.0,
        }
    }
}

impl ReapPolicy {
    /// O daemon do Claude Code é órfão de propósito: segura as sessões em
    /// segundo plano dele, e encerrá-lo por relógio levaria uma delas no meio.
    pub fn is_spared(command: &str) -> bool {
        command.contains("bg-pty-host")
            || command.contains("bg-spare")
            || (command.contains("claude") && command.contains(" daemon run"))
    }

    pub fn victims(&self, processes: &[EgeonProcess], now: SystemTime) -> Vec<EgeonProcess> {
        let mut children: HashMap<u32, Vec<u32>> = HashMap::new();
        for process in processes {
            children.entry(process.ppid).or_default().push(process.pid);
        }
        let mut spared = HashSet::new();
        let mut stack: Vec<u32> = processes
            .iter()
            .filter(|p| Self::is_spared(&p.command))
            .map(|p| p.pid)
            .collect();
        while let Some(pid) = stack.pop() {
            if !spared.insert(pid) {
                continue;
            }
            stack.extend(children.get(&pid).into_iter().flatten());
        }
        // A idade é a da família: o filho que um laço relança nasce de novo a
        // cada queda e nunca chegaria à idade mínima sozinho.
        let orphans: HashMap<u32, &EgeonProcess> = processes
            .iter()
            .rev()
            .filter(|p| p.orphan)
            .map(|p| (p.pid, p))
            .collect();
        let family_start = |process: &EgeonProcess| {
            let mut oldest = process.started;
            let mut current = process;
            for _ in 0..64 {
                if current.ppid <= 1 {
                    break;
                }
                let Some(parent) = orphans.get(&current.ppid) else {
                    break;
                };
                oldest = oldest.min(parent.started);
                current = parent;
            }
            oldest
        };
        let min_age = self.min_age_minutes * 60.0;
        processes
            .iter()
            .filter(|p| {
                p.orphan
                    && !spared.contains(&p.pid)
                    && seconds_between(family_start(p), now) >= min_age
            })
            .cloned()
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    const T0: u64 = 1_790_000_000;

    fn at(offset: u64) -> SystemTime {
        SystemTime::UNIX_EPOCH + Duration::from_secs(T0 + offset)
    }

    fn raw_at(pid: u32, ppid: u32, name: &str, offset: u64, env: &[(&str, &str)]) -> RawProcess {
        RawProcess {
            pid,
            ppid,
            started: at(offset),
            name: name.to_owned(),
            command: name.to_owned(),
            environment: env
                .iter()
                .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
                .collect(),
        }
    }

    fn raw(pid: u32, ppid: u32, name: &str, env: &[(&str, &str)]) -> RawProcess {
        raw_at(pid, ppid, name, 0, env)
    }

    fn pids(found: &[EgeonProcess]) -> Vec<u32> {
        let mut pids: Vec<u32> = found.iter().map(|p| p.pid).collect();
        pids.sort_unstable();
        pids
    }

    fn node_of(found: &[EgeonProcess], pid: u32) -> Option<&str> {
        found.iter().find(|p| p.pid == pid)?.node.as_deref()
    }

    const DECK: &str = "egeon";

    #[test]
    fn descendentes_do_app_sao_dele_e_herdam_o_no() {
        let all = [
            raw(1, 0, "launchd", &[]),
            raw(100, 1, "EgeonDeck", &[]),
            raw(
                101,
                100,
                "zsh",
                &[(mark::NODE, "deck/claude"), (mark::DECK, DECK)],
            ),
            // Limpou o ambiente: ainda é do nó pela árvore.
            raw(102, 101, "chrome", &[]),
            raw(103, 100, "claude", &[]),
        ];
        let found = classify(&all, 100, DECK);
        assert_eq!(pids(&found), [101, 102, 103]);
        assert!(found.iter().all(|p| !p.orphan));
        assert_eq!(node_of(&found, 102), Some("deck/claude"));
        assert_eq!(node_of(&found, 103), None);
    }

    #[test]
    fn shell_ilegivel_pega_o_no_do_filho() {
        let all = [
            raw(1, 0, "launchd", &[]),
            raw(100, 1, "EgeonDeck", &[]),
            raw(101, 100, "zsh", &[]),
            raw(
                102,
                101,
                "claude",
                &[(mark::NODE, "deck/claude"), (mark::DECK, DECK)],
            ),
        ];
        assert_eq!(
            node_of(&classify(&all, 100, DECK), 101),
            Some("deck/claude")
        );
    }

    #[test]
    fn marcado_fora_do_app_e_orfao_com_os_filhos() {
        let all = [
            raw(1, 0, "launchd", &[]),
            raw(100, 1, "EgeonDeck", &[]),
            raw_at(
                200,
                1,
                "node",
                10,
                &[(mark::NODE, "x/claude"), (mark::DECK, DECK)],
            ),
            raw_at(201, 200, "chrome", 11, &[]),
            raw(300, 1, "vim", &[]),
        ];
        let found = classify(&all, 100, DECK);
        assert_eq!(pids(&found), [200, 201]);
        assert!(found.iter().all(|p| p.orphan));
        assert_eq!(node_of(&found, 201), Some("x/claude"));
    }

    #[test]
    fn outro_flavor_e_a_arvore_dele_nao_sao_nossos() {
        let all = [
            raw(1, 0, "launchd", &[]),
            raw(100, 1, "EgeonDeck", &[]),
            // O outro app herdou a marca de quem o lançou; nem ele nem os
            // filhos dele são órfãos daqui.
            raw(
                500,
                1,
                "EgeonDeck",
                &[(mark::NODE, "deck/claude"), (mark::DECK, DECK)],
            ),
            raw(
                501,
                500,
                "zsh",
                &[(mark::NODE, "dev/a"), (mark::DECK, "egeon-dev")],
            ),
            raw(
                600,
                1,
                "node",
                &[(mark::NODE, "dev/b"), (mark::DECK, "egeon-dev")],
            ),
        ];
        assert_eq!(classify(&all, 100, DECK), []);
    }

    /// Daqui: o core novo também é "outro Egeon" para quem olha de fora, e o
    /// Swift em uso não leva os processos dele, que têm outro deck.
    #[test]
    fn core_novo_e_outro_app_e_tem_deck_proprio() {
        let all = [
            raw(1, 0, "launchd", &[]),
            raw(100, 1, "EgeonDeck", &[]),
            raw(700, 1, "egeon-app", &[]),
            raw(
                701,
                700,
                "zsh",
                &[(mark::NODE, "n/a"), (mark::DECK, "egeon-next")],
            ),
            raw(
                800,
                1,
                "node",
                &[(mark::NODE, "n/b"), (mark::DECK, "egeon-next")],
            ),
        ];
        assert_eq!(classify(&all, 100, DECK), []);
        let ours = classify(&all, 700, "egeon-next");
        assert_eq!(pids(&ours), [701, 800]);
        assert_eq!(
            ours.iter().find(|p| p.pid == 800).map(|p| p.orphan),
            Some(true)
        );
    }

    #[test]
    fn app_aberto_de_um_terminal_nao_e_orfao() {
        let docker = [
            (mark::NODE, "x/back"),
            (mark::DECK, DECK),
            (mark::BUNDLE_VARIABLE, "com.docker.docker"),
        ];
        let server = [
            (mark::NODE, "x/back"),
            (mark::DECK, DECK),
            (mark::BUNDLE_VARIABLE, "dev.duckcoder.egeondeck"),
        ];
        let all = [
            raw(1, 0, "launchd", &[]),
            raw(100, 1, "EgeonDeck", &[]),
            raw(200, 1, "com.docker.backend", &docker),
            raw(201, 200, "com.docker.build", &docker),
            raw(300, 1, "node", &server),
        ];
        assert_eq!(pids(&classify(&all, 100, DECK)), [300]);
    }

    #[test]
    fn alvo_antigo_sem_deck_ainda_conta() {
        let all = [
            raw(1, 0, "launchd", &[]),
            raw(100, 1, "EgeonDeck", &[]),
            raw(200, 1, "node", &[(mark::TARGET, "velha/claude")]),
        ];
        let found = classify(&all, 100, DECK);
        assert_eq!(
            found.iter().map(|p| p.node.as_deref()).collect::<Vec<_>>(),
            [Some("velha/claude")]
        );
        assert_eq!(found.iter().map(|p| p.orphan).collect::<Vec<_>>(), [true]);
    }

    #[test]
    fn ordem_e_idade() {
        let p = |pid, offset, node: &str, orphan| EgeonProcess {
            pid,
            ppid: 0,
            started: at(offset),
            command: String::new(),
            node: Some(node.to_owned()),
            orphan,
        };
        let list = vec![p(1, 0, "b", false), p(2, 5, "z", true), p(3, 0, "z", true)];
        assert_eq!(
            ordered(list).iter().map(|p| p.pid).collect::<Vec<_>>(),
            [3, 2, 1]
        );
        assert_eq!(age(42.0), "42 s");
        assert_eq!(age(600.0), "10 min");
        assert_eq!(age(3.0 * 3600.0 + 120.0), "3 h 2 min");
        assert_eq!(age(19.0 * 86_400.0 + 16.0 * 3600.0), "19 d 16 h");
    }

    #[test]
    fn limpeza_leva_orfao_velho_e_poupa_o_daemon_do_claude() {
        let now = at(3 * 3600);
        let p = |pid, ppid, command: &str, age_secs: u64, orphan| EgeonProcess {
            pid,
            ppid,
            started: now - Duration::from_secs(age_secs),
            command: command.to_owned(),
            node: Some("x/claude".to_owned()),
            orphan,
        };
        let list = [
            p(1, 1, "node server.js", 7200, true),
            p(2, 1, "node vite", 600, true), // novo demais
            p(
                3,
                1,
                "/Users/a/.local/bin/claude daemon run --json-path x",
                7200,
                true,
            ),
            p(4, 3, "claude bg-pty-host --bg-pty-host /tmp/s", 7200, true),
            p(5, 4, "npm exec @playwright/mcp@latest", 7200, true), // debaixo do daemon
            p(6, 99, "claude --resume abc", 7200, false),
        ];
        let victims = |policy: &ReapPolicy| -> Vec<u32> {
            policy.victims(&list, now).iter().map(|p| p.pid).collect()
        };
        assert_eq!(victims(&ReapPolicy::default()), [1]);
        let policy = ReapPolicy {
            min_age_minutes: 5.0,
            ..ReapPolicy::default()
        };
        assert_eq!(victims(&policy), [1, 2]);
    }

    #[test]
    fn arquivo_da_politica_completa_o_que_falta() {
        let policy: ReapPolicy = serde_json::from_str(r#"{"enabled":false}"#).unwrap();
        assert!(!policy.enabled);
        assert_eq!(policy.interval_minutes, 10.0);
        assert_eq!(policy.min_age_minutes, 60.0);
        let floor: ReapPolicy = serde_json::from_str(r#"{"intervalMinutes":0}"#).unwrap();
        assert_eq!(floor.interval_minutes, 1.0);
    }

    #[test]
    fn laco_que_relanca_sem_marca_legivel_e_adotado_pelos_filhos() {
        let m = [(mark::NODE, "3614/claude"), (mark::DECK, DECK)];
        let all = [
            raw(1, 0, "launchd", &[]),
            raw(100, 1, "EgeonDeck", &[]),
            // O laço: pai morto, ambiente ilegível; o filho renasce a cada queda.
            raw_at(200, 1, "bash", 0, &[]),
            raw_at(201, 200, "aws", 90_000, &m),
            raw_at(202, 201, "session-manager-plugin", 90_001, &[]),
            // App solto no launchd com filho marcado não é adotado.
            RawProcess {
                command: "/Applications/Docker.app/Contents/MacOS/Docker".to_owned(),
                ..raw(300, 1, "Docker", &[])
            },
            raw(301, 300, "helper", &m),
            // Pai sem marca que ainda tem pai vivo (um terminal seu) não é órfão.
            raw_at(
                400,
                1,
                "Terminal",
                0,
                &[(mark::BUNDLE_VARIABLE, "com.apple.Terminal")],
            ),
            raw(401, 400, "zsh", &[]),
            raw(402, 401, "node", &m),
        ];
        let found = classify(&all, 100, DECK);
        let orphans: HashSet<u32> = found.iter().filter(|p| p.orphan).map(|p| p.pid).collect();
        assert!(orphans.is_superset(&HashSet::from([200, 201, 202])));
        assert!(!orphans.contains(&300));
        assert!(!orphans.contains(&400));
        assert!(!orphans.contains(&401));
        assert_eq!(node_of(&found, 200), Some("3614/claude"));

        // A idade é a da família: o filho de 10 minutos sai com o laço de um dia.
        let now = at(90_600);
        let victims: HashSet<u32> = ReapPolicy::default()
            .victims(&found, now)
            .iter()
            .map(|p| p.pid)
            .collect();
        assert!(victims.is_superset(&HashSet::from([200, 201, 202])));
    }

    #[test]
    fn json_da_lista_como_no_swift() {
        let process = EgeonProcess {
            pid: 7,
            ppid: 1,
            started: at(0),
            command: "node x".into(),
            node: None,
            orphan: false,
        };
        assert_eq!(
            process.json(at(90)),
            json!({"pid":7,"ppid":1,"node":"app","orphan":false,"age":90,"command":"node x"})
        );
        assert_eq!(process.json(SystemTime::UNIX_EPOCH)["age"], 0);
    }
}
