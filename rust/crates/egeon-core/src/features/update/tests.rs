//! Porte de `AppUpdateTests.swift`. O que depende do sistema (descompactar com
//! `ditto`, `codesign`, o script de troca) é do driver e fica atrás de um
//! `AppInstaller` de mentira: nenhum teste instala nem troca app nenhum.

use std::collections::HashMap;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use ed25519_dalek::{Signer, SigningKey, VerifyingKey};
use serde_json::json;

use super::controller::{CHECK_EVERY, FEED, FIRST_CHECK_AFTER, cannot_install_hint};
use super::release::{AssetNames, NEXT_BUNDLE_ID};
use super::*;
use crate::ports::installer::{AppInstaller, InstallError, Swap, UnpackedApp};

// ---- AppUpdateTests: versão, release, política, aviso, chave

fn v(text: &str) -> AppVersion {
    AppVersion::parse(text).unwrap()
}

#[test]
fn versoes_comparam_como_numeros() {
    assert!(v("v1.10.0") > v("1.9.2"));
    assert_eq!(v("1.6"), v("v1.6.0"));
    assert!(v("1.6.0") < v("1.6.1"));
    assert!(AppVersion::parse("1.6.0-beta").is_none());
    assert!(AppVersion::parse("nightly").is_none());
    assert!(AppVersion::parse("1..2").is_none());
    assert!(AppVersion::parse("").is_none());
}

fn release(tag: &str, assets: &[&str]) -> Vec<u8> {
    let assets: Vec<_> = assets
        .iter()
        .map(|n| json!({"name": n, "browser_download_url": format!("https://example.com/{n}")}))
        .collect();
    serde_json::to_vec(&json!({
        "tag_name": tag, "html_url": "https://example.com/r", "body": "novidades", "assets": assets,
    }))
    .unwrap()
}

const BOTH: [&str; 2] = ["EgeonDeck.zip", "EgeonDeck.zip.sig"];

/// Os testes publicam com os nomes do Swift; o padrão do app novo é outro.
fn names() -> AssetNames {
    AssetNames::legacy()
}

#[test]
fn os_nomes_dos_assets_sao_parametro_e_o_padrao_e_o_desta_plataforma() {
    let of = |os, arch| {
        let n = AssetNames::for_platform(os, arch);
        (n.zip, n.signature)
    };
    let pair = |zip: &str| (zip.to_owned(), format!("{zip}.sig"));
    assert_eq!(of("macos", "aarch64"), pair("EgeonDeck-macos-arm64.zip"));
    assert_eq!(of("macos", "x86_64"), pair("EgeonDeck-macos-arm64.zip"));
    assert_eq!(
        of("linux", "x86_64"),
        pair("EgeonDeck-linux-x86_64.AppImage")
    );
    assert_eq!(
        of("linux", "aarch64"),
        pair("EgeonDeck-linux-aarch64.AppImage")
    );
    assert_eq!(
        of("windows", "x86_64"),
        pair("EgeonDeck-windows-x86_64.zip")
    );
    assert_eq!(
        AssetNames::default(),
        AssetNames::for_platform(std::env::consts::OS, std::env::consts::ARCH)
    );
    // Sem arquivo publicado para a plataforma, nenhuma release serve.
    let riscv = AssetNames::for_platform("linux", "riscv64");
    let published = release("v1.7.0", &["EgeonDeck-linux-x86_64.AppImage"]);
    assert_eq!(AvailableUpdate::parse(&published, &riscv), None);
    let next = AssetNames::default();
    assert_eq!(NEXT_BUNDLE_ID, "dev.duckcoder.egeondeck.next");
    // O zip do app antigo não serve ao novo, e vice-versa.
    let old = release("v1.7.0", &BOTH);
    assert!(AvailableUpdate::parse(&old, &next).is_none());
    let new = release("v1.7.0", &[next.zip.as_str(), next.signature.as_str()]);
    assert!(AvailableUpdate::parse(&new, &next).is_some());
    assert!(AvailableUpdate::parse(&new, &names()).is_none());
}

#[test]
fn leitura_da_release() {
    let update = AvailableUpdate::parse(&release("v1.7.0", &BOTH), &names()).unwrap();
    assert_eq!(update.version, "1.7.0");
    assert_eq!(update.notes, "novidades");
    assert_eq!(update.zip_file_name(), "EgeonDeck.zip");
    assert!(update.signature.is_some());
    assert!(update.is_newer("1.6.0"));
    assert!(!update.is_newer("1.7.0"));
    assert!(!update.is_newer("1.8.0"));
    assert!(!update.is_newer("nightly"));

    let unsigned =
        AvailableUpdate::parse(&release("v1.7.0", &["EgeonDeck.zip"]), &names()).unwrap();
    assert!(unsigned.signature.is_none());
    assert!(AvailableUpdate::parse(&release("v1.7.0", &["outro.zip"]), &names()).is_none());
    assert!(AvailableUpdate::parse(&release("nightly", &BOTH), &names()).is_none());
    assert!(AvailableUpdate::parse(b"{}", &names()).is_none());
    assert!(AvailableUpdate::parse(b"isto nao e json", &names()).is_none());
}

