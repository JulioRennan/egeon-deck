//! Texto de caminho como o Foundation o trata no Swift (`~`, barra final,
//! `..`), sem perguntar ao disco.
//!
//! O HOME entra como parâmetro: o teste não depende do processo e o core não
//! lê o ambiente aqui.

/// Separador de caminho do sistema: só `/` no unix; `/` e `\` no Windows
/// (pela biblioteca padrão, sem `cfg` aqui).
pub fn is_separator(c: char) -> bool {
    std::path::is_separator(c)
}

/// A barra com que `path` está escrito: as junções seguem o estilo de quem já
/// está lá (`C:\Users\eu` continua com `\`, `/h` com `/`); sem nenhuma, a do
/// sistema.
pub fn style(path: &str) -> char {
    path.chars()
        .find(|&c| is_separator(c))
        .unwrap_or(std::path::MAIN_SEPARATOR)
}

/// A unidade do Windows no começo (`C:`), que não é um componente: o `..` não
/// sobe acima dela. Vazio no unix, onde `C:` é um nome como outro qualquer.
fn drive(path: &str) -> &str {
    let bytes = path.as_bytes();
    let windows = std::path::MAIN_SEPARATOR == '\\';
    if windows && bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':' {
        &path[..2]
    } else {
        ""
    }
}

/// Caminho a partir da raiz: `/x` no unix; `C:\x`, `\x` ou `/x` no Windows.
pub fn is_absolute(path: &str) -> bool {
    path[drive(path).len()..].starts_with(is_separator)
}

/// `base` + `rest` com uma barra só entre os dois, no estilo de `base`.
pub fn join(base: &str, rest: &str) -> String {
    format!(
        "{}{}{rest}",
        base.trim_end_matches(is_separator),
        style(base)
    )
}

/// O que vem depois de `root` quando `path` está dentro dela (`None` se não
/// está, ou se é a própria `root`). Sem barra no começo do resto.
pub fn inside<'a>(path: &'a str, root: &str) -> Option<&'a str> {
    let rest = path.strip_prefix(root.trim_end_matches(is_separator))?;
    let rest = rest.strip_prefix(is_separator)?;
    Some(rest)
}

/// Um caminho como o git o escreve: no Windows ele usa `/` (`C:/Users/eu`),
/// que aqui volta à barra do sistema para casar com o resto. No unix fica
/// como veio.
pub fn from_git(path: &str) -> String {
    if std::path::MAIN_SEPARATOR == '/' {
        path.to_owned()
    } else {
        path.replace('/', std::path::MAIN_SEPARATOR_STR)
    }
}

/// O inverso de [`from_git`]: o caminho com `/`, para quem lê `\` como
/// escape — o Git Bash do Windows, ao montar os argumentos. No unix fica como
/// veio.
pub fn with_slashes(path: &str) -> String {
    if std::path::MAIN_SEPARATOR == '/' {
        path.to_owned()
    } else {
        path.replace(std::path::MAIN_SEPARATOR, "/")
    }
}

/// `~` e `~/x` viram o HOME; qualquer outra coisa fica como veio (`~outro` não
/// é expandido — o Swift o expandiria pelo diretório do usuário `outro`, o que
/// nenhum arquivo de `~/.egeon` usa).
pub fn expand_tilde(path: &str, home: &str) -> String {
    if path == "~" {
        return home.to_owned();
    }
    match path
        .strip_prefix('~')
        .and_then(|p| p.strip_prefix(is_separator))
    {
        Some(rest) => join(home, rest),
        None => path.to_owned(),
    }
}

/// O inverso de [`expand_tilde`]: o que está dentro do HOME volta a começar por
/// `~`.
pub fn abbreviate_tilde(path: &str, home: &str) -> String {
    let home = home.trim_end_matches(is_separator);
    if home.is_empty() {
        return path.to_owned();
    }
    if path == home {
        return "~".to_owned();
    }
    match path.strip_prefix(home) {
        Some(rest) if rest.starts_with(is_separator) => format!("~{rest}"),
        _ => path.to_owned(),
    }
}

/// Compara como o disco compara: `~` expandido e sem barra no fim. É o que
/// deixa `~/Documents/deck` e `/Users/x/Documents/deck/` serem o mesmo projeto.
pub fn normalize(path: &str, home: &str) -> String {
    let mut p = expand_tilde(path, home);
    // A barra da raiz fica: `/`, e no Windows o `C:\\` (sem ela, `C:` é a pasta
    // atual daquela unidade).
    let keep = drive(&p).len() + 1;
    while p.chars().count() > keep.max(1) && p.ends_with(is_separator) {
        p.pop();
    }
    p
}

