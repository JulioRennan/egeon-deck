//! O que a janela "Processos" mostra, pronto para a UI: a lista na ordem do
//! Swift, a idade e o resumo já em texto. Porte de `ProcessesWindow.show` e
//! `restyle`. Puro: a leitura do kernel e a hora vêm de fora.

use std::collections::HashSet;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use super::model::{EgeonProcess, age, ordered};
use super::reaper::OrphanReaper;

/// Uma linha da tabela.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProcessRow {
    pub pid: u32,
    /// `None` é do próprio app, fora de terminal: a UI escreve "app", como a
    /// coluna do Swift.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub node: Option<String>,
    pub orphan: bool,
    /// `ProcessList.age`: "42 s", "10 min", "3 h 2 min", "19 d 4 h".
    pub age: String,
    pub command: String,
}

/// A janela inteira: as linhas, o texto do resumo e o que os botões precisam.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProcessesView {
    pub processes: Vec<ProcessRow>,
    /// "3 no app · 1 órfão · limpeza a cada 60 min".
    pub summary: String,
    /// Habilita o "Encerrar órfãos" (o Swift o desliga com zero).
    pub orphans: usize,
    /// A limpeza automática está ligada (o item de menu).
    pub enabled: bool,
}

/// Monta a janela. `offset_secs` é o fuso local em `now`, para a hora da
/// última limpeza.
pub fn view(
    found: Vec<EgeonProcess>,
    reaper: &OrphanReaper,
    now: SystemTime,
    offset_secs: i64,
) -> ProcessesView {
    let all = ordered(found);
    let orphans = all.iter().filter(|p| p.orphan).count();
    let processes = all
        .iter()
        .map(|p| ProcessRow {
            pid: p.pid,
            node: p.node.clone(),
            orphan: p.orphan,
            age: age(seconds_since(p.started, now)),
            command: p.command.clone(),
        })
        .collect();
    ProcessesView {
        processes,
        summary: summary(all.len() - orphans, orphans, reaper, offset_secs),
        orphans,
        enabled: reaper.policy().enabled,
    }
}

/// A pergunta antes de encerrar: o texto do `NSAlert` do Swift.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Confirm {
    pub title: String,
    pub detail: String,
}

/// O que perguntar para encerrar `pids` da lista `view`, ou todos os órfãos
/// se `pids` é `None` (`killOrphansClicked` e `killSelectedClicked`). Quem
/// escolheu uma linha só escolhe o que a lista mostra: pid que ela não tem
/// não conta. No selecionado, o aviso lembra que processo no app é de um
/// terminal aberto e pode ser o próprio agente.
pub fn confirm(view: &ProcessesView, pids: Option<&HashSet<u32>>) -> Confirm {
    let title = match pids {
        None => format!(
            "Encerrar {} processo{} órfão{}?",
            view.orphans,
            plural_s(view.orphans),
            plural_s(view.orphans)
        ),
        Some(pids) => {
            let chosen: Vec<&ProcessRow> = view
                .processes
                .iter()
                .filter(|p| pids.contains(&p.pid))
                .collect();
            let live = chosen.iter().filter(|p| !p.orphan).count();
            let extra = if live > 0 {
                format!(" {live} ainda são de terminal aberto.")
            } else {
                String::new()
            };
            format!(
                "Encerrar {} processo{}?{extra}",
                chosen.len(),
                plural_s(chosen.len())
            )
        }
    };
    Confirm {
        title,
        detail: "Recebem SIGTERM — o mesmo que fechar o terminal deles.".to_owned(),
    }
}

fn seconds_since(started: SystemTime, now: SystemTime) -> f64 {
    match now.duration_since(started) {
        Ok(d) => d.as_secs_f64(),
        Err(e) => -e.duration().as_secs_f64(),
    }
}

fn summary(owned: usize, orphans: usize, reaper: &OrphanReaper, offset_secs: i64) -> String {
    let mut text = format!("{owned} no app · {orphans} órfão{}", plural_s(orphans));
    let policy = reaper.policy();
    if !policy.enabled {
        text.push_str(" · limpeza automática desligada");
    } else if let Some((at, count)) = reaper.last() {
        text.push_str(&format!(
            " · última limpeza {}: {count} encerrado{}",
            clock(at, offset_secs),
            plural_s(count)
        ));
    } else {
        // `Int(...)` do Swift trunca.
        text.push_str(&format!(
            " · limpeza a cada {} min",
            policy.interval_minutes as i64
        ));
    }
    text
}

fn plural_s(count: usize) -> &'static str {
    if count == 1 { "" } else { "s" }
}

