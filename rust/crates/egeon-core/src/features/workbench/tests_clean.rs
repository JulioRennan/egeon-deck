//! Porte do WorkbenchCleanerTests, WorkbenchRemovalTests, WorkbenchClockTests e
//! FolderAccessTests.

use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{Duration, SystemTime};

use super::access::FolderAccess;
use super::cleaner::*;
use super::clock::*;
use super::removal::{RemovalTarget, purge};
use crate::features::activity::model::{Activity, ActivitySummary};
use crate::features::worktree::model::Failure;
use crate::ports::folder_access::FolderPermissions;

fn at(seconds: f64) -> SystemTime {
    SystemTime::UNIX_EPOCH + Duration::from_secs_f64(1_787_679_000.0 + seconds)
}

// ── WorkbenchCleanerTests ──────────────────────────────────────────────────

fn agent(id: &str, clear: Option<&str>) -> CleanAgent {
    CleanAgent {
        id: id.into(),
        address: format!("deck/{id}"),
        command: clear.map(str::to_owned),
    }
}

#[derive(Default)]
struct Fake {
    busy: BTreeSet<String>,
    refuse: BTreeSet<String>,
    archives: u32,
    archived: Archived,
    phases: Vec<Phase>,
    finished: Option<CleanResult>,
    dispatched: Vec<String>,
}

impl CleanerHost for Fake {
    fn dispatch(&mut self, agent: &CleanAgent) -> bool {
        self.dispatched.push(agent.id.clone());
        !self.refuse.contains(&agent.id)
    }
    fn is_busy(&mut self, agent: &CleanAgent) -> bool {
        self.busy.contains(&agent.id)
    }
    fn archive(&mut self) -> Archived {
        self.archives += 1;
        self.archived.clone()
    }
    fn on_phase(&mut self, phase: Phase) {
        self.phases.push(phase);
    }
    fn on_finish(&mut self, result: CleanResult) {
        self.finished = Some(result);
    }
}

fn secs(n: u64) -> Duration {
    Duration::from_secs(n)
}

#[test]
fn so_arquiva_depois_que_os_agentes_assentam() {
    let mut host = Fake {
        busy: ["front".to_owned()].into(),
        archived: Archived {
            chat: Some(PathBuf::from("/tmp/chat.jsonl")),
            trace: None,
        },
        ..Fake::default()
    };
    let mut cleaner = WorkbenchCleaner::new(
        vec![
            agent("front", Some("/clear")),
            agent("revisor", Some("/clear")),
        ],
        secs(2),
        secs(45),
    );

    cleaner.start(at(0.0), &mut host);
    assert_eq!(host.archives, 0, "arquivou no disparo — é o bug");

    // Dentro da folga ninguém conta como assentado: o texto acabou de ser colado
    // e o gancho de início de turno ainda não chegou.
    host.busy.clear();
    cleaner.tick(at(1.0), &mut host);
    assert_eq!(
        host.archives, 0,
        "arquivou antes de a injeção sequer chegar à TUI"
    );

    host.busy.insert("front".into());
    cleaner.tick(at(5.0), &mut host);
    assert_eq!(
        host.archives, 0,
        "um agente ainda trabalhando e já arquivou"
    );
    assert_eq!(cleaner.phase(), Phase::Clearing { remaining: 1 });

    host.busy.clear();
    cleaner.tick(at(6.0), &mut host);
    assert_eq!(host.archives, 1);
    assert_eq!(cleaner.phase(), Phase::Done);
    let finished = host.finished.unwrap();
    assert_eq!(finished.cleared, ["front", "revisor"]);
    assert!(!finished.timed_out);
    assert!(finished.chat.is_some());
}

#[test]
fn agente_atolado_nao_prende_a_limpeza_para_sempre() {
    let mut host = Fake {
        busy: ["front".to_owned()].into(),
        ..Fake::default()
    };
    let mut cleaner =
        WorkbenchCleaner::new(vec![agent("front", Some("/clear"))], secs(2), secs(30));
    cleaner.start(at(0.0), &mut host);
    cleaner.tick(at(29.0), &mut host);
    assert_eq!(host.archives, 0);
    cleaner.tick(at(31.0), &mut host);
    assert_eq!(
        host.archives, 1,
        "o teto existe para o loading não ficar eterno"
    );
    assert!(host.finished.unwrap().timed_out);
}

