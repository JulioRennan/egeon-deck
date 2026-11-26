//! Notificação e som. O executável de teste não está num app empacotado (um
//! `.app` no macOS; um AppImage ou o `.deb` no Linux), que é justamente o caso
//! em que a central não existe.

use egeon_core::ports::notifier::{Notice, Notifier, SoundError};
use egeon_driver::SystemNotifier;

fn notice() -> Notice {
    Notice {
        identifier: "egeon.teste/terminal".into(),
        title: "A bancada teste precisa de você".into(),
        body: "rodar um comando".into(),
        workbench: "teste".into(),
        node: "terminal".into(),
    }
}

#[test]
fn fora_de_um_app_nao_avisa_nem_derruba_o_processo() {
    let notifier = SystemNotifier::new();
    let mut clicks = notifier.start();
    assert!(!notifier.authorized());
    notifier.post(notice());
    notifier.withdraw("egeon.teste/terminal");
    assert!(!notifier.authorized());
    // Sem central ninguém vai entregar clique: o canal já nasce fechado.
    assert!(clicks.try_recv().is_err());
}

#[test]
fn som_que_nao_existe_e_erro_de_nome() {
    let notifier = SystemNotifier::new();
    assert_eq!(
        notifier.play_sound("SomQueNaoExisteNoSistema", 0.5),
        Err(SoundError::Unknown("SomQueNaoExisteNoSistema".into()))
    );
}

#[test]
fn nome_vazio_ou_volume_zero_nao_tocam_e_nao_sao_erro() {
    let notifier = SystemNotifier::new();
    assert_eq!(notifier.play_sound("", 0.5), Ok(()));
    // Nem o nome inexistente é consultado quando o volume é zero.
    assert_eq!(notifier.play_sound("SomQueNaoExisteNoSistema", 0.0), Ok(()));
}

#[test]
#[ignore = "toca som no computador do usuário; rodar com --ignored"]
fn som_do_sistema_toca_e_reinicia_se_ja_estava_tocando() {
    let notifier = SystemNotifier::new();
    // Volume mínimo: o teste confere que a chamada não derruba, não o ouvido.
    assert_eq!(notifier.play_sound("Tink", 0.02), Ok(()));
    assert_eq!(notifier.play_sound("Tink", 0.02), Ok(()));
}
