//! Apps abertos pelo `lsappinfo`; `lsof` e `docker` nos caminhos do macOS.

use std::path::Path;

use egeon_core::ports::procs::RunningApp;
use objc2_app_kit::NSRunningApplication;

pub(super) const LSOF: &str = "/usr/sbin/lsof";
pub(super) const DOCKER: &str = "/Applications/Docker.app/Contents/Resources/bin/docker";
const LSAPPINFO: &str = "/usr/bin/lsappinfo";

/// Pelo `lsappinfo`, e não pelo `NSWorkspace.runningApplications`: a lista do
/// `NSWorkspace` só se atualiza quando o run loop principal gira, e o core
/// chama de uma thread de fundo — veria uma foto congelada da primeira leitura.
pub(super) fn running_apps() -> Vec<RunningApp> {
    super::run(Path::new(LSAPPINFO), &["list"], true)
        .map(|output| parse_lsappinfo(&output))
        .unwrap_or_default()
}

/// A saída de `lsappinfo list`: um bloco por app, com `bundleID="…"` (ou
/// `[ NULL ]` quando não tem) e `pid = …` mais abaixo.
fn parse_lsappinfo(output: &str) -> Vec<RunningApp> {
    let mut apps = Vec::new();
    let mut bundle: Option<String> = None;
    for line in output.lines() {
        let line = line.trim();
        if let Some(value) = line.strip_prefix("bundleID=") {
            bundle = value
                .strip_prefix('"')
                .and_then(|rest| rest.split('"').next())
                .map(str::to_string);
        } else if let Some(rest) = line.strip_prefix("pid = ") {
            let pid = rest.split_whitespace().next().and_then(|p| p.parse().ok());
            if let (Some(bundle), Some(pid)) = (bundle.take(), pid) {
                apps.push(RunningApp { bundle, pid });
            }
        } else if line.contains(" ASN:") && !line.starts_with("bundle") {
            // Cabeçalho de um app novo: o bundle do anterior não vale para ele.
            bundle = None;
        }
    }
    apps
}

/// O mesmo pedido do ⌘Q. Processo que não é app (sem janela, sem bundle) não
/// tem `NSRunningApplication`, e aí não há nada a pedir.
pub(super) fn request_quit(pid: u32) {
    let Ok(pid) = i32::try_from(pid) else {
        return;
    };
    if let Some(app) = NSRunningApplication::runningApplicationWithProcessIdentifier(pid) {
        app.terminate();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lsappinfo_vira_bundle_e_pid_e_ignora_app_sem_bundle() {
        let output = r#" 1) "loginwindow" ASN:0x0-0x2002: (in front) 
    bundleID="com.apple.loginwindow"
    bundle path="/System/Library/CoreServices/loginwindow.app"
    pid = 397 type="UIElement" flavor=3 Version="3085.6.3" fileType="APPL" creator="lgnw" Arch=ARM64 
    childASNs: ASN:0x0-0x2b02b: ASN:0x0-0x2d02d: 
 2) "universalaccessd" ASN:0x0-0x8008: 
    bundleID=[ NULL ] 
    bundle path="/usr/sbin/universalaccessd"
    pid = 590 !signalled type="BackgroundOnly" flavor=3 Version=[ NULL ]  fileType="????" creator="????" Arch=ARM64 
 3) "Dock" ASN:0x0-0xb00b: 
    bundleID="com.apple.dock"
    pid = 600 type="UIElement" flavor=3
"#;
        assert_eq!(
            parse_lsappinfo(output),
            vec![
                RunningApp {
                    bundle: "com.apple.loginwindow".into(),
                    pid: 397
                },
                RunningApp {
                    bundle: "com.apple.dock".into(),
                    pid: 600
                },
            ]
        );
    }
}