/// CLI sem `clear` declarado é pulado — e não pode segurar a espera, senão
/// bancada só de shell ficava com a cortina até o teto.
#[test]
fn agentes_sem_clear_sao_pulados_e_nao_atrasam_o_arquivamento() {
    let mut host = Fake {
        busy: ["shell".to_owned(), "outro".to_owned()].into(),
        archived: Archived {
            chat: None,
            trace: Some(PathBuf::from("/tmp/trace.md")),
        },
        ..Fake::default()
    };
    let mut cleaner = WorkbenchCleaner::new(
        vec![agent("shell", None), agent("outro", Some(""))],
        secs(2),
        secs(30),
    );
    cleaner.start(at(0.0), &mut host);
    assert_eq!(host.archives, 1);
    assert!(host.dispatched.is_empty(), "nada a despachar");
    let finished = host.finished.unwrap();
    assert_eq!(finished.skipped, ["shell", "outro"]);
    assert!(finished.cleared.is_empty());
    assert_eq!(host.phases.last(), Some(&Phase::Done));
    assert!(
        host.phases.contains(&Phase::Archiving),
        "a cortina precisa dizer que está arquivando"
    );
}

/// Quem parou pedindo permissão depende de VOCÊ: a fila dele não anda com a
/// caixa na tela, e esperar era ficar com a cortina de pé até o teto — visto no
/// DEV, 45 s por um agente que só queria um "sim".
#[test]
fn agente_pedindo_permissao_nao_e_esperado() {
    assert!(!is_busy(&Activity::Asking, 1));
    assert!(is_busy(&Activity::Working, 0));
    assert!(is_busy(&Activity::Starting, 0));
    assert!(
        is_busy(&Activity::Waiting, 1),
        "o `clear` ainda na fila é trabalho por fazer"
    );
    assert!(!is_busy(&Activity::Waiting, 0));
    assert!(!is_busy(&Activity::Ready, 0));
}

/// Agente que não está mais no Dispatcher (terminal fechado) entra em pulados
/// pelo próprio `dispatch`, e a limpeza segue.
#[test]
fn falha_no_despacho_conta_como_pulado() {
    let mut host = Fake {
        refuse: ["sumido".to_owned()].into(),
        ..Fake::default()
    };
    let mut cleaner = WorkbenchCleaner::new(
        vec![
            agent("front", Some("/clear")),
            agent("sumido", Some("/clear")),
        ],
        secs(0),
        secs(30),
    );
    cleaner.start(at(0.0), &mut host);
    cleaner.tick(at(1.0), &mut host);
    let finished = host.finished.unwrap();
    assert_eq!(finished.cleared, ["front"]);
    assert_eq!(finished.skipped, ["sumido"]);
}

#[test]
fn o_loading_diz_onde_a_limpeza_esta() {
    assert_eq!(
        Phase::Clearing { remaining: 1 }.label().as_deref(),
        Some("Limpando 1 agente…")
    );
    assert_eq!(
        Phase::Clearing { remaining: 3 }.label().as_deref(),
        Some("Limpando 3 agentes…")
    );
    assert_eq!(
        Phase::Clearing { remaining: 0 }.label().as_deref(),
        Some("Limpando os agentes…")
    );
    assert_eq!(
        Phase::Archiving.label().as_deref(),
        Some("Arquivando o chat e a trilha…")
    );
    assert_eq!(Phase::Done.label(), None);
}

#[test]
fn a_resposta_da_rota_tem_as_chaves_de_sempre() {
    let result = CleanResult {
        cleared: vec!["a".into()],
        skipped: vec![],
        chat: Some(PathBuf::from("/c.jsonl")),
        trace: None,
        timed_out: true,
    };
    assert_eq!(
        result.payload(),
        serde_json::json!({"ok": true, "cleared": ["a"], "skipped": [], "archived": "/c.jsonl",
                           "trace": null, "timeout": true})
    );
    // Tick sem ter começado, ou já pronta, não faz nada.
    let mut host = Fake::default();
    let mut cleaner = WorkbenchCleaner::with_defaults(vec![]);
    cleaner.tick(at(0.0), &mut host);
    assert_eq!(host.archives, 0);
}