#[test]
fn a_politica_nunca_baixa_sem_a_opcao_e_so_avisa_na_abertura_ou_a_pedido() {
    use Action::*;
    use Reason::*;
    let p = UpdatePolicy::action;
    assert_eq!(p(false, Launch, true), Nothing);
    assert_eq!(p(false, Periodic, false), Nothing);
    assert_eq!(p(false, Manual, false), SayUpToDate);
    assert_eq!(p(true, Launch, false), Prompt);
    assert_eq!(p(true, Periodic, false), ShowInMenu);
    assert_eq!(p(true, Manual, false), Prompt);
    assert_eq!(p(true, Manual, true), Prompt);
    assert_eq!(p(true, Launch, true), DownloadQuietly);
    assert_eq!(p(true, Periodic, true), DownloadQuietly);
}

#[test]
fn o_aviso_diz_o_que_reiniciar_custa_e_o_que_o_clique_autoriza() {
    let many = prompt::text(&"x".repeat(900), 3);
    assert!(many.contains("3 agentes abertos"));
    assert!(many.contains("quarentena"));
    assert!(many.chars().count() < 900);
    assert!(prompt::text("", 1).contains("1 agente aberto"));
    assert!(!prompt::text("", 0).contains("agente"));
    // As novidades curtas vão inteiras, antes do resto.
    assert!(prompt::text("  novidades  ", 0).starts_with("novidades\n\nO app não tem"));
}

#[test]
fn a_chave_publicada_e_uma_chave_usavel() {
    let raw: [u8; 32] = STANDARD
        .decode(signature::PUBLIC_KEY)
        .unwrap()
        .try_into()
        .unwrap();
    assert!(VerifyingKey::from_bytes(&raw).is_ok());
}

// ---- A conferência do download, com o sistema de mentira

fn key() -> SigningKey {
    SigningKey::from_bytes(&[7u8; 32])
}

fn public_key(key: &SigningKey) -> String {
    STANDARD.encode(key.verifying_key().to_bytes())
}

fn sign(key: &SigningKey, zip: &[u8]) -> String {
    STANDARD.encode(key.sign(zip).to_bytes())
}

#[derive(Default)]
struct Calls {
    unpacked: usize,
    staged: usize,
    swaps: Vec<(u32, PathBuf, PathBuf, bool)>,
}

struct FakePlatform {
    can_install: bool,
    /// O que o "zip" tem dentro.
    app: Mutex<(String, String)>,
    code_signature_ok: bool,
    swap_fails: bool,
    calls: Mutex<Calls>,
}

impl FakePlatform {
    fn new(bundle_id: &str, version: &str) -> Arc<Self> {
        Arc::new(FakePlatform {
            can_install: true,
            app: Mutex::new((bundle_id.into(), version.into())),
            code_signature_ok: true,
            swap_fails: false,
            calls: Mutex::new(Calls::default()),
        })
    }

    fn with(self: Arc<Self>, edit: impl FnOnce(&mut FakePlatform)) -> Arc<Self> {
        let mut inner = Arc::try_unwrap(self).ok().unwrap();
        edit(&mut inner);
        Arc::new(inner)
    }
}

impl AppInstaller for FakePlatform {
    fn can_install(&self, _destination: &Path) -> bool {
        self.can_install
    }

    fn unpack(&self, zip: &Path, _into: &Path) -> Result<UnpackedApp, InstallError> {
        self.calls.lock().unwrap().unpacked += 1;
        assert!(
            zip.exists(),
            "o zip tem de estar em disco para o driver abrir"
        );
        let (bundle_id, version) = self.app.lock().unwrap().clone();
        Ok(UnpackedApp {
            path: PathBuf::from("/tmp/nunca-usado.app"),
            bundle_id,
            version,
        })
    }

    fn stage(&self, _app: &UnpackedApp, staged: &Path) -> Result<(), InstallError> {
        if !self.code_signature_ok {
            return Err(InstallError::BadCodeSignature);
        }
        self.calls.lock().unwrap().staged += 1;
        std::fs::create_dir_all(staged).map_err(|_| InstallError::CannotWrite(staged.into()))
    }

    fn launch_swap(&self, swap: Swap<'_>) -> io::Result<()> {
        if self.swap_fails {
            return Err(io::Error::other("sem sh"));
        }
        self.calls.lock().unwrap().swaps.push((
            swap.app_pid,
            swap.staged.to_owned(),
            swap.destination.to_owned(),
            swap.reopen,
        ));
        Ok(())
    }
}

struct Bench {
    dir: tempfile::TempDir,
    platform: Arc<FakePlatform>,
    key: SigningKey,
}

impl Bench {
    fn new(platform: Arc<FakePlatform>) -> Self {
        Bench {
            dir: tempfile::tempdir().unwrap(),
            platform,
            key: key(),
        }
    }

    fn destination(&self) -> PathBuf {
        self.dir.path().join("Egeon Deck.app")
    }

