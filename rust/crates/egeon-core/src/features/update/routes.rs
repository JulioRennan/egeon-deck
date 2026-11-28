//! A rota `GET /update`. Casamento no Swift: `ControlSocket.swift:724`
//! (`case ("GET", _, _) where route.hasPrefix("/update")`).

use std::time::SystemTime;

use super::controller::{Effect, UpdateController};
use crate::protocol::handler::{RouteReply, RouteRequest};

/// `/update[?check=1][&feed=url, só no dev][&prompt=1][&install=1][&auto=0|1]`
/// — a atualização do app por fora, e o estado dela. A resposta é o
/// `snapshot()` puro, sem `ok`, como no Swift. Os [`Effect`]s (consulta,
/// download, aviso) são do core executar.
pub fn update(
    state: &mut UpdateController,
    req: &RouteRequest,
    _now: SystemTime,
) -> (RouteReply, Vec<Effect>) {
    let (effects, snapshot) = state.control(&req.query);
    (RouteReply::ok(snapshot), effects)
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use serde_json::json;

    use super::*;
    use crate::features::update::controller::{FEED, UpdateConfig};
    use crate::features::update::installer::UpdateInstaller;
    use crate::features::update::policy::Reason;
    use crate::features::update::release::AssetNames;
    use crate::ports::installer::{AppInstaller, InstallError, Swap, UnpackedApp};

    struct Nothing;

    impl AppInstaller for Nothing {
        fn can_install(&self, _: &std::path::Path) -> bool {
            true
        }
        fn unpack(
            &self,
            _: &std::path::Path,
            _: &std::path::Path,
        ) -> Result<UnpackedApp, InstallError> {
            Err(InstallError::NotInstallable("teste".into()))
        }
        fn stage(&self, _: &UnpackedApp, _: &std::path::Path) -> Result<(), InstallError> {
            Ok(())
        }
        fn launch_swap(&self, _: Swap<'_>) -> std::io::Result<()> {
            Ok(())
        }
    }

    fn controller(dir: &std::path::Path) -> UpdateController {
        let installer = UpdateInstaller::new(
            dir.join("Egeon Deck.app"),
            "dev.teste.egeon",
            "1.6.0",
            dir.to_owned(),
            Arc::new(Nothing),
        );
        UpdateController::new(
            Arc::new(installer),
            UpdateConfig {
                installed_version: "1.6.0".into(),
                display_name: "Egeon Deck".into(),
                is_dev: false,
                app_pid: 1,
                settings_file: dir.join("update.json"),
                swap_log: dir.join("update.log"),
                feed: FEED.into(),
                assets: AssetNames::default(),
            },
        )
    }

    fn get(target: &str) -> RouteRequest {
        let (path, query) = target.split_once('?').unwrap_or((target, ""));
        RouteRequest {
            method: "GET".into(),
            target: target.into(),
            path: path.into(),
            query: query
                .split('&')
                .filter_map(|p| p.split_once('='))
                .map(|(k, v)| (k.to_owned(), v.to_owned()))
                .collect(),
            body: Vec::new(),
            origin: None,
        }
    }

    #[test]
    fn sem_parametros_so_mostra_o_estado() {
        let dir = tempfile::tempdir().unwrap();
        let mut state = controller(dir.path());
        let (reply, effects) = update(&mut state, &get("/update"), SystemTime::now());
        assert_eq!(reply.status, 200);
        assert!(effects.is_empty());
        assert_eq!(
            reply.json,
            json!({
                "auto": false, "installed": "1.6.0", "menu": "Procurar atualizações…",
                "staged": false, "state": "idle",
            })
        );
    }

    #[test]
    fn check_pede_a_consulta_e_auto_grava_a_opcao() {
        let dir = tempfile::tempdir().unwrap();
        let mut state = controller(dir.path());
        let (reply, effects) = update(
            &mut state,
            &get("/update?auto=1&check=1"),
            SystemTime::now(),
        );
        assert_eq!(reply.json["auto"], true);
        assert_eq!(reply.json["state"], "checking");
        assert_eq!(
            effects,
            [Effect::FetchRelease {
                reason: Reason::Periodic,
                feed: FEED.into()
            }]
        );
        assert_eq!(
            std::fs::read_to_string(dir.path().join("update.json")).unwrap(),
            r#"{"auto":true}"#
        );
    }
}