// ── WorkbenchRemovalTests ──────────────────────────────────────────────────

fn targets(paths: &[&str]) -> Vec<RemovalTarget> {
    paths
        .iter()
        .map(|p| RemovalTarget {
            path: (*p).to_owned(),
            label: format!("repo · {p}"),
        })
        .collect()
}

fn paths(list: &[RemovalTarget]) -> Vec<&str> {
    list.iter().map(|t| t.path.as_str()).collect()
}

#[test]
fn tudo_removido_tem_sucesso() {
    let called = RefCell::new(Vec::new());
    let outcome = purge(&targets(&["/a", "/b"]), |p| {
        called.borrow_mut().push(p.to_owned());
        Ok(())
    });
    assert!(outcome.succeeded());
    assert_eq!(*called.borrow(), ["/a", "/b"]);
    assert_eq!(paths(&outcome.removed), ["/a", "/b"]);
    assert!(outcome.leftovers.is_empty());
}

/// Sobra de pasta não segura a bancada: o registro já foi, a faxina vem depois.
#[test]
fn sobras_contam_como_removidas_e_vao_para_a_faxina() {
    let outcome = purge(&targets(&["/a"]), |path| {
        Err(Failure::Leftovers {
            path: path.to_owned(),
            reason: "Directory not empty".into(),
        })
    });
    assert!(outcome.succeeded());
    assert_eq!(paths(&outcome.removed), ["/a"]);
    assert_eq!(outcome.leftovers, ["/a"]);
}

/// Uma falha não para as outras: o alerta diz o que já foi e o que resistiu.
#[test]
fn falha_segue_adiante_e_e_relatada() {
    let outcome = purge(&targets(&["/a", "/b", "/c"]), |path| {
        if path == "/b" {
            Err(Failure::Git {
                command: "worktree remove".into(),
                output: "boom".into(),
            })
        } else {
            Ok(())
        }
    });
    assert!(!outcome.succeeded());
    assert_eq!(paths(&outcome.removed), ["/a", "/c"]);
    assert_eq!(
        outcome
            .failures
            .iter()
            .map(|(t, _)| t.path.as_str())
            .collect::<Vec<_>>(),
        ["/b"]
    );
}

#[test]
fn nada_a_remover_tem_sucesso() {
    assert!(purge(&[], |_| panic!("não devia chamar")).succeeded());
}

// ── WorkbenchClockTests ────────────────────────────────────────────────────

fn summary(f: impl FnOnce(&mut ActivitySummary)) -> ActivitySummary {
    let mut s = ActivitySummary::default();
    f(&mut s);
    s
}

fn phases(s: ActivitySummary) -> Vec<ClockPhase> {
    WorkbenchClock::phases(&s).into_iter().collect()
}

use ClockPhase::{Failed, Running, Waiting};

#[test]
fn as_fases_andam_juntas() {
    assert_eq!(phases(ActivitySummary::default()), []);
    assert_eq!(
        phases(summary(|s| {
            s.starting = 2;
            s.done = 1;
        })),
        []
    );
    assert_eq!(phases(summary(|s| s.working = 1)), [Running]);
    // Aguardar vizinho é `background`: trabalho, não espera por você.
    assert_eq!(phases(summary(|s| s.background = 1)), [Running]);
    assert_eq!(phases(summary(|s| s.attention = 1)), [Waiting]);
    // Um perguntando não para o relógio de quem trabalha ao lado (ADR-078).
    assert_eq!(
        phases(summary(|s| {
            s.working = 3;
            s.attention = 1;
        })),
        [Running, Waiting]
    );
}

