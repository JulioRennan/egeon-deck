//! Texto de caminho como o Foundation o trata no Swift (`~`, barra final,
//! `..`), sem perguntar ao disco.
//!
//! O HOME entra como parâmetro: o teste não depende do processo e o core não
//! lê o ambiente aqui.

/// `~` e `~/x` viram o HOME; qualquer outra coisa fica como veio (`~outro` não
/// é expandido — o Swift o expandiria pelo diretório do usuário `outro`, o que
/// nenhum arquivo de `~/.egeon` usa).
pub fn expand_tilde(path: &str, home: &str) -> String {
    if path == "~" {
        return home.to_owned();
    }
    match path.strip_prefix("~/") {
        Some(rest) => format!("{}/{rest}", home.trim_end_matches('/')),
        None => path.to_owned(),
    }
}

/// O inverso de [`expand_tilde`]: o que está dentro do HOME volta a começar por
/// `~`.
pub fn abbreviate_tilde(path: &str, home: &str) -> String {
    let home = home.trim_end_matches('/');
    if home.is_empty() {
        return path.to_owned();
    }
    if path == home {
        return "~".to_owned();
    }
    match path.strip_prefix(home) {
        Some(rest) if rest.starts_with('/') => format!("~{rest}"),
        _ => path.to_owned(),
    }
}

/// Compara como o disco compara: `~` expandido e sem barra no fim. É o que
/// deixa `~/Documents/deck` e `/Users/x/Documents/deck/` serem o mesmo projeto.
pub fn normalize(path: &str, home: &str) -> String {
    let mut p = expand_tilde(path, home);
    while p.chars().count() > 1 && p.ends_with('/') {
        p.pop();
    }
    p
}

/// O último componente, como o `URL.lastPathComponent`: ignora a barra final,
/// e a raiz é `/`.
pub fn last_component(path: &str) -> String {
    let trimmed = path.trim_end_matches('/');
    if trimmed.is_empty() {
        return if path.is_empty() {
            String::new()
        } else {
            "/".to_owned()
        };
    }
    trimmed.rsplit('/').next().unwrap_or(trimmed).to_owned()
}

/// Resolve `.` e `..` só pelo texto — o `URL.standardized` do Swift. Previsível
/// a partir do que está escrito, sem depender de symlink (ADR-017).
pub fn standardize(path: &str) -> String {
    let absolute = path.starts_with('/');
    let mut parts: Vec<&str> = Vec::new();
    for segment in path.split('/') {
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
    let joined = parts.join("/");
    if absolute {
        format!("/{joined}")
    } else {
        joined
    }
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
    fn standardize_resolve_pontos_pelo_texto() {
        assert_eq!(standardize("/repos/deck/../vizinho"), "/repos/vizinho");
        assert_eq!(standardize("/repos/./deck//api"), "/repos/deck/api");
        assert_eq!(standardize("/.."), "/");
        assert_eq!(standardize("a/../../b"), "../b");
    }
}
