//! O Linux não tem app com identificador de bundle nem o `__CFBundleIdentifier`
//! que o launchd põe no processo do app que abre: sem isso não há como saber
//! que o Egeon abriu um app de desktop, e o fechamento do ADR-084 não tem o que
//! fechar. A lista de apps é vazia, e o resto só existe para o contrato.

use egeon_core::ports::procs::{RunningApp, SocketLinks};

/// O do pacote `docker.io` e o do `docker-ce`, os dois no mesmo caminho.
pub(super) const DOCKER: &str = "/usr/bin/docker";

pub(super) fn running_apps() -> Vec<RunningApp> {
    Vec::new()
}

/// Sem app na lista, ninguém chega a pedir a saída de um.
pub(super) fn request_quit(_pid: u32) {}

/// Desconhecido, que é o lado seguro do contrato: quem não sabe quem fala com
/// o app não o fecha. O `lsof` do Linux não diz o outro lado de um socket unix
/// como o do macOS diz.
pub(super) fn socket_links() -> Option<SocketLinks> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sem_apps_nada_e_fechado_e_os_sockets_sao_desconhecidos() {
        assert!(running_apps().is_empty());
        request_quit(std::process::id());
        assert_eq!(socket_links(), None);
    }
}