    fn installer(&self) -> UpdateInstaller {
        UpdateInstaller::new(
            self.destination(),
            "dev.teste.egeon",
            "1.6.0",
            self.dir.path().to_owned(),
            self.platform.clone(),
        )
        .with_public_key(public_key(&self.key))
    }

    fn work_leftovers(&self) -> Vec<String> {
        std::fs::read_dir(self.dir.path())
            .unwrap()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .filter(|n| n.starts_with("egeon-update-"))
            .collect()
    }
}

#[test]
fn prepare_deixa_pronto_um_app_assinado_e_mais_novo() {
    let b = Bench::new(FakePlatform::new("dev.teste.egeon", "1.7.0"));
    let installer = b.installer();
    let zip = b"conteudo do zip";
    assert_eq!(installer.prepare(zip, &sign(&b.key, zip)).unwrap(), "1.7.0");
    assert!(installer.is_staged());
    assert_eq!(
        installer.staged().file_name().unwrap(),
        "Egeon Deck.app.novo"
    );
    // A pasta de trabalho não sobra.
    assert!(b.work_leftovers().is_empty());
    // O `.sig` costuma vir com a quebra de linha do fim.
    installer.discard_staged();
    assert!(!installer.is_staged());
    let with_newline = format!("{}\n", sign(&b.key, zip));
    assert_eq!(installer.prepare(zip, &with_newline).unwrap(), "1.7.0");
}

#[test]
fn prepare_recusa_o_que_nao_da_para_confiar() {
    let installer_for = |bundle: &str, version: &str, code_ok: bool| {
        let platform = FakePlatform::new(bundle, version).with(|p| p.code_signature_ok = code_ok);
        let b = Bench::new(platform);
        let installer = b.installer();
        (b, installer)
    };
    let zip = b"zip assinado";

    // Um byte a mais no zip, ou assinado por outra chave, ou nem base64.
    let (b, installer) = installer_for("dev.teste.egeon", "1.7.0", true);
    let good = sign(&b.key, zip);
    let mut longer = zip.to_vec();
    longer.push(0);
    assert_eq!(
        installer.prepare(&longer, &good),
        Err(Failure::BadSignature)
    );
    let stranger = SigningKey::from_bytes(&[9u8; 32]);
    assert_eq!(
        installer.prepare(zip, &sign(&stranger, zip)),
        Err(Failure::BadSignature)
    );
    assert_eq!(
        installer.prepare(zip, "isto não é base64"),
        Err(Failure::BadSignature)
    );
    assert_eq!(installer.prepare(zip, ""), Err(Failure::BadSignature));
    assert_eq!(
        b.platform.calls.lock().unwrap().unpacked,
        0,
        "nem abriu o zip"
    );
    assert!(!installer.is_staged());

    // Assinado de verdade, e mesmo assim não serve.
    let (b, installer) = installer_for("dev.teste.egeon", "1.6.0", true);
    assert_eq!(
        installer.prepare(zip, &sign(&b.key, zip)),
        Err(Failure::NotNewer("1.6.0".into()))
    );
    assert!(!installer.is_staged());
    let (b, installer) = installer_for("dev.outro.app", "1.7.0", true);
    assert_eq!(
        installer.prepare(zip, &sign(&b.key, zip)),
        Err(Failure::WrongApp("dev.outro.app".into()))
    );
    let (b, installer) = installer_for("dev.teste.egeon", "1.7.0", false);
    assert_eq!(
        installer.prepare(zip, &sign(&b.key, zip)),
        Err(Failure::BadCodeSignature)
    );
    assert!(!installer.is_staged());
    assert!(b.work_leftovers().is_empty());
}

#[test]
fn as_mensagens_de_falha_sao_as_do_swift() {
    assert_eq!(
        Failure::BadSignature.to_string(),
        "a assinatura do download não confere"
    );
    assert_eq!(
        Failure::NotInstallable("sem bundle dentro".into()).to_string(),
        "o download não é um app válido (sem bundle dentro)"
    );
    assert_eq!(
        Failure::WrongApp("dev.x".into()).to_string(),
        "o download é de outro app (dev.x)"
    );
    assert_eq!(
        Failure::NotNewer("1.6.0".into()).to_string(),
        "o download traz a versão 1.6.0, que não é mais nova"
    );
    assert_eq!(
        Failure::BadCodeSignature.to_string(),
        "a assinatura de código do app baixado está quebrada"
    );
    assert_eq!(
        Failure::CannotWrite("/Applications".into()).to_string(),
        "sem permissão para escrever em /Applications"
    );
}

// ---- A regra do UpdateController

struct Rig {
    b: Bench,
    controller: UpdateController,
}

fn rig(platform: Arc<FakePlatform>, is_dev: bool) -> Rig {
    let b = Bench::new(platform);
    let controller = controller_in(&b, is_dev);
    Rig { b, controller }
}

fn controller_in(b: &Bench, is_dev: bool) -> UpdateController {
    UpdateController::new(
        Arc::new(b.installer()),
        UpdateConfig {
            installed_version: "1.6.0".into(),
            display_name: "Egeon Deck".into(),
            is_dev,
            app_pid: 4242,
            settings_file: b.dir.path().join("update.json"),
            swap_log: b.dir.path().join("update.log"),
            feed: FEED.into(),
            assets: names(),
        },
    )
}

