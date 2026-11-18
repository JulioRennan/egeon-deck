//! Fecha o app de desktop que o Egeon abriu quando o último que o usava sai
//! (ADR-084). Abrir conta pela marca no processo do app; usar, pelo que se vê
//! na hora de fechar — conexão viva com ele e, no Docker, container de pé.
//!
//! Tudo aqui bloqueia (lê o sistema e roda ferramentas dele): o core chama de
//! fora do ator.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::time::Duration;

use serde_json::{Map, Value, json};

use super::claims::{AppClaims, Entry};
use super::containers::ContainerOwners;
use super::mark;
use super::scanner::ProcessScanner;
use crate::ports::procs::{AppDriver, ProcessDriver, RunningApp, descendants};

/// Quanto depois do pedido de saída o core confere se o app saiu
/// ([`AppKeeper::still_open`]).
pub const QUIT_WATCH: Duration = Duration::from_secs(15);

const DOCKER: &str = "com.docker.docker";

/// Um app a que o `release` pediu que saísse.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Closing {
    pub bundle: String,
    pub pid: u32,
}

#[derive(Debug, Clone)]
pub struct AppKeeper {
    claims: AppClaims,
    file: PathBuf,
}

impl AppKeeper {
    pub fn new(file: PathBuf) -> Self {
        AppKeeper {
            claims: AppClaims::load(&file),
            file,
        }
    }

    pub fn claims(&self) -> &AppClaims {
        &self.claims
    }

    /// `/apps`: o que se sabe de cada app aberto pelo Egeon.
    pub fn snapshot(&self) -> Value {
        let apps: Map<String, Value> = self
            .claims
            .apps
            .iter()
            .map(|(bundle, entry)| {
                let users: Vec<&String> = entry.users.iter().collect();
                (
                    bundle.clone(),
                    json!({"launched": entry.launched, "users": users}),
                )
            })
            .collect();
        json!({"apps": apps})
    }

    /// Chamar na remoção de verdade, depois de os nós saírem do despacho —
    /// reiniciar o agente (modelo, esforço, regras) não larga app nenhum.
    /// `live`: os nós de pé, sem os que saem. `paths`: bancada → pastas, de
    /// todas as bancadas. Devolve os apps cuja saída foi pedida, para o core
    /// conferir depois de [`QUIT_WATCH`].
    pub fn release(
        &mut self,
        leaving: &BTreeSet<String>,
        live: &BTreeSet<String>,
        paths: &BTreeMap<String, Vec<String>>,
        drivers: &Drivers<'_>,
    ) -> Vec<Closing> {
        if leaving.is_empty() {
            return Vec::new();
        }
        // O próprio Egeon (estável, dev, novo) nunca é fechado por aqui.
        let apps: Vec<RunningApp> = drivers
            .apps
            .running_apps()
            .into_iter()
            .filter(|app| !app.bundle.starts_with(mark::BUNDLE_PREFIX))
            .collect();
        let mut launchers = BTreeMap::new();
        // De qual app aberto pelo launchd cada um descende: a janela do Docker
        // Desktop é outro bundle, mas leva o `__CFBundleIdentifier` do motor —
        // é parte dele, até quando já não é filha na árvore.
        let mut job: HashMap<u32, String> = HashMap::new();
        for app in &apps {
            let Some(environment) = drivers.procs.environment_of(app.pid) else {
                continue;
            };
            if let Some(owner) = environment.get(mark::BUNDLE_VARIABLE) {
                job.insert(app.pid, owner.clone());
            }
            // Defeito do Swift que não foi portado: lá `launchers[bundle] = opener`
            // grava também o `nil`, e com duas instâncias do mesmo bundle a
            // última, sem marca, apagava a reivindicação da primeira.
            if let Some(opener) = AppClaims::opener(&app.bundle, &environment) {
                launchers.insert(app.bundle.clone(), opener);
            }
        }
        let mut closing = Vec::new();
        for bundle in self.claims.release(leaving, live, &launchers) {
            let Some(pid) = apps.iter().find(|a| a.bundle == bundle).map(|a| a.pid) else {
                continue;
            };
            let (users, reason) = still_using(&bundle, pid, live, leaving, paths, drivers);
            if !users.is_empty() || reason.is_some() {
                crate::log!(
                    "apps: {bundle} segue aberto — {}",
                    reason.unwrap_or_else(|| format!(
                        "em uso por {}",
                        users.iter().cloned().collect::<Vec<_>>().join(", ")
                    ))
                );
                self.claims.apps.insert(
                    bundle,
                    Entry {
                        launched: true,
                        users,
                    },
                );
                continue;
            }
            crate::log!(
                "apps: {bundle} fechado — {} era o último a usar",
                leaving.iter().cloned().collect::<Vec<_>>().join(", ")
            );
            let relatives: Vec<u32> = apps
                .iter()
                .filter(|a| a.pid != pid && job.get(&a.pid) == Some(&bundle))
                .map(|a| a.pid)
                .collect();
            close(pid, &relatives, &apps, drivers);
            closing.push(Closing { bundle, pid });
        }
        self.claims.save(&self.file);
        closing
    }

    /// Passado [`QUIT_WATCH`]: o app seguiu aberto? Registra no log, como o
    /// Swift.
    pub fn still_open(closing: &Closing, procs: &dyn ProcessDriver) -> bool {
        let open = procs.parent_of(closing.pid).is_some();
        if open {
            crate::log!(
                "apps: {} pedido para fechar, mas segue aberto após 15 s",
                closing.bundle
            );
        }
        open
    }

