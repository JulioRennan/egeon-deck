//! Quem usa cada app de desktop que o Egeon abriu (ADR-084), por bundle id.
//!
//! Só app que o Egeon ABRIU é fechado: o que já estava aberto é seu, e um
//! `open` de agente nele só o traz para a frente — o processo não muda, e a
//! marca não chega. Dividido entre bancadas, quem fecha é o último a sair:
//! quem abriu entra pela marca; quem ainda usava quando ele saiu (conexão
//! viva, container) fica registrado aqui como herdeiro. Em `apps.json`, porque
//! o app fica de pé entre reinícios do Egeon.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::Path;

use serde::{Deserialize, Serialize};

use super::mark;
use crate::features::json_file::{parse, read_bytes, write_pretty};

pub const FILE: &str = "apps.json";

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Entry {
    /// Aberto por um terminal do Egeon.
    pub launched: bool,
    pub users: BTreeSet<String>,
}

// As chaves são obrigatórias, como no `Codable` sintetizado do Swift: arquivo
// que não as tem abre vazio.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppClaims {
    pub apps: BTreeMap<String, Entry>,
}

impl AppClaims {
    /// Os apps a fechar quando `leaving` sai, e os usos deles esquecidos.
    ///
    /// `launchers` é quem a marca no processo do app aponta (bundle → nó): o
    /// app aberto antes do registro, ou por outra via, ainda é de quem o abriu.
    /// `live` são os nós de pé depois da saída; uso de nó morto não segura
    /// app. O resultado vem em ordem.
    pub fn release(
        &mut self,
        leaving: &BTreeSet<String>,
        live: &BTreeSet<String>,
        launchers: &BTreeMap<String, String>,
    ) -> Vec<String> {
        let bundles: BTreeSet<String> = self.apps.keys().chain(launchers.keys()).cloned().collect();
        let mut close = Vec::new();
        for bundle in bundles {
            let mut entry = self.apps.get(&bundle).cloned().unwrap_or_default();
            if let Some(launcher) = launchers.get(&bundle) {
                entry.launched = true;
                entry.users.insert(launcher.clone());
            }
            if entry.users.is_disjoint(leaving) {
                continue;
            }
            entry.users = entry
                .users
                .difference(leaving)
                .filter(|user| live.contains(*user))
                .cloned()
                .collect();
            if entry.users.is_empty() {
                self.apps.remove(&bundle);
                if entry.launched {
                    close.push(bundle);
                }
            } else {
                self.apps.insert(bundle, entry);
            }
        }
        close
    }

    /// O nó que abriu o app, pelo ambiente do processo dele. Só vale para quem
    /// o launchd abriu como ESTE app: a janela do Docker Desktop é outro
    /// bundle, aberto pelo motor, e carrega a marca herdada — fechá-la derruba
    /// o Docker.
    pub fn opener(bundle: &str, environment: &HashMap<String, String>) -> Option<String> {
        if environment.get(mark::BUNDLE_VARIABLE).map(String::as_str) != Some(bundle) {
            return None;
        }
        mark::node_in(environment).map(str::to_owned)
    }

    /// Arquivo ausente ou ilegível é o vazio.
    pub fn load(path: &Path) -> AppClaims {
        read_bytes(path)
            .and_then(|bytes| parse(&bytes).ok())
            .unwrap_or_default()
    }

    pub fn save(&self, path: &Path) {
        if let Err(error) = write_pretty(path, self) {
            crate::log!("apps: não gravei {} — {error}", path.display());
        }
    }
}
