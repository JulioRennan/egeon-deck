//! Tudo que é do Claude Code: perfil de fábrica, ganchos, skills, confiança,
//! transcript, uso e o catálogo lido do binário.

pub mod binary_source;
pub mod catalog;
pub mod command_registry;
pub mod hooks;
pub mod model_registry;
pub mod profile;
pub mod skill;
pub mod slash_catalog;
pub mod transcript;
pub mod trust;
pub mod trust_seeder;
pub mod usage;

use regex::Regex;

/// Expressão regular de padrão literal do código. O padrão é constante e os
/// testes o compilam, então não há entrada que a faça falhar; a regra de não ter
/// `unwrap` em caminho normal não se aplica a uma constante.
#[allow(clippy::unwrap_used)]
pub(crate) fn regex(pattern: &str) -> Regex {
    Regex::new(pattern).unwrap()
}

/// Bytes como texto Latin-1, que é como o binário (JavaScript minificado) é
/// lido: cada byte vira um caractere, nada se perde.
pub(crate) fn latin1(bytes: &[u8]) -> String {
    bytes.iter().map(|b| char::from(*b)).collect()
}

/// A primeira ocorrência de `needle` em `data[from..]`, como posição absoluta.
pub(crate) fn find(data: &[u8], needle: &[u8], from: usize) -> Option<usize> {
    if from >= data.len() {
        return None;
    }
    memchr::memmem::find(&data[from..], needle).map(|at| from + at)
}

/// Grava trocando o arquivo de uma vez (`atomically: true` do Swift): quem lê no
/// meio — o `claude` lendo os ganchos, um app novo lendo o `skills/` — nunca vê
/// metade. O arquivo temporário fica ao lado, para o `rename` ficar no mesmo
/// disco.
pub(crate) fn write_atomic(path: &std::path::Path, bytes: &[u8]) -> std::io::Result<()> {
    let mut tmp = path.as_os_str().to_owned();
    tmp.push(".tmp");
    let tmp = std::path::PathBuf::from(tmp);
    let written = std::fs::write(&tmp, bytes).and_then(|()| std::fs::rename(&tmp, path));
    if written.is_err() {
        let _ = std::fs::remove_file(&tmp);
    }
    written
}