fn newer() -> AvailableUpdate {
    AvailableUpdate::parse(&release("v1.7.0", &BOTH), &names()).unwrap()
}

fn fetched(r: &mut Rig, reason: Reason, tag: &str, assets: &[&str]) -> Vec<Effect> {
    r.controller
        .release_fetched(reason, FetchOutcome::Body(release(tag, assets)))
}

fn platform() -> Arc<FakePlatform> {
    FakePlatform::new("dev.teste.egeon", "1.7.0")
}

#[test]
fn ao_abrir_o_aviso_e_o_automatico_baixa_sem_perguntar() {
    let mut r = rig(platform(), false);
    assert_eq!(
        r.controller.check(Reason::Launch, None),
        [Effect::FetchRelease {
            reason: Reason::Launch,
            feed: FEED.into()
        }]
    );
    assert_eq!(r.controller.state(), &State::Checking);
    assert!(!r.controller.menu_enabled());
    assert_eq!(
        fetched(&mut r, Reason::Launch, "v1.7.0", &BOTH),
        [Effect::Prompt(newer())]
    );
    assert_eq!(r.controller.state(), &State::Available(newer()));
    assert_eq!(r.controller.menu_title(), "Atualizar para a versão 1.7.0…");

    let mut auto = rig(platform(), false);
    auto.controller.set_auto(true);
    auto.controller.check(Reason::Launch, None);
    assert_eq!(
        fetched(&mut auto, Reason::Launch, "v1.7.0", &BOTH),
        [Effect::Download(newer())]
    );
    assert_eq!(auto.controller.state(), &State::Downloading(newer()));
    assert_eq!(auto.controller.menu_title(), "Baixando a versão 1.7.0…");
}

#[test]
fn consulta_periodica_so_muda_o_menu() {
    let mut r = rig(platform(), false);
    r.controller.check(Reason::Periodic, None);
    assert_eq!(fetched(&mut r, Reason::Periodic, "v1.7.0", &BOTH), []);
    assert_eq!(r.controller.menu_title(), "Atualizar para a versão 1.7.0…");
    // A mesma versão de novo: segue disponível, sem aviso.
    r.controller.check(Reason::Periodic, None);
    assert_eq!(fetched(&mut r, Reason::Periodic, "v1.6.0", &BOTH), []);
    assert_eq!(r.controller.state(), &State::Idle);
}

#[test]
fn a_pedido_na_ultima_versao_diz_que_esta_na_ultima() {
    let mut r = rig(platform(), false);
    assert_eq!(r.controller.menu_clicked().len(), 1);
    assert_eq!(
        fetched(&mut r, Reason::Manual, "v1.6.0", &BOTH),
        [Effect::Message {
            title: "Você está na última versão".into(),
            text: "Egeon Deck 1.6.0.".into(),
        }]
    );
    assert_eq!(r.controller.state(), &State::Idle);
}

#[test]
fn consulta_que_falha_volta_ao_estado_de_antes() {
    let mut r = rig(platform(), false);
    r.controller.check(Reason::Periodic, None);
    fetched(&mut r, Reason::Periodic, "v1.7.0", &BOTH);
    let available = r.controller.state().clone();

    r.controller.check(Reason::Periodic, None);
    assert_eq!(
        r.controller
            .release_fetched(Reason::Periodic, FetchOutcome::Failed("sem rede".into())),
        []
    );
    assert_eq!(r.controller.state(), &available);

    r.controller.check(Reason::Manual, None);
    assert_eq!(
        r.controller
            .release_fetched(Reason::Manual, FetchOutcome::Body(b"{}".to_vec())),
        [Effect::Message {
            title: "Não deu para procurar atualizações".into(),
            text: "Confira a internet e tente de novo.".into(),
        }]
    );
    assert_eq!(r.controller.state(), &available);
}

#[test]
fn nao_consulta_por_cima_de_consulta_ou_download() {
    let mut r = rig(platform(), false);
    r.controller.check(Reason::Periodic, None);
    assert_eq!(r.controller.check(Reason::Manual, None), []);
    r.controller
        .release_fetched(Reason::Periodic, FetchOutcome::Failed("x".into()));
    r.controller.update_and_restart(newer());
    assert!(matches!(r.controller.state(), State::Downloading(_)));
    assert_eq!(r.controller.check(Reason::Manual, None), []);
}

#[test]
fn atualizar_e_reiniciar_baixa_confere_troca_e_encerra() {
    let mut r = rig(platform(), false);
    assert_eq!(
        r.controller.update_and_restart(newer()),
        [Effect::Download(newer())]
    );
    let zip = b"zip";
    let version = r.controller.installer().prepare(zip, &sign(&r.b.key, zip));
    assert_eq!(r.controller.prepared(newer(), version), [Effect::Terminate]);
    assert_eq!(r.controller.state(), &State::Ready("1.7.0".into()));
    let swaps = &r.b.platform.calls.lock().unwrap().swaps;
    assert_eq!(swaps.len(), 1);
    assert_eq!(swaps[0].0, 4242);
    assert_eq!(swaps[0].1, r.controller.installer().staged());
    assert_eq!(swaps[0].2, r.b.destination());
    assert!(swaps[0].3, "reabre o app");
}