/// `HH:MM` local, o `timeStyle: .short` do pt-BR.
fn clock(at: SystemTime, offset_secs: i64) -> String {
    let unix = match at.duration_since(UNIX_EPOCH) {
        Ok(d) => d.as_secs() as i64,
        Err(e) => -(e.duration().as_secs() as i64),
    };
    let day = (unix + offset_secs).rem_euclid(86_400);
    format!("{:02}:{:02}", day / 3600, day % 3600 / 60)
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::time::Duration;

    use serde_json::json;

    use super::*;

    fn at(secs: u64) -> SystemTime {
        UNIX_EPOCH + Duration::from_secs(secs)
    }

    fn process(pid: u32, node: Option<&str>, orphan: bool, started: u64) -> EgeonProcess {
        EgeonProcess {
            pid,
            ppid: 1,
            started: at(started),
            command: format!("cmd {pid}"),
            node: node.map(str::to_owned),
            orphan,
        }
    }

    fn reaper(policy_json: Option<&str>) -> (OrphanReaper, tempfile::TempDir) {
        let dir = tempfile::tempdir().unwrap();
        let file: PathBuf = dir.path().join("processes.json");
        if let Some(text) = policy_json {
            std::fs::write(&file, text).unwrap();
        }
        (OrphanReaper::new(file), dir)
    }

    #[test]
    fn a_ordem_e_as_linhas_sao_as_da_janela_do_swift() {
        let (reaper, _dir) = reaper(None);
        let found = vec![
            process(10, None, false, 100),
            process(20, Some("b/x"), true, 50),
            process(30, Some("a/x"), true, 60),
        ];
        let view = view(found, &reaper, at(100 + 19 * 86_400 + 4 * 3600), 0);
        let pids: Vec<u32> = view.processes.iter().map(|p| p.pid).collect();
        // Órfãos primeiro, por nó; o do app por último.
        assert_eq!(pids, [30, 20, 10]);
        assert_eq!(view.processes[2].node, None);
        assert_eq!(view.processes[2].age, "19 d 4 h");
        assert_eq!(view.orphans, 2);
        assert!(view.enabled);
    }

    #[test]
    fn o_json_omite_o_no_do_app_e_traz_a_idade_pronta() {
        let (reaper, _dir) = reaper(None);
        let found = vec![process(1, None, false, 0), process(2, Some("a/x"), true, 0)];
        let value = serde_json::to_value(view(found, &reaper, at(600), 0)).unwrap();
        assert_eq!(
            value["processes"][0],
            json!({"pid": 2, "node": "a/x", "orphan": true, "age": "10 min", "command": "cmd 2"})
        );
        assert_eq!(
            value["processes"][1],
            json!({"pid": 1, "orphan": false, "age": "10 min", "command": "cmd 1"})
        );
        assert_eq!(value["orphans"], 1);
        assert_eq!(value["enabled"], true);
    }

    #[test]
    fn o_resumo_tem_as_tres_variantes_e_o_plural_do_swift() {
        let now = at(10_000);
        let one = || vec![process(1, None, false, 0), process(2, Some("a/x"), true, 0)];
        let three = || {
            vec![
                process(1, None, false, 0),
                process(2, Some("a/x"), true, 0),
                process(3, Some("a/x"), true, 0),
            ]
        };

        let (mut on, _d1) = reaper(Some(r#"{"enabled": true, "intervalMinutes": 30.9}"#));
        assert_eq!(
            view(one(), &on, now, 0).summary,
            "1 no app · 1 órfão · limpeza a cada 30 min"
        );
        assert_eq!(
            view(three(), &on, now, 0).summary,
            "1 no app · 2 órfãos · limpeza a cada 30 min"
        );
        assert_eq!(
            view(Vec::new(), &on, now, 0).summary,
            "0 no app · 0 órfãos · limpeza a cada 30 min"
        );

        // A última limpeza vence o intervalo, na hora local (UTC-3 aqui).
        on.record(at(14 * 3600 + 5 * 60), 1);
        assert_eq!(
            view(one(), &on, now, -3 * 3600).summary,
            "1 no app · 1 órfão · última limpeza 11:05: 1 encerrado"
        );
        on.record(at(0), 3);
        assert_eq!(
            view(one(), &on, now, 9 * 3600 + 30 * 60).summary,
            "1 no app · 1 órfão · última limpeza 09:30: 3 encerrados"
        );

        let (off, _d2) = reaper(Some(r#"{"enabled": false}"#));
        let shown = view(one(), &off, now, 0);
        assert_eq!(
            shown.summary,
            "1 no app · 1 órfão · limpeza automática desligada"
        );
        assert!(!shown.enabled);
    }

    #[test]
    fn a_confirmacao_tem_os_textos_e_os_plurais_do_alert_do_swift() {
        let (reaper, _dir) = reaper(None);
        let found = vec![
            process(1, None, false, 0),
            process(2, Some("a/x"), true, 0),
            process(3, Some("a/x"), true, 0),
        ];
        let list = view(found, &reaper, at(10), 0);
        let detail = "Recebem SIGTERM — o mesmo que fechar o terminal deles.";

        let orphans = confirm(&list, None);
        assert_eq!(orphans.title, "Encerrar 2 processos órfãos?");
        assert_eq!(orphans.detail, detail);

        let ask = |pids: &[u32]| confirm(&list, Some(&pids.iter().copied().collect())).title;
        assert_eq!(ask(&[2]), "Encerrar 1 processo?");
        assert_eq!(ask(&[2, 3]), "Encerrar 2 processos?");
        // O do app avisa que pode ser o próprio agente.
        assert_eq!(
            ask(&[1]),
            "Encerrar 1 processo? 1 ainda são de terminal aberto."
        );
        assert_eq!(
            ask(&[1, 2, 3]),
            "Encerrar 3 processos? 1 ainda são de terminal aberto."
        );
        // Pid que a lista não tem não é linha selecionada.
        assert_eq!(ask(&[2, 4242]), "Encerrar 1 processo?");

        let one = view(vec![process(9, Some("a/x"), true, 0)], &reaper, at(10), 0);
        assert_eq!(confirm(&one, None).title, "Encerrar 1 processo órfão?");
    }
}
