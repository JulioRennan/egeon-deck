//! Até a recusa do sistema abre diálogo na tela do usuário (o LaunchServices
//! mostra "não existe aplicativo para abrir…" e "-50"), e com vários agentes
//! rodando `cargo test --workspace` isso empilhou dezenas de janelas. Só rodam
//! a pedido: `cargo test -p egeon-driver --test opener -- --ignored`.

use std::path::PathBuf;

use egeon_core::ports::opener::{OpenTarget, Opener};
use egeon_driver::SystemOpener;

#[test]
#[ignore = "abre diálogo do macOS na tela do usuário"]
fn url_sem_quem_trate_o_esquema_nao_abre() {
    let url = OpenTarget::Url("egeon-esquema-que-ninguem-trata://x".into());
    assert!(!SystemOpener.open(&url));
}

#[test]
#[ignore = "abre diálogo do macOS na tela do usuário"]
fn texto_que_nao_e_url_nao_abre() {
    assert!(!SystemOpener.open(&OpenTarget::Url("isto nao e url".into())));
}

#[test]
#[ignore = "abre diálogo do macOS na tela do usuário"]
fn arquivo_que_nao_existe_nao_abre() {
    let path = PathBuf::from("/tmp/egeon-nao-existe-e2e/nada.txt");
    assert!(!SystemOpener.open(&OpenTarget::File(path)));
}