#[test]
fn baixada_sem_reiniciar_espera_o_clique_no_menu() {
    let mut r = rig(platform(), false);
    r.controller.set_auto(true);
    r.controller.check(Reason::Launch, None);
    fetched(&mut r, Reason::Launch, "v1.7.0", &BOTH);
    assert_eq!(r.controller.prepared(newer(), Ok("1.7.0".into())), []);
    assert!(r.b.platform.calls.lock().unwrap().swaps.is_empty());
    assert_eq!(
        r.controller.menu_title(),
        "Reiniciar para atualizar para a versão 1.7.0"
    );
    assert!(r.controller.menu_enabled());

    // O clique no menu pede o aviso com a versão pronta; reiniciar troca de vez.
    let effects = r.controller.menu_clicked();
    assert!(
        matches!(&effects[..], [Effect::Prompt(u)] if u.version == "1.7.0" && u.notes.is_empty())
    );
    assert_eq!(
        r.controller.update_and_restart(newer()),
        [Effect::Terminate]
    );
    // A troca é solta uma vez só.
    assert_eq!(r.controller.restart(), [Effect::Terminate]);
    assert_eq!(r.b.platform.calls.lock().unwrap().swaps.len(), 1);
}

#[test]
fn consulta_manual_com_a_versao_ja_baixada_so_pede_o_aviso() {
    let mut r = rig(platform(), false);
    r.controller.update_and_restart(newer());
    r.controller.prepared(newer(), Ok("1.7.0".into()));
    r.controller.menu_clicked();
    // `menu_clicked` no estado pronto não consulta; a consulta periódica sim.
    r.controller.check(Reason::Periodic, None);
    assert_eq!(fetched(&mut r, Reason::Periodic, "v1.7.0", &BOTH), []);
    assert_eq!(r.controller.state(), &State::Ready("1.7.0".into()));
    r.controller.check(Reason::Manual, None);
    assert_eq!(
        fetched(&mut r, Reason::Manual, "v1.7.0", &BOTH),
        [Effect::Prompt(newer())]
    );
    assert_eq!(r.controller.state(), &State::Ready("1.7.0".into()));
}

#[test]
fn falhas_de_download_voltam_a_disponivel_com_a_mensagem() {
    let message = |effects: Vec<Effect>| match effects.as_slice() {
        [Effect::Message { title, text }] => {
            assert_eq!(title, "Não deu para atualizar");
            text.clone()
        }
        other => panic!("{other:?}"),
    };

    // Sem assinatura publicada.
    let mut r = rig(platform(), false);
    let unsigned =
        AvailableUpdate::parse(&release("v1.7.0", &["EgeonDeck.zip"]), &names()).unwrap();
    assert_eq!(
        message(r.controller.update_and_restart(unsigned.clone())),
        "A versão 1.7.0 foi publicada sem assinatura, e o app não instala o que não pode conferir."
    );
    assert_eq!(r.controller.state(), &State::Available(unsigned));

    // App num lugar onde não dá para trocar.
    let mut stuck = rig(platform().with(|p| p.can_install = false), false);
    let text = message(stuck.controller.update_and_restart(newer()));
    assert!(
        text.starts_with("O app não está num lugar onde possa ser trocado ("),
        "{text}"
    );
    assert!(
        text.ends_with(&cannot_install_hint(std::env::consts::OS, &newer().page)),
        "{text}"
    );
    assert_eq!(
        cannot_install_hint("macos", "https://x/r"),
        "Mova-o para /Applications e tente de novo."
    );
    assert_eq!(
        cannot_install_hint("linux", "https://github.com/o/r/releases/tag/v1.7.0"),
        "Só o AppImage se atualiza sozinho: baixe a versão nova em \
         https://github.com/o/r/releases/tag/v1.7.0"
    );
    assert_eq!(stuck.controller.state(), &State::Available(newer()));

    // O download não passou na conferência. E a opção "reiniciar quando
    // pronto" não fica armada para a próxima.
    let mut r = rig(platform(), false);
    r.controller.update_and_restart(newer());
    let text = message(r.controller.prepared(newer(), Err(Failure::BadSignature)));
    assert_eq!(
        text,
        "A atualização não foi instalada: a assinatura do download não confere"
    );
    assert_eq!(r.controller.state(), &State::Available(newer()));
    assert_eq!(r.controller.prepared(newer(), Ok("1.7.0".into())), []);
    assert!(r.b.platform.calls.lock().unwrap().swaps.is_empty());
}

#[test]
fn troca_que_nao_sobe_vira_mensagem_e_nao_encerra() {
    let mut r = rig(platform().with(|p| p.swap_fails = true), false);
    r.controller.update_and_restart(newer());
    let effects = r.controller.prepared(newer(), Ok("1.7.0".into()));
    assert_eq!(
        effects,
        [Effect::Message {
            title: "Não deu para atualizar".into(),
            text: "Não consegui preparar a troca: sem sh".into(),
        }]
    );
}

