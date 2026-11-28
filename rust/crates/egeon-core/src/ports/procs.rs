//! Interface da tabela de processos do usuário e dos sinais.
//!
//! Implementada por `egeon-driver`. O que varia por plataforma é como se lê a
//! tabela (sysctl no macOS, /proc no Linux), a linha de comando e o ambiente de
//! cada processo e a morte da árvore; quem decide quais processos são do Egeon
//! (`ProcessTable.classify` do Swift) é o core, sobre o que esta interface
//! entrega.
//!
//! Tudo aqui bloqueia (lê a tabela do kernel): o core chama de fora do ator.

use std::collections::{HashMap, HashSet};
use std::io;
use std::time::SystemTime;

use thiserror::Error;

/// Um processo como o sistema o entrega, antes de saber se é nosso.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RawProcess {
    pub pid: u32,
    pub ppid: u32,
    /// Início do processo. Com o pid, identifica o processo: pid reaproveitado
    /// por outro tem outro início.
    pub started: SystemTime,
    /// O nome curto do executável (`p_comm`): é por ele que se reconhece outro
    /// Egeon Deck.
    pub name: String,
    /// A linha de comando inteira; o nome quando o sistema não a entrega.
    pub command: String,
    /// Vazio em [`ProcessDetail::Tree`] e quando o sistema não deixa ler.
    pub environment: HashMap<String, String>,
}

/// Quanto ler de cada processo.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProcessDetail {
    /// Linha de comando e ambiente: uma leitura por processo, cara.
    Full,
    /// Só pid, pai, início e nome: barata o bastante para a remoção de um nó.
    Tree,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProcessSignal {
    Terminate,
    Kill,
}

#[derive(Debug, Error)]
pub enum ProcessError {
    #[error("não consegui ler a tabela de processos: {0}")]
    Table(io::Error),
    /// O processo não existe mais.
    #[error("o processo {0} não existe mais")]
    Gone(u32),
    #[error("sinal para o processo {pid}: {source}")]
    Signal { pid: u32, source: io::Error },
}

pub trait ProcessDriver: Send + Sync {
    /// Os processos do usuário.
    fn list(&self, detail: ProcessDetail) -> Result<Vec<RawProcess>, ProcessError>;

    /// O ambiente de um processo; `None` se ele sumiu ou o sistema não deixa
    /// ler.
    fn environment_of(&self, pid: u32) -> Option<HashMap<String, String>>;

    /// O pai de um processo; `None` se ele sumiu. É o que sobe a cadeia de
    /// quem abriu a conexão até o terminal dono.
    fn parent_of(&self, pid: u32) -> Option<u32>;

    /// Manda o sinal a UM processo. Que processos matar e quando (a árvore de um
    /// nó, o SIGKILL depois do prazo) é do core: `features::processes::tree`.
    /// Manda o sinal a UM processo. Que processos matar e quando (a árvore de um
    /// nó, o SIGKILL depois do prazo) é do core: `features::processes::tree`.
    fn signal(&self, pid: u32, signal: ProcessSignal) -> Result<(), ProcessError>;
}

/// Um app de desktop aberto (macOS: o que tem identificador de bundle).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunningApp {
    pub bundle: String,
    pub pid: u32,
}

/// Os sockets locais de cada processo: o endereço do próprio socket e, se
/// conectado, o do outro lado. É como se vê que um terminal de outra bancada
/// ainda fala com um app (o `docker compose up` preso ao socket do Docker) sem
/// ele ter aberto o app.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SocketLinks {
    pub own: HashMap<u32, HashSet<String>>,
    pub peers: HashMap<u32, HashSet<String>>,
}

impl SocketLinks {
    /// Dos `candidates`, os que têm socket ligado a algum socket de `app`.
    pub fn connected(&self, candidates: &HashSet<u32>, app: &HashSet<u32>) -> HashSet<u32> {
        let theirs: HashSet<&String> = app
            .iter()
            .filter_map(|pid| self.own.get(pid))
            .flatten()
            .collect();
        candidates
            .iter()
            .copied()
            .filter(|pid| {
                self.peers
                    .get(pid)
                    .is_some_and(|peers| peers.iter().any(|peer| theirs.contains(peer)))
            })
            .collect()
    }
}