    pub fn file(&self) -> &Path {
        &self.file
    }
}

/// O que o keeper lê e aciona no sistema.
pub struct Drivers<'a> {
    pub apps: &'a dyn AppDriver,
    pub procs: &'a dyn ProcessDriver,
    pub context: &'a super::scanner::ScanContext,
}

/// O ⌘Q no app e, antes, nos apps que são parte dele — filhos na árvore ou do
/// mesmo lançamento (`relatives`). O motor do Docker ignora o pedido de saída;
/// quem obedece é a janela do Docker Desktop, e ela leva o motor.
fn close(pid: u32, relatives: &[u32], apps: &[RunningApp], drivers: &Drivers<'_>) {
    let scanner = ProcessScanner::new(drivers.procs, drivers.context);
    let tree: HashSet<u32> = descendants(pid, &scanner.tree())
        .iter()
        .map(|p| p.pid)
        .collect();
    let mut family: Vec<u32> = apps
        .iter()
        .filter(|a| tree.contains(&a.pid))
        .map(|a| a.pid)
        .chain(relatives.iter().copied())
        .collect::<BTreeSet<u32>>()
        .into_iter()
        .collect();
    family.push(pid);
    for member in family {
        drivers.apps.request_quit(member);
    }
}

/// Os nós de pé que ainda usam o app. A razão, quando existe, segura o app sem
/// herdeiro — o caso em que não se sabe de quem é o uso.
fn still_using(
    bundle: &str,
    pid: u32,
    live: &BTreeSet<String>,
    leaving: &BTreeSet<String>,
    paths: &BTreeMap<String, Vec<String>>,
    drivers: &Drivers<'_>,
) -> (BTreeSet<String>, Option<String>) {
    let mut users = connected(pid, live, drivers);
    if bundle == DOCKER {
        let Some(dirs) = drivers.apps.container_working_dirs() else {
            return (users, Some("não deu para listar os containers".into()));
        };
        // `/tmp` e `/private/tmp`: o compose grava um, a bancada pode ter o outro.
        let dirs: Vec<String> = dirs
            .iter()
            .map(|d| if d.is_empty() { d.clone() } else { real(d) })
            .collect();
        let paths: BTreeMap<String, Vec<String>> = paths
            .iter()
            .map(|(bench, dirs)| (bench.clone(), dirs.iter().map(|d| real(d)).collect()))
            .collect();
        let owners = ContainerOwners::new(&dirs, &paths);
        if owners.unknown {
            return (users, Some("há container de fora das bancadas".into()));
        }
        let bench = |address: &String| {
            // `split` do Swift: pedaço vazio não conta.
            address
                .split('/')
                .find(|p| !p.is_empty())
                .unwrap_or("")
                .to_owned()
        };
        let live_benches: BTreeSet<String> = live.iter().map(bench).collect();
        let leaving_benches: BTreeSet<String> = leaving
            .iter()
            .map(bench)
            .filter(|b| !live_benches.contains(b))
            .collect();
        users.extend(
            live.iter()
                .filter(|a| owners.benches.contains(&bench(a)))
                .cloned(),
        );
        // Bancada parada (não a que sai) com container de pé: o banco dela vai
        // estar lá quando ela voltar.
        if let Some(idle) = owners
            .benches
            .iter()
            .find(|b| !live_benches.contains(*b) && !leaving_benches.contains(*b))
        {
            return (
                users,
                Some(format!("há container da bancada {idle}, parada")),
            );
        }
    }
    (users, None)
}

/// Os nós de pé com algum processo ligado por socket ao app ou aos filhos dele
/// — o `docker compose up` de outra bancada falando com o Docker.
fn connected(app: u32, live: &BTreeSet<String>, drivers: &Drivers<'_>) -> BTreeSet<String> {
    let scanner = ProcessScanner::new(drivers.procs, drivers.context);
    let mut app_pids: HashSet<u32> = descendants(app, &scanner.tree())
        .iter()
        .map(|p| p.pid)
        .collect();
    app_pids.insert(app);
    let ours: Vec<_> = scanner
        .scan()
        .into_iter()
        .filter(|p| !p.orphan && p.node.as_ref().is_some_and(|n| live.contains(n)))
        .collect();
    if ours.is_empty() {
        return BTreeSet::new();
    }
    let Some(links) = drivers.apps.socket_links() else {
        return BTreeSet::new();
    };
    let candidates: HashSet<u32> = ours.iter().map(|p| p.pid).collect();
    let hits = links.connected(&candidates, &app_pids);
    ours.iter()
        .filter(|p| hits.contains(&p.pid))
        .filter_map(|p| p.node.clone())
        .collect()
}

/// `resolvingSymlinksInPath` do Foundation: segue os links do que existe e
/// tira o `/private` de `/tmp`, `/var` e `/etc`. O que não existe fica como
/// veio.
fn real(path: &str) -> String {
    let resolved = std::fs::canonicalize(path)
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|_| path.to_owned());
    for system in ["tmp", "var", "etc"] {
        if let Some(rest) = resolved.strip_prefix(&format!("/private/{system}"))
            && (rest.is_empty() || rest.starts_with('/'))
        {
            return format!("/{system}{rest}");
        }
    }
    resolved
}