#[test]
fn ao_sair_so_troca_com_a_opcao_ligada_e_a_versao_pronta() {
    let mut r = rig(platform(), false);
    // Pronta pelo automático, que não reinicia sozinho.
    r.controller.set_auto(true);
    r.controller.check(Reason::Launch, None);
    fetched(&mut r, Reason::Launch, "v1.7.0", &BOTH);
    std::fs::create_dir_all(r.controller.installer().staged()).unwrap();
    r.controller.prepared(newer(), Ok("1.7.0".into()));
    assert_eq!(r.controller.state(), &State::Ready("1.7.0".into()));

    // Sem a opção, o app sai e nada troca.
    r.controller.set_auto(false);
    assert_eq!(r.controller.application_will_terminate(), []);
    assert!(r.b.platform.calls.lock().unwrap().swaps.is_empty());

    r.controller.set_auto(true);
    assert_eq!(r.controller.application_will_terminate(), []);
    let swaps = &r.b.platform.calls.lock().unwrap().swaps;
    assert_eq!(swaps.len(), 1);
    assert!(!swaps[0].3, "ao sair não reabre");
}

#[test]
fn ligar_o_automatico_com_versao_disponivel_baixa_na_hora() {
    let mut r = rig(platform(), false);
    r.controller.check(Reason::Periodic, None);
    fetched(&mut r, Reason::Periodic, "v1.7.0", &BOTH);
    assert_eq!(r.controller.set_auto(true), [Effect::Download(newer())]);
    assert_eq!(r.controller.set_auto(false), []);
}

#[test]
fn a_opcao_de_atualizar_sozinho_sobrevive_ao_app() {
    let r = rig(platform(), false);
    let mut first = controller_in(&r.b, false);
    assert!(!first.auto());
    first.set_auto(true);
    assert_eq!(
        std::fs::read_to_string(r.b.dir.path().join("update.json")).unwrap(),
        r#"{"auto":true}"#
    );
    assert!(controller_in(&r.b, false).auto());
    std::fs::write(r.b.dir.path().join("update.json"), "lixo").unwrap();
    assert!(!controller_in(&r.b, false).auto());
    // Com BOM e chave repetida, como o `JSONDecoder` abre: a primeira vence.
    std::fs::write(
        r.b.dir.path().join("update.json"),
        b"\xEF\xBB\xBF{\"auto\":true,\"auto\":false}",
    )
    .unwrap();
    assert!(controller_in(&r.b, false).auto());
}

#[test]
fn ao_abrir_o_estavel_descarta_o_bundle_esperando_e_pede_as_consultas() {
    let r = rig(platform(), false);
    let installer = r.controller.installer().clone();
    std::fs::create_dir_all(installer.staged()).unwrap();
    assert!(installer.is_staged());
    assert!(r.controller.start());
    assert!(!installer.is_staged());
    assert_eq!(FIRST_CHECK_AFTER.as_secs(), 4);
    assert_eq!(CHECK_EVERY.as_secs(), 6 * 3600);

    // No dev o número não diz nada: não consulta e não mexe em nada.
    let dev = rig(platform(), true);
    std::fs::create_dir_all(dev.controller.installer().staged()).unwrap();
    assert!(!dev.controller.start());
    assert!(dev.controller.installer().is_staged());
}

#[test]
fn a_rota_update_mostra_o_estado_e_so_no_dev_troca_o_feed() {
    let query = |pairs: &[(&str, &str)]| {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect::<HashMap<_, _>>()
    };
    let mut stable = rig(platform(), false);
    let (effects, snapshot) = stable
        .controller
        .control(&query(&[("check", "1"), ("feed", "http://falso/release")]));
    assert_eq!(
        effects,
        [Effect::FetchRelease {
            reason: Reason::Periodic,
            feed: FEED.into()
        }]
    );
    assert_eq!(snapshot["state"], "checking");
    assert_eq!(snapshot["menu"], "Procurando atualizações…");
    assert_eq!(snapshot["installed"], "1.6.0");
    assert_eq!(snapshot["auto"], false);
    assert_eq!(snapshot["staged"], false);
    assert!(snapshot.get("version").is_none());

    let mut dev = rig(platform(), true);
    let (effects, _) = dev
        .controller
        .control(&query(&[("check", "1"), ("feed", "http://falso/release")]));
    assert_eq!(
        effects,
        [Effect::FetchRelease {
            reason: Reason::Periodic,
            feed: "http://falso/release".into()
        }]
    );

    let mut r = rig(platform(), false);
    r.controller.check(Reason::Periodic, None);
    fetched(&mut r, Reason::Periodic, "v1.7.0", &BOTH);
    let (effects, snapshot) = r
        .controller
        .control(&query(&[("auto", "1"), ("prompt", "1")]));
    assert_eq!(snapshot["auto"], true);
    assert_eq!(snapshot["state"], "downloading");
    assert_eq!(snapshot["version"], "1.7.0");
    assert_eq!(effects, [Effect::Download(newer())]);
}