#[test]
fn falha_nao_e_espera_nem_trabalho() {
    // Desistido conta em `attention`, mas é erro, não pergunta.
    assert_eq!(
        phases(summary(|s| {
            s.attention = 1;
            s.failed = 1;
        })),
        [Failed]
    );
    assert_eq!(
        phases(summary(|s| {
            s.working = 1;
            s.attention = 2;
            s.failed = 1;
        })),
        [Running, Waiting, Failed]
    );
    // Tentativa agendada conta em `background`, mas é erro, não trabalho.
    assert_eq!(
        phases(summary(|s| {
            s.background = 1;
            s.failed = 1;
            s.retrying = 1;
        })),
        [Failed]
    );
}

#[test]
fn somar_limita_os_buracos_longos() {
    let mut clock = WorkbenchClock::default();
    clock.add(0.5, Running);
    clock.add(600.0, Running);
    clock.add(-3.0, Waiting);
    assert_eq!(clock.running, 0.5 + WorkbenchClock::MAX_STEP);
    assert_eq!(clock.waiting, 0.0);
    assert_eq!(clock.get(Running), clock.running);
}

#[test]
fn formato_de_relogio() {
    assert_eq!(WorkbenchClock::format(0.0), "00:00");
    assert_eq!(WorkbenchClock::format(59.9), "00:59");
    assert_eq!(WorkbenchClock::format(61.0), "01:01");
    assert_eq!(WorkbenchClock::format(3599.0), "59:59");
    assert_eq!(
        WorkbenchClock::format(3600.0 + 5.0 * 60.0 + 12.0),
        "1:05:12"
    );
    assert_eq!(WorkbenchClock::format(-5.0), "00:00");
}

fn map(entries: &[(&str, &[ClockPhase])]) -> BTreeMap<String, BTreeSet<ClockPhase>> {
    entries
        .iter()
        .map(|(id, p)| ((*id).to_owned(), p.iter().copied().collect()))
        .collect()
}

fn near(a: f64, b: f64) {
    assert!((a - b).abs() < 0.001, "{a} ≠ {b}");
}

#[test]
fn o_tique_soma_grava_e_zera() {
    let dir = tempfile::tempdir().unwrap();
    let mut clocks = WorkbenchClocks::new(dir.path().to_path_buf());
    // Valores exatos em ponto flutuante: o arquivo guarda segundos desde 2001.
    let start = SystemTime::UNIX_EPOCH + Duration::from_secs(1_790_000_000);
    let plus = |s: f64| start + Duration::from_secs_f64(s);

    clocks.tick(&map(&[("a", &[Running])]), start).unwrap(); // o primeiro tique só marca
    clocks
        .tick(&map(&[("a", &[Running]), ("b", &[Failed])]), plus(1.0))
        .unwrap();
    clocks
        .tick(&map(&[("a", &[Running, Waiting])]), plus(1.5))
        .unwrap();
    clocks.tick(&map(&[("a", &[])]), plus(3.0)).unwrap();
    near(clocks.clock("a").running, 1.5);
    near(clocks.clock("a").waiting, 0.5);
    near(clocks.clock("b").failed, 1.0);
    // O último instante com fase andando — o tique vazio não conta.
    assert_eq!(clocks.clock("a").last_active, Some(plus(1.5)));
    assert_eq!(clocks.clock("b").last_active, Some(plus(1.0)));

    clocks.flush(plus(3.0)).unwrap();
    let mut reloaded = WorkbenchClocks::new(dir.path().to_path_buf());
    assert_eq!(reloaded.clock("a"), clocks.clock("a"));

    clocks.reset("a", plus(4.0)).unwrap();
    // Zerar começa outro período, mas não apaga quando ela rodou.
    let mut again = WorkbenchClocks::new(dir.path().to_path_buf());
    assert_eq!(
        again.clock("a"),
        WorkbenchClock {
            last_active: Some(plus(1.5)),
            ..WorkbenchClock::default()
        }
    );
}