/// Apps abertos, sockets e containers: o que o `AppKeeper` olha para decidir se
/// fecha o app que o Egeon abriu (ADR-084). Tudo bloqueia — lê o sistema ou
/// roda uma ferramenta dele —, então o core chama de fora do ator.
pub trait AppDriver: Send + Sync {
    /// Os apps abertos, incluindo o próprio Egeon: filtrar o dele é do core.
    fn running_apps(&self) -> Vec<RunningApp>;

    /// O pedido de saída que o ⌘Q faria. O app pode ignorar (o motor do Docker
    /// ignora); quem confere se saiu é o core.
    fn request_quit(&self, pid: u32);

    /// `None` quando o sistema não respondeu: aí não se sabe quem fala com quem.
    fn socket_links(&self) -> Option<SocketLinks>;

    /// A pasta de onde cada container de pé foi subido (o rótulo
    /// `com.docker.compose.project.working_dir`): uma entrada por container,
    /// vazia quando ele não tem o rótulo — e essa conta, é container sem dono.
    /// `None` quando o Docker não responde: aí não se sabe o que está rodando.
    fn container_working_dirs(&self) -> Option<Vec<String>>;
}

/// Filhos, netos e assim por diante de `root`, sem a raiz.
pub fn descendants(root: u32, all: &[RawProcess]) -> Vec<RawProcess> {
    let mut children: HashMap<u32, Vec<&RawProcess>> = HashMap::new();
    for process in all.iter().filter(|p| p.pid != p.ppid) {
        children.entry(process.ppid).or_default().push(process);
    }
    let mut result = Vec::new();
    let mut seen = HashSet::from([root]);
    let mut stack: Vec<&RawProcess> = children.get(&root).cloned().unwrap_or_default();
    while let Some(process) = stack.pop() {
        if !seen.insert(process.pid) {
            continue;
        }
        result.push(process.clone());
        if let Some(next) = children.get(&process.pid) {
            stack.extend(next);
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn process(pid: u32, ppid: u32) -> RawProcess {
        RawProcess {
            pid,
            ppid,
            started: SystemTime::UNIX_EPOCH,
            name: "p".into(),
            command: "p".into(),
            environment: HashMap::new(),
        }
    }

    #[test]
    fn descendentes_atravessam_grupos_e_deixam_a_raiz_de_fora() {
        let all = [
            process(1, 0),
            process(10, 1),
            process(11, 10),
            process(12, 11),
            process(13, 12),
            process(20, 1),
        ];
        let mut pids: Vec<u32> = descendants(10, &all).iter().map(|p| p.pid).collect();
        pids.sort_unstable();
        assert_eq!(pids, [11, 12, 13]);
        // Folha: sem filhos, sem descendentes (ProcessTableTests.swift:132).
        assert!(descendants(13, &all).is_empty());
    }

    #[test]
    fn socket_ligado_ao_app_aparece_como_conectado() {
        let set = |pids: &[u32]| pids.iter().copied().collect::<HashSet<u32>>();
        let addresses = |items: &[&str]| items.iter().map(|s| s.to_string()).collect();
        let links = SocketLinks {
            own: HashMap::from([
                (10, addresses(&["0xaaa", "0xbbb"])),
                (20, addresses(&["0xccc"])),
                (30, addresses(&["0xddd"])),
            ]),
            peers: HashMap::from([(10, addresses(&["0xccc"])), (30, addresses(&["0xeee"]))]),
        };
        assert_eq!(links.connected(&set(&[10, 30]), &set(&[20])), set(&[10]));
        assert_eq!(links.connected(&set(&[30]), &set(&[20])), set(&[]));
    }

    #[test]
    fn ciclo_de_ppid_nao_prende_a_busca() {
        let all = [process(10, 1), process(11, 12), process(12, 11)];
        assert!(descendants(10, &all).is_empty());
        let all = [process(10, 11), process(11, 10)];
        assert_eq!(descendants(10, &all).len(), 1);
    }
}