// ---- A rede, contra um servidor HTTP local de mentira (nunca a internet)

mod network {
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::thread::JoinHandle;

    use super::*;
    use crate::features::update::fetch::{Completion, UpdateClient};

    /// Atende uma requisição por conexão com `route(caminho, user_agent)`, que
    /// devolve `(status, cabeçalhos extras, corpo)`.
    struct Web {
        base: String,
        stop: Arc<AtomicBool>,
        handle: Option<JoinHandle<()>>,
    }

    type Reply = (u16, Vec<(String, String)>, Vec<u8>);

    impl Web {
        fn start(route: impl Fn(&str, &str) -> Reply + Send + 'static) -> Web {
            let listener = TcpListener::bind("127.0.0.1:0").unwrap();
            listener.set_nonblocking(true).unwrap();
            let base = format!("http://{}", listener.local_addr().unwrap());
            let stop = Arc::new(AtomicBool::new(false));
            let flag = Arc::clone(&stop);
            let handle = std::thread::spawn(move || {
                while !flag.load(Ordering::Relaxed) {
                    let Ok((mut stream, _)) = listener.accept() else {
                        std::thread::sleep(std::time::Duration::from_millis(2));
                        continue;
                    };
                    stream.set_nonblocking(false).unwrap();
                    let mut buf = [0u8; 4096];
                    let n = stream.read(&mut buf).unwrap_or(0);
                    let request = String::from_utf8_lossy(&buf[..n]).into_owned();
                    let path = request.split(' ').nth(1).unwrap_or("/").to_owned();
                    let agent = request
                        .lines()
                        .find_map(|l| {
                            l.strip_prefix("user-agent: ")
                                .or_else(|| l.strip_prefix("User-Agent: "))
                        })
                        .unwrap_or("")
                        .to_owned();
                    let (status, headers, body) = route(&path, &agent);
                    let mut head = format!(
                        "HTTP/1.1 {status} X\r\nContent-Length: {}\r\nConnection: close\r\n",
                        body.len()
                    );
                    for (k, v) in headers {
                        head.push_str(&format!("{k}: {v}\r\n"));
                    }
                    head.push_str("\r\n");
                    let _ = stream.write_all(head.as_bytes());
                    let _ = stream.write_all(&body);
                }
            });
            Web {
                base,
                stop,
                handle: Some(handle),
            }
        }
    }

    impl Drop for Web {
        fn drop(&mut self) {
            self.stop.store(true, Ordering::Relaxed);
            if let Some(h) = self.handle.take() {
                let _ = h.join();
            }
        }
    }

    fn ok(body: &[u8]) -> Reply {
        (200, Vec::new(), body.to_vec())
    }

    #[tokio::test]
    async fn consulta_a_release_com_o_user_agent_e_devolve_o_corpo() {
        let web = Web::start(|path, agent| match path {
            "/release" => ok(agent.as_bytes()),
            _ => (404, Vec::new(), b"nada".to_vec()),
        });
        let client = UpdateClient::new("1.6.0", true).unwrap();
        assert_eq!(
            client.fetch_release(&format!("{}/release", web.base)).await,
            FetchOutcome::Body(b"EgeonDeck/1.6.0".to_vec())
        );
    }

    #[tokio::test]
    async fn so_https_fora_do_dev() {
        let web = Web::start(|_, _| ok(b"{}"));
        let strict = UpdateClient::new("1.6.0", false).unwrap();
        // O estável recusa http, mesmo que o servidor responda.
        assert!(matches!(
            strict.fetch_release(&format!("{}/release", web.base)).await,
            FetchOutcome::Failed(_)
        ));
        let dev = UpdateClient::new("1.6.0", true).unwrap();
        assert_eq!(
            dev.fetch_release(&format!("{}/release", web.base)).await,
            FetchOutcome::Body(b"{}".to_vec())
        );
    }

    #[tokio::test]
    async fn resposta_acima_do_teto_e_recusada_com_ou_sem_content_length() {
        let web = Web::start(|_, _| ok(&[b'x'; 100]));
        let client = UpdateClient::new("1.6.0", true)
            .unwrap()
            .with_limits(50, 50, 50);
        let url = format!("{}/release", web.base);
        assert_eq!(
            client.fetch_release(&url).await,
            FetchOutcome::Failed("resposta maior que 50 bytes".into())
        );
        let roomy = UpdateClient::new("1.6.0", true)
            .unwrap()
            .with_limits(100, 50, 50);
        assert!(matches!(roomy.fetch_release(&url).await, FetchOutcome::Body(b) if b.len() == 100));
        // O zip tem teto próprio: acima dele o download falha como um todo.
        let b = Bench::new(platform());
        let installer = Arc::new(b.installer());
        // A assinatura (100 bytes) cabe no teto dela; é o zip (também 100) que
        // passa do dele.
        let update = update_at(&web.base);
        let zip_capped = UpdateClient::new("1.6.0", true)
            .unwrap()
            .with_limits(50, 200, 50);
        assert_eq!(
            zip_capped.download(&update, installer).await,
            Err(Failure::NotInstallable("o download falhou".into()))
        );
    }

