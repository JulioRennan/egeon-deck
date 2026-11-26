//! Como no Linux: sem o identificador de bundle que o launchd põe no processo
//! do app que abre, não há como saber que o Egeon abriu um app de desktop, e o
//! fechamento do ADR-084 não tem o que fechar.

use egeon_core::ports::procs::{RunningApp, SocketLinks};

/// Onde o Docker Desktop põe o `docker.exe`.
pub(super) const DOCKER: &str = r"C:\Program Files\Docker\Docker\resources\bin\docker.exe";

pub(super) fn running_apps() -> Vec<RunningApp> {
    Vec::new()
}

/// Sem app na lista, ninguém chega a pedir a saída de um.
pub(super) fn request_quit(_pid: u32) {}

/// Desconhecido: quem não sabe quem fala com o app não o fecha.
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
