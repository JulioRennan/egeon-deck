//! Traz o libghostty-vt pré-compilado do projeto Ghostty e o liga estático
//! (decisão 14 de `docs/migracao/3-proposta.html`).
//!
//! A origem é fixa: versão, URL e sha256 abaixo, tirados do `SHA256SUMS`
//! publicado com a versão. O arquivo baixado é conferido toda vez que este
//! script roda, inclusive o que já estava no cache.

use std::env;
use std::error::Error;
use std::fs::{self, File};
use std::io::{self, Read};
use std::path::{Path, PathBuf};
use std::process::Command;

use sha2::{Digest, Sha256};

const VERSION: &str = "1.0.1";
const BASE_URL: &str = "https://release.files.ghostty.org/libghostty-vt";
/// `ghostty-vt-1.0.1.xcframework.zip` em `SHA256SUMS` da 1.0.1.
const APPLE_SHA256: &str = "c0f9631277f726154c8f521954d17cdc41aac4626fc0df8cf925a19ee58e829b";
/// Dentro do xcframework, a fatia de macOS é universal (arm64 + x86_64).
const APPLE_LIB_IN_ZIP: &str = "ghostty-vt.xcframework/macos-arm64_x86_64/libghostty-vt.a";
/// O `.a` acima, tirado do zip conferido. Conferir o que vai para o link, e não
/// só o zip, pega o cache mexido sem extrair de novo a cada build.
const APPLE_LIB_SHA256: &str = "5388c66b81d8fadc63d4fd6ca8984d2be4645a98d2397ad9d43437a6b96c7cf5";
/// Pasta com um `libghostty-vt.a` pronto: build sem rede, ou o plano B
/// (compilado do fonte com Zig). Pula o download e a conferência.
const LIB_DIR_ENV: &str = "EGEON_GHOSTTY_VT_DIR";

type Res<T> = Result<T, Box<dyn Error>>;

fn main() -> Res<()> {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed={LIB_DIR_ENV}");
    println!("cargo:rerun-if-env-changed=CARGO_TARGET_DIR");

    let lib_dir = match env::var_os(LIB_DIR_ENV) {
        Some(dir) => {
            let dir = PathBuf::from(dir);
            println!(
                "cargo:warning=libghostty-vt de {} ({LIB_DIR_ENV}): não conferido por sha256",
                dir.display()
            );
            dir
        }
        None => official_lib()?,
    };
    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    println!("cargo:rustc-link-lib=static=ghostty-vt");
    Ok(())
}

fn official_lib() -> Res<PathBuf> {
    let os = env::var("CARGO_CFG_TARGET_OS")?;
    if os != "macos" {
        return Err(format!(
            "libghostty-vt {VERSION}: só o binário de macOS está ligado aqui (alvo: {os}). \
             Aponte {LIB_DIR_ENV} para uma pasta com libghostty-vt.a."
        )
        .into());
    }

    // Fora do OUT_DIR para não baixar de novo a cada perfil (debug, release,
    // clippy). O cargo não diz ao script onde fica o target; o
    // `CARGO_TARGET_DIR` do ambiente vale quando existe, e o padrão é
    // `rust/target/`, que já está no .gitignore.
    let workspace = Path::new(&env::var("CARGO_MANIFEST_DIR")?).join("../..");
    let target = match env::var_os("CARGO_TARGET_DIR") {
        Some(dir) => workspace.join(dir),
        None => workspace.join("target"),
    };
    let cache = target.join("libghostty-vt").join(VERSION);
    fs::create_dir_all(&cache)?;

    let lib_dir = cache.join("lib");
    let lib = lib_dir.join("libghostty-vt.a");
    // Sem isto, apagar o cache deixa o cargo achando que nada mudou, e o erro
    // só aparece no link.
    println!("cargo:rerun-if-changed={}", lib.display());
    if lib.exists() && sha256(&lib)? == APPLE_LIB_SHA256 {
        return Ok(lib_dir);
    }

    let name = format!("ghostty-vt-{VERSION}.xcframework.zip");
    let zip_path = cache.join(&name);
    if !zip_path.exists() || sha256(&zip_path)? != APPLE_SHA256 {
        download(&format!("{BASE_URL}/{VERSION}/{name}"), &zip_path)?;
    }
    check(&zip_path, APPLE_SHA256)?;
    fs::create_dir_all(&lib_dir)?;
    extract(&zip_path, APPLE_LIB_IN_ZIP, &lib)?;
    check(&lib, APPLE_LIB_SHA256)?;
    Ok(lib_dir)
}

/// Arquivo que não confere é apagado: o próximo build baixa de novo em vez de
/// tropeçar no mesmo lixo.
fn check(path: &Path, want: &str) -> Res<()> {
    let got = sha256(path)?;
    if got != want {
        fs::remove_file(path)?;
        return Err(format!("{}: sha256 {got}, esperado {want}", path.display()).into());
    }
    Ok(())
}

/// Nome temporário por processo: dois `cargo` na mesma árvore (teste e clippy
/// ao mesmo tempo) não escrevem no mesmo arquivo.
fn partial(dest: &Path) -> PathBuf {
    dest.with_extension(format!("part-{}", std::process::id()))
}

fn download(url: &str, dest: &Path) -> Res<()> {
    let part = partial(dest);
    let status = Command::new("curl")
        .args([
            "--fail",
            "--silent",
            "--show-error",
            "--location",
            "--retry",
            "2",
        ])
        .arg("--output")
        .arg(&part)
        .arg(url)
        .status()
        .map_err(|e| format!("curl não rodou ({e}); baixe {url} ou use {LIB_DIR_ENV}"))?;
    if !status.success() {
        let _ = fs::remove_file(&part);
        return Err(format!("curl {url} saiu com {status}; sem rede, use {LIB_DIR_ENV}").into());
    }
    fs::rename(&part, dest)?;
    Ok(())
}

fn sha256(path: &Path) -> Res<String> {
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 1 << 16];
    loop {
        let n = file.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hasher
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect())
}

fn extract(zip_path: &Path, entry: &str, dest: &Path) -> Res<()> {
    let mut archive = zip::ZipArchive::new(File::open(zip_path)?)?;
    let mut file = archive.by_name(entry)?;
    let part = partial(dest);
    io::copy(&mut file, &mut File::create(&part)?)?;
    fs::rename(&part, dest)?;
    Ok(())
}
