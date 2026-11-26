//! Traz o libghostty-vt do projeto Ghostty e o liga estático (decisões 14 e 52
//! de `docs/migracao/3-proposta.html`): no macOS, o binário oficial; no Linux,
//! que não tem binário oficial, compilado aqui do tarball de fonte com Zig.
//!
//! A origem é fixa: versão, URLs e sha256 abaixo, tirados do `SHA256SUMS`
//! publicado com a versão. O que foi baixado é conferido toda vez que este
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
/// `libghostty-vt-1.0.1.tar.gz` e `-deps.tar.gz` em `SHA256SUMS` da 1.0.1: o
/// fonte e os pacotes Zig de que ele precisa, para compilar sem rede.
const SOURCE_SHA256: &str = "333dfce97641ef9b536bb9e08907ad86abaaada50e8f7417b70d9284adef37aa";
const DEPS_SHA256: &str = "91a4e10960a52bf5bf4b15aa2a2cddaff8a89d6cd903d3055bda4fd17de3356d";
/// O `minimum_zig_version` do `build.zig.zon` da 1.0.1. O build do Ghostty
/// aceita qualquer 0.17.x; aqui é a exata, para dois builds darem o mesmo `.a`.
const ZIG_VERSION: &str = "0.17.0";
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
    match env::var("CARGO_CFG_TARGET_OS")?.as_str() {
        "macos" => apple_lib(&cache_dir()?),
        "linux" => linux_lib(&cache_dir()?),
        os => Err(format!(
            "libghostty-vt {VERSION}: sem receita para o alvo {os}. \
             Aponte {LIB_DIR_ENV} para uma pasta com libghostty-vt.a."
        )
        .into()),
    }
}

fn cache_dir() -> Res<PathBuf> {
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
    Ok(cache)
}

fn apple_lib(cache: &Path) -> Res<PathBuf> {
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

/// Compila do tarball de fonte, como o `PACKAGING-LIBGHOSTTY.md` da versão
/// manda: com os pacotes do tarball de dependências e sem rede.
///
/// O `.a` compilado não é reprodutível byte a byte entre máquinas, então não há
/// sha256 dele para fixar: o carimbo ao lado guarda o sha256 de quando foi
/// feito aqui, e é ele que pega o cache mexido.
fn linux_lib(cache: &Path) -> Res<PathBuf> {
    let arch = env::var("CARGO_CFG_TARGET_ARCH")?;
    let target = format!("{arch}-linux-gnu");
    let lib_dir = cache
        .join(format!("{target}-zig-{ZIG_VERSION}"))
        .join("lib");
    let lib = lib_dir.join("libghostty-vt.a");
    let stamp = lib_dir.join("libghostty-vt.a.sha256");
    println!("cargo:rerun-if-changed={}", lib.display());
    if lib.exists() && fs::read_to_string(&stamp).ok() == Some(sha256(&lib)?) {
        return Ok(lib_dir);
    }

    check_zig()?;
    let source = fetch(
        cache,
        &format!("libghostty-vt-{VERSION}.tar.gz"),
        SOURCE_SHA256,
    )?;
    let deps = fetch(
        cache,
        &format!("libghostty-vt-{VERSION}-deps.tar.gz"),
        DEPS_SHA256,
    )?;

    // Tudo do build numa pasta do processo: dois `cargo` ao mesmo tempo não
    // compilam um por cima do outro, e o que sobrar de um build interrompido
    // não entra no seguinte.
    let work = partial(&cache.join(format!("build-{target}")));
    let _ = fs::remove_dir_all(&work);
    fs::create_dir_all(&work)?;
    let built = build_from_source(&work, &source, &deps, &target);
    let result = built.and_then(|built| {
        fs::create_dir_all(&lib_dir)?;
        let part = partial(&lib);
        fs::copy(&built, &part)?;
        fs::rename(&part, &lib)?;
        fs::write(&stamp, sha256(&lib)?)?;
        Ok(lib_dir)
    });
    let _ = fs::remove_dir_all(&work);
    result
}

fn build_from_source(work: &Path, source: &Path, deps: &Path, target: &str) -> Res<PathBuf> {
    for tarball in [source, deps] {
        run(Command::new("tar")
            .arg("-xzf")
            .arg(tarball)
            .arg("-C")
            .arg(work))?;
    }
    let source_dir = work.join(format!("libghostty-vt-{VERSION}"));
    let prefix = work.join("prefix");
    // Cache global novo e vazio: com o Zig 0.17, um cache que já tem o arquivo
    // de um pacote pode derrubar o build com "reached unreachable code"
    // (PACKAGING-LIBGHOSTTY.md).
    let zig_cache = work.join("zig-cache");
    run(Command::new("zig")
        .current_dir(&source_dir)
        .env("ZIG_GLOBAL_CACHE_DIR", &zig_cache)
        // O build do Ghostty tira a versão do `git` da pasta do fonte. Extraído
        // dentro do `target/`, o fonte cai no repositório do Egeon, e uma tag
        // nossa no HEAD (v2.0.0-alpha.1) derruba o build ("tagged releases
        // must be in vX.Y.Z format matching build.zig"). Sem repositório, ele
        // usa a versão do tarball, como no build de pacote.
        .env("GIT_CEILING_DIRECTORIES", work)
        .env("GIT_DIR", source_dir.join(".git-inexistente"))
        .arg("build")
        .arg("--prefix")
        .arg(&prefix)
        .arg("--system")
        .arg(work.join(format!("libghostty-vt-{VERSION}-deps")))
        .arg(format!("-Dtarget={target}"))
        // Sem isto o `.a` usaria as instruções da máquina que compilou, e o
        // AppImage cairia num processador mais velho.
        .arg("-Dcpu=baseline")
        .arg("-Doptimize=ReleaseFast"))?;
    Ok(prefix.join("lib").join("libghostty-vt.a"))
}

fn check_zig() -> Res<()> {
    let output = Command::new("zig").arg("version").output().map_err(|e| {
        format!("zig não rodou ({e}); instale o Zig {ZIG_VERSION} ou use {LIB_DIR_ENV}")
    })?;
    let found = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if found != ZIG_VERSION {
        return Err(format!(
            "libghostty-vt {VERSION} é compilado com Zig {ZIG_VERSION}; o zig do PATH é {found:?}"
        )
        .into());
    }
    Ok(())
}

/// O tarball conferido no cache, baixado se faltar ou não conferir.
fn fetch(cache: &Path, name: &str, want: &str) -> Res<PathBuf> {
    let path = cache.join(name);
    if !path.exists() || sha256(&path)? != want {
        download(&format!("{BASE_URL}/{VERSION}/{name}"), &path)?;
    }
    check(&path, want)?;
    Ok(path)
}

/// Roda e, se falhar, devolve o fim do que a ferramenta disse: o cargo só
/// mostra a saída do script quando ele falha.
fn run(command: &mut Command) -> Res<()> {
    let output = command
        .output()
        .map_err(|e| format!("{:?} não rodou: {e}", command.get_program()))?;
    if output.status.success() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&output.stderr);
    let tail: Vec<&str> = stderr.lines().rev().take(40).collect();
    let tail: Vec<&str> = tail.into_iter().rev().collect();
    Err(format!(
        "{:?} saiu com {}:\n{}",
        command.get_program(),
        output.status,
        tail.join("\n")
    )
    .into())
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