#[test]
fn grava_a_cada_quinze_segundos_e_nao_a_cada_tique() {
    let dir = tempfile::tempdir().unwrap();
    let mut clocks = WorkbenchClocks::new(dir.path().to_path_buf());
    let start = SystemTime::UNIX_EPOCH + Duration::from_secs(1_790_000_000);
    let file = clocks.file("a");
    clocks.tick(&map(&[("a", &[Running])]), start).unwrap();
    clocks
        .tick(&map(&[("a", &[Running])]), start + secs(1))
        .unwrap();
    assert!(!file.exists(), "um segundo depois ainda não gravou");
    clocks
        .tick(&map(&[("a", &[Running])]), start + secs(16))
        .unwrap();
    assert!(file.exists());
}

/// O arquivo guarda o `lastActive` como o `Date` do Swift: segundos desde 2001.
#[test]
fn a_data_e_gravada_como_o_date_do_swift() {
    let when = SystemTime::UNIX_EPOCH + Duration::from_secs(1_790_000_000);
    let text = serde_json::to_value(WorkbenchClock {
        last_active: Some(when),
        ..Default::default()
    })
    .unwrap();
    assert_eq!(text["lastActive"], 1_790_000_000.0 - 978_307_200.0);
    assert_eq!(text["running"], 0.0);
    let no_date = serde_json::to_value(WorkbenchClock::default()).unwrap();
    assert!(no_date.get("lastActive").is_none());
}