/// O último componente, como o `URL.lastPathComponent`: ignora a barra final,
/// e a raiz é `/`.
pub fn last_component(path: &str) -> String {
    let trimmed = path.trim_end_matches(is_separator);
    if trimmed.is_empty() {
        return if path.is_empty() {
            String::new()
        } else {
            "/".to_owned()
        };
    }
    trimmed
        .rsplit(is_separator)
        .next()
        .unwrap_or(trimmed)
        .to_owned()
}

/// Resolve `.` e `..` só pelo texto — o `URL.standardized` do Swift. Previsível
/// a partir do que está escrito, sem depender de symlink (ADR-017).
pub fn standardize(path: &str) -> String {
    let drive = drive(path);
    let body = &path[drive.len()..];
    let absolute = body.starts_with(is_separator);
    let mut parts: Vec<&str> = Vec::new();
    for segment in body.split(is_separator) {
        match segment {
            "" | "." => {}
            ".." => match parts.last() {
                Some(&last) if last != ".." => {
                    parts.pop();
                }
                _ if absolute => {}
                _ => parts.push(".."),
            },
            other => parts.push(other),
        }
    }
    let sep = style(path);
    let joined = parts.join(&sep.to_string());
    if absolute {
        format!("{drive}{sep}{joined}")
    } else {
        format!("{drive}{joined}")
    }
}

/// O caminho dos testes, escrito com `/`, na barra do sistema: é como o core
/// monta os caminhos que junta.
#[cfg(test)]
pub fn native(path: &str) -> String {
    from_git(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn til_expande_e_abrevia() {
        assert_eq!(expand_tilde("~", "/h"), "/h");
        assert_eq!(expand_tilde("~/a/b", "/h"), "/h/a/b");
        assert_eq!(expand_tilde("/x/~/y", "/h"), "/x/~/y");
        assert_eq!(expand_tilde("~outro/a", "/h"), "~outro/a");
        assert_eq!(abbreviate_tilde("/h/a/b", "/h"), "~/a/b");
        assert_eq!(abbreviate_tilde("/h", "/h"), "~");
        assert_eq!(abbreviate_tilde("/hx/a", "/h"), "/hx/a");
    }

    #[test]
    fn normaliza_sem_barra_final() {
        assert_eq!(normalize("~/repos/deck/", "/h"), "/h/repos/deck");
        assert_eq!(normalize("/", "/h"), "/");
        assert_eq!(normalize("/a//", "/h"), "/a");
    }

    #[test]
    fn ultimo_componente_como_a_url() {
        assert_eq!(last_component("/repos/deck"), "deck");
        assert_eq!(last_component("/repos/deck/"), "deck");
        assert_eq!(last_component("deck"), "deck");
        assert_eq!(last_component("/"), "/");
    }

    #[test]
    fn dentro_e_juncao_com_uma_barra_so() {
        assert_eq!(inside("/r/app/src", "/r/app"), Some("src"));
        assert_eq!(inside("/r/app/src", "/r/app/"), Some("src"));
        assert_eq!(inside("/r/app", "/r/app"), None);
        assert_eq!(inside("/r/apps", "/r/app"), None);
        assert_eq!(join("/r/app/", "src"), "/r/app/src");
        assert!(is_absolute("/r"));
        assert!(!is_absolute("r/s"));
        assert!(!is_absolute("~/r"));
    }

    /// O mesmo texto com as barras do Windows: só lá `\` é separador.
    #[test]
    fn barras_do_windows_onde_o_sistema_as_aceita() {
        if std::path::MAIN_SEPARATOR != '\\' {
            return;
        }
        let home = r"C:\Users\eu";
        assert_eq!(expand_tilde("~/a", home), r"C:\Users\eu\a");
        assert_eq!(abbreviate_tilde(r"C:\Users\eu\a\b", home), r"~\a\b");
        assert_eq!(normalize(r"C:\Users\eu\deck\", home), r"C:\Users\eu\deck");
        assert_eq!(normalize(r"C:\", home), r"C:\");
        assert_eq!(last_component(r"C:\Users\eu\deck"), "deck");
        assert_eq!(standardize(r"C:\r\deck\..\api"), r"C:\r\api");
        assert_eq!(standardize(r"C:\.."), r"C:\");
        assert_eq!(inside(r"C:\r\app\src", r"C:\r\app"), Some("src"));
        assert!(is_absolute(r"C:\r"));
        assert!(!is_absolute(r"C:r"));
    }

    #[test]
    fn standardize_resolve_pontos_pelo_texto() {
        assert_eq!(standardize("/repos/deck/../vizinho"), "/repos/vizinho");
        assert_eq!(standardize("/repos/./deck//api"), "/repos/deck/api");
        assert_eq!(standardize("/.."), "/");
        assert_eq!(standardize("a/../../b"), "../b");
    }
}
