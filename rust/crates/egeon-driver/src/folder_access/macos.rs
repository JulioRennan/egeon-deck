//! O `tccutil` do macOS: o `reset` da própria pasta, do próprio app, não pede
//! senha e devolve a decisão para "não perguntado".

use std::path::Path;
use std::process::{Command, Stdio};

use objc2_foundation::NSBundle;

const TCCUTIL: &str = "/usr/bin/tccutil";
const SETTINGS_URL: &str =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders";

pub(super) fn settings_url() -> Option<String> {
    Some(SETTINGS_URL.to_owned())
}

pub(super) fn reset(service: &str) -> bool {
    let Some(bundle) = app_bundle_id() else {
        return false;
    };
    reset_with(Path::new(TCCUTIL), service, &bundle)
}

/// O identificador do app, só quando o executável está dentro de um `.app`:
/// fora dele não há decisão do usuário para zerar.
fn app_bundle_id() -> Option<String> {
    let main = NSBundle::mainBundle();
    if main.bundleURL().pathExtension()?.to_string() != "app" {
        return None;
    }
    main.bundleIdentifier().map(|id| id.to_string())
}

/// Rodou e terminou. O código de saída não conta: o `tccutil` sai com erro
/// para serviço que não conhece, e a leitura seguinte é que diz o que valeu.
fn reset_with(program: &Path, service: &str, bundle: &str) -> bool {
    Command::new(program)
        .args(["reset", service, bundle])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok()
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    use super::*;

    #[test]
    fn chama_o_tccutil_com_servico_e_bundle() -> std::io::Result<()> {
        let dir = tempfile::tempdir()?;
        let args = dir.path().join("args");
        let script = dir.path().join("tccutil");
        fs::write(
            &script,
            format!("#!/bin/sh\necho \"$@\" > '{}'\nexit 1\n", args.display()),
        )?;
        fs::set_permissions(&script, fs::Permissions::from_mode(0o755))?;
        assert!(reset_with(
            &script,
            "SystemPolicyDocumentsFolder",
            "dev.teste.app"
        ));
        assert_eq!(
            fs::read_to_string(args)?.trim(),
            "reset SystemPolicyDocumentsFolder dev.teste.app"
        );
        Ok(())
    }

    #[test]
    fn comando_que_nao_abre_nao_rodou() {
        assert!(!reset_with(Path::new("/nao/existe/tccutil"), "X", "y"));
    }

    #[test]
    fn o_painel_e_o_de_arquivos_e_pastas() {
        assert_eq!(
            settings_url().as_deref(),
            Some("x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
        );
    }

    #[test]
    fn fora_de_um_app_nao_ha_o_que_zerar() {
        assert!(!reset("SystemPolicyDocumentsFolder"));
    }
}