// Arquivo de antes do `lastActive`: a data dele é a última vez que rodou.
#[test]
fn arquivo_antigo_tira_o_last_active_da_data_de_modificacao() {
    let dir = tempfile::tempdir().unwrap();
    let mut clocks = WorkbenchClocks::new(dir.path().to_path_buf());
    let file = clocks.file("a");
    std::fs::create_dir_all(file.parent().unwrap()).unwrap();
    std::fs::write(&file, br#"{"running":10,"waiting":0,"failed":0}"#).unwrap();
    let when = SystemTime::UNIX_EPOCH + Duration::from_secs(1_790_000_000);
    std::fs::File::options()
        .write(true)
        .open(&file)
        .unwrap()
        .set_modified(when)
        .unwrap();
    assert_eq!(clocks.clock("a").last_active, Some(when));
    assert_eq!(clocks.clock("a").running, 10.0);
    // Arquivo ausente ou quebrado é cronômetro zerado.
    assert_eq!(clocks.clock("b").running, 0.0);
    std::fs::create_dir_all(clocks.file("c").parent().unwrap()).unwrap();
    std::fs::write(clocks.file("c"), "{quebrado").unwrap();
    assert_eq!(clocks.clock("c").running, 0.0);
}

// ── FolderAccessTests ──────────────────────────────────────────────────────

struct Reset {
    asked: Mutex<Vec<String>>,
    works: bool,
}

impl FolderPermissions for Reset {
    fn reset(&self, service: &str) -> bool {
        self.asked.lock().unwrap().push(service.to_owned());
        self.works
    }

    fn settings_url(&self) -> Option<String> {
        None
    }
}

#[cfg(unix)]
#[test]
fn pasta_legivel_ausente_e_bloqueada() {
    if crate::commons::testing::running_as_root() {
        return;
    }
    use std::os::unix::fs::PermissionsExt;
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().to_str().unwrap().to_owned();
    assert_eq!(FolderAccess::check(&root, "/Users/x"), FolderAccess::Ok);
    assert_eq!(
        FolderAccess::check(&format!("{root}/nada"), "/Users/x"),
        FolderAccess::Missing
    );
    // Um arquivo no lugar da pasta também é "não há pasta".
    std::fs::write(dir.path().join("arquivo"), b"").unwrap();
    assert_eq!(
        FolderAccess::check(&format!("{root}/arquivo"), "/Users/x"),
        FolderAccess::Missing
    );

    std::fs::set_permissions(dir.path(), std::fs::Permissions::from_mode(0o000)).unwrap();
    let blocked = FolderAccess::check(&root, "/Users/x");
    std::fs::set_permissions(dir.path(), std::fs::Permissions::from_mode(0o755)).unwrap();
    assert_eq!(blocked, FolderAccess::Denied { folder: None });
    assert!(blocked.message().is_some());
}

#[test]
fn nomeia_a_pasta_protegida_como_o_ajustes_mostra() {
    let name = |p: &str| FolderAccess::protected_folder(p, "/Users/x");
    assert_eq!(
        name("/Users/x/Documents/proj").as_deref(),
        Some("Documentos")
    );
    assert_eq!(name("/Users/x/Desktop").as_deref(), Some("Mesa"));
    assert_eq!(
        name("/Users/x/Downloads/a/b").as_deref(),
        Some("Transferências")
    );
    assert_eq!(name("/Users/x/Documentsish/a"), None);
    assert_eq!(name("/Users/x/code"), None);
    assert_eq!(
        name("/Users/x/code/../Documents/a").as_deref(),
        Some("Documentos"),
        "`..` resolve pelo texto"
    );
    let message = FolderAccess::Denied {
        folder: Some("Documentos".into()),
    }
    .message()
    .unwrap();
    assert!(message.contains("a pasta Documentos"));
    assert!(message.contains("Ajustes › Privacidade › Arquivos e Pastas"));
    assert_eq!(FolderAccess::Ok.message(), None);
    assert_eq!(FolderAccess::Missing.message(), None);
    assert!(
        FolderAccess::Denied { folder: None }
            .message()
            .unwrap()
            .contains("esta pasta")
    );
}

// O pedido de novo zera a decisão do serviço certo, e só das três pastas.
#[test]
fn o_servico_de_cada_pasta_protegida() {
    assert_eq!(
        FolderAccess::service("Documentos"),
        Some("SystemPolicyDocumentsFolder")
    );
    assert_eq!(
        FolderAccess::service("Mesa"),
        Some("SystemPolicyDesktopFolder")
    );
    assert_eq!(
        FolderAccess::service("Transferências"),
        Some("SystemPolicyDownloadsFolder")
    );
    assert_eq!(FolderAccess::service("Outra"), None);
}

// Fora de um .app não há o que zerar: devolve a conferência.
#[test]
fn pedir_sem_o_que_zerar_e_so_a_conferencia() {
    let dir = tempfile::tempdir().unwrap();
    let reset = Reset {
        asked: Mutex::new(vec![]),
        works: false,
    };
    assert_eq!(
        FolderAccess::request(dir.path().to_str().unwrap(), "/Users/x", &reset),
        FolderAccess::Ok
    );
    assert!(
        reset.asked.lock().unwrap().is_empty(),
        "pasta que lê não pede nada ao sistema"
    );
}

#[cfg(unix)]
#[test]
fn pasta_protegida_negada_zera_o_servico_e_confere_de_novo() {
    if crate::commons::testing::running_as_root() {
        return;
    }
    use std::os::unix::fs::PermissionsExt;
    let home = tempfile::tempdir().unwrap();
    let docs = home.path().join("Documents");
    std::fs::create_dir_all(&docs).unwrap();
    std::fs::set_permissions(&docs, std::fs::Permissions::from_mode(0o000)).unwrap();
    let home_s = home.path().to_str().unwrap();
    let docs_s = docs.to_str().unwrap();

    let works = Reset {
        asked: Mutex::new(vec![]),
        works: true,
    };
    let broken = Reset {
        asked: Mutex::new(vec![]),
        works: false,
    };
    let after_reset = FolderAccess::request(docs_s, home_s, &works);
    let without = FolderAccess::request(docs_s, home_s, &broken);
    std::fs::set_permissions(&docs, std::fs::Permissions::from_mode(0o755)).unwrap();

    assert_eq!(
        *works.asked.lock().unwrap(),
        ["SystemPolicyDocumentsFolder"]
    );
    assert_eq!(
        *broken.asked.lock().unwrap(),
        ["SystemPolicyDocumentsFolder"]
    );
    // Nos dois casos a pasta continua trancada aqui: a conferência é refeita.
    assert_eq!(
        after_reset,
        FolderAccess::Denied {
            folder: Some("Documentos".into())
        }
    );
    assert_eq!(
        without,
        FolderAccess::Denied {
            folder: Some("Documentos".into())
        }
    );
}