    #[tokio::test]
    async fn status_diferente_de_200_e_sem_servidor_viram_falha_com_motivo() {
        let web = Web::start(|_, _| (403, Vec::new(), b"limite".to_vec()));
        let client = UpdateClient::new("1.6.0", true).unwrap();
        assert_eq!(
            client.fetch_release(&format!("{}/x", web.base)).await,
            FetchOutcome::Failed("resposta 403".into())
        );
        let gone = {
            let listener = TcpListener::bind("127.0.0.1:0").unwrap();
            format!("http://{}", listener.local_addr().unwrap())
        };
        assert!(matches!(
            client.fetch_release(&gone).await,
            FetchOutcome::Failed(_)
        ));
    }

    /// Um servidor com a release, o zip (atrás de um redirecionamento, como o
    /// GitHub) e a assinatura.
    fn release_site(key: &SigningKey, zip: &'static [u8]) -> Web {
        let signature = sign(key, zip);
        Web::start(move |path, _| match path {
            "/EgeonDeck.zip" => (
                302,
                vec![("Location".into(), "/objetos/real.zip".into())],
                Vec::new(),
            ),
            "/objetos/real.zip" => ok(zip),
            "/EgeonDeck.zip.sig" => ok(format!("{signature}\n").as_bytes()),
            _ => (404, Vec::new(), Vec::new()),
        })
    }

    fn update_at(base: &str) -> AvailableUpdate {
        let mut update = newer();
        update.zip = format!("{base}/EgeonDeck.zip");
        update.signature = Some(format!("{base}/EgeonDeck.zip.sig"));
        update
    }

    #[tokio::test]
    async fn baixa_segue_o_redirecionamento_confere_e_deixa_pronto() {
        let b = Bench::new(platform());
        let web = release_site(&b.key, b"zip de verdade");
        let installer = Arc::new(b.installer());
        let client = UpdateClient::new("1.6.0", true).unwrap();
        let update = update_at(&web.base);
        assert_eq!(
            client.download(&update, installer.clone()).await,
            Ok("1.7.0".to_owned())
        );
        assert!(installer.is_staged());
    }

    #[tokio::test]
    async fn download_que_falha_ou_nao_confere_nao_deixa_nada() {
        let b = Bench::new(platform());
        let installer = Arc::new(b.installer());
        let client = UpdateClient::new("1.6.0", true).unwrap();

        // Servidor que não tem o zip.
        let missing = Web::start(|_, _| (404, Vec::new(), Vec::new()));
        assert_eq!(
            client
                .download(&update_at(&missing.base), installer.clone())
                .await,
            Err(Failure::NotInstallable("o download falhou".into()))
        );

        // O zip chega, mas a assinatura é de outra chave.
        let other = SigningKey::from_bytes(&[9u8; 32]);
        let forged = release_site(&other, b"zip adulterado");
        assert_eq!(
            client
                .download(&update_at(&forged.base), installer.clone())
                .await,
            Err(Failure::BadSignature)
        );
        assert!(!installer.is_staged());

        // Sem assinatura publicada, nem tenta.
        let mut unsigned = update_at(&forged.base);
        unsigned.signature = None;
        assert!(client.download(&unsigned, installer).await.is_err());
    }

    #[tokio::test]
    async fn o_executor_fecha_o_ciclo_com_o_controller() {
        let b = Bench::new(platform());
        let web = release_site(&b.key, b"zip de verdade");
        let release_json = {
            let mut json: serde_json::Value =
                serde_json::from_slice(&release("v1.7.0", &BOTH)).unwrap();
            json["assets"][0]["browser_download_url"] =
                json!(format!("{}/EgeonDeck.zip", web.base));
            json["assets"][1]["browser_download_url"] =
                json!(format!("{}/EgeonDeck.zip.sig", web.base));
            serde_json::to_vec(&json).unwrap()
        };
        let feed = Web::start(move |_, _| ok(&release_json));
        let mut controller = controller_in(&b, false);
        controller.set_auto(true);
        let client = UpdateClient::new("1.6.0", true).unwrap();
        let installer = controller.installer().clone();

        // Consulta → baixa sozinha (automático) → pronta; nada reinicia.
        let mut pending = controller.check(Reason::Launch, Some(&format!("{}/release", feed.base)));
        let mut seen_prompt = false;
        while let Some(effect) = pending.pop() {
            match client.execute(effect.clone(), installer.clone()).await {
                Some(done @ (Completion::Fetched { .. } | Completion::Prepared { .. })) => {
                    pending.extend(done.apply(&mut controller));
                }
                None => seen_prompt |= matches!(effect, Effect::Prompt(_)),
            }
        }
        assert!(!seen_prompt);
        assert_eq!(controller.state(), &State::Ready("1.7.0".into()));
        assert!(installer.is_staged());
        assert!(b.platform.calls.lock().unwrap().swaps.is_empty());
    }
}
