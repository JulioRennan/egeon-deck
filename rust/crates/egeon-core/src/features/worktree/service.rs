//! As operações de worktree do git: ler o repositório, abrir, apagar. Porte do
//! `Worktree` do Swift.
//!
//! Tudo síncrono, com o [`Git`] e o caminho como parâmetro: o core chama de
//! `spawn_blocking`. Quando um `git worktree remove` leva minutos num
//! `node_modules` grande, quem espera é a tarefa de fundo, nunca o ator.

use std::path::{Path, PathBuf};
use std::time::Duration;

use super::git::Git;
use super::model::{BranchIndex, Created, Failure, Losses, Status, exists, lines};
use crate::commons::ids::BranchName;
use crate::features::path_text;

// ── Leitura ────────────────────────────────────────────────────────────────

pub fn status(git: &Git, path: &str) -> Result<Status, Failure> {
    let dir = Path::new(path);
    let root = git
        .run(&["rev-parse", "--show-toplevel"], dir)?
        .trim()
        .to_owned();
    if root.is_empty() {
        return Err(Failure::NotARepo(path.to_owned()));
    }
    let branch = git
        .run(&["rev-parse", "--abbrev-ref", "HEAD"], dir)?
        .trim()
        .to_owned();
    let dirty = git.run(&["status", "--porcelain", "--untracked-files=no"], dir)?;
    let untracked = lines(&git.run(&["ls-files", "--others", "--exclude-standard"], dir)?);
    Ok(Status {
        repo_root: root,
        branch,
        has_dirty_tracked: !dirty.trim().is_empty(),
        untracked,
    })
}

/// Onde a worktree nasce: `<pai do repo>/worktrees/<repo>/<branch>` — a
/// convenção de `BranchName::suggested_worktree_path`.
///
/// Fora do repositório para não misturar com repositórios de verdade, e fora do
/// diretório do app porque worktree é artefato de git: se o app sumir, o
/// trabalho não deve ficar órfão dentro da config dele. Sem ponto no nome — o
/// Finder esconde pasta que começa com ponto.
pub fn suggested_path(repo_root: &str, branch: &BranchName) -> String {
    branch
        .suggested_worktree_path(Path::new(repo_root))
        .to_string_lossy()
        .into_owned()
}

fn branches(git: &Git, path: &str) -> Vec<String> {
    git.run(
        &["branch", "--format=%(refname:short)", "--list"],
        Path::new(path),
    )
    .map(|out| {
        lines(&out)
            .into_iter()
            .map(|b| b.trim().to_owned())
            .collect()
    })
    .unwrap_or_default()
}

/// Nome livre a partir do atual: `PROJ-1234` → `PROJ-1234-2`, `-3`…
///
/// Sempre deriva um nome novo, e é o contrato certo para quem chama: a branch
/// em que você está agora está tomada por definição.
pub fn available_branch(git: &Git, current: &str, path: &str) -> String {
    let existing = branches(git, path);
    let mut n = 2;
    while existing.iter().any(|b| *b == format!("{current}-{n}")) {
        n += 1;
    }
    format!("{current}-{n}")
}

fn worktree_listing(git: &Git, dir: &str) -> Option<String> {
    git.run(&["worktree", "list", "--porcelain"], Path::new(dir))
        .ok()
}

/// As branches que já estão abertas em alguma worktree que existe, e se algum
/// registro aponta para pasta que sumiu.
fn read_checked_out(git: &Git, repo: &str) -> (std::collections::BTreeMap<String, String>, bool) {
    let mut checked_out = std::collections::BTreeMap::new();
    let mut stale = false;
    let listing = worktree_listing(git, repo).unwrap_or_default();
    let mut path: Option<String> = None;
    for line in lines(&listing) {
        if let Some(p) = line.strip_prefix("worktree ") {
            path = Some(p.to_owned());
        } else if let (Some(branch), Some(path)) = (line.strip_prefix("branch refs/heads/"), &path)
        {
            if exists(path) {
                checked_out.insert(branch.to_owned(), path.clone());
            } else {
                stale = true;
            }
        }
    }
    (checked_out, stale)
}

pub fn index(git: &Git, repo: &str) -> BranchIndex {
    let (mut checked_out, stale) = read_checked_out(git, repo);
    // Pasta apagada à mão deixa o registro do git para trás, e reaproveitá-lo
    // mandaria a bancada para um caminho que não existe. `prune` é idempotente.
    if stale {
        let _ = git.run(&["worktree", "prune"], Path::new(repo));
        checked_out = read_checked_out(git, repo).0;
    }

    let mut remote: std::collections::BTreeMap<String, String> = std::collections::BTreeMap::new();
    let refs = git
        .run(
            &["for-each-ref", "--format=%(refname:short)", "refs/remotes"],
            Path::new(repo),
        )
        .unwrap_or_default();
    for reference in lines(&refs).into_iter().map(|r| r.trim().to_owned()) {
        let Some((_, name)) = reference.split_once('/') else {
            continue;
        };
        // `origin/HEAD` é ponteiro para a branch padrão, não uma branch.
        if name == "HEAD" {
            continue;
        }
        // `origin` ganha de outro remoto com o mesmo nome: é o que se quer sem
        // perguntar, e perguntar aqui seria um diálogo por tecla digitada.
        if !remote.contains_key(name) || reference.starts_with("origin/") {
            remote.insert(name.to_owned(), reference.clone());
        }
    }

    BranchIndex {
        local: branches(git, repo).into_iter().collect(),
        remote,
        checked_out,
    }
}

// ── Criação ────────────────────────────────────────────────────────────────

/// Abre a worktree de `branch` em `destination` — criando-a, ou devolvendo a
/// que já existe.
///
/// Quatro caminhos, e o nome que você escreveu decide qual (ADR-018):
///
/// - branch que não existe → nasce do HEAD da origem;
/// - branch que existe local e está livre → a worktree abre **nela**, no commit
///   dela;
/// - branch que só existe no remoto → nasce local seguindo a ref remota;
/// - branch já aberta em outra worktree → é aquela pasta, e nada é criado.
///
/// O app só sabia criar branch nova, e da recusa do git em ter a mesma branch
/// em dois lugares concluía "escolha outro nome" — quando "já está aberta ali"
/// é justamente a resposta útil.
pub fn create(
    git: &Git,
    repo_path: &str,
    branch: &str,
    destination: &str,
    carry_dirty: bool,
) -> Result<Created, Failure> {
    let status = status(git, repo_path)?;
    let plan = index(git, repo_path).plan(branch);
    let repo = Path::new(repo_path);

    let add: Vec<&str> = match &plan {
        super::model::BranchPlan::AlreadyCheckedOut(existing) => {
            crate::log!(
                "worktree: {branch} já está aberta em {existing} — reaproveitando em vez de criar"
            );
            return Ok(Created {
                path: existing.clone(),
                branch: branch.to_owned(),
                carried_tracked_changes: false,
                reused: true,
            });
        }
        super::model::BranchPlan::New => {
            vec!["worktree", "add", "-b", branch, destination, "HEAD"]
        }
        super::model::BranchPlan::ExistingLocal => vec!["worktree", "add", destination, branch],
        super::model::BranchPlan::Remote(reference) => {
            vec![
                "worktree",
                "add",
                "--track",
                "-b",
                branch,
                destination,
                reference,
            ]
        }
    };

    if exists(destination) {
        return Err(Failure::DestinationExists(destination.to_owned()));
    }

    // Feito ANTES de criar a worktree e sem tocar no working tree de origem:
    // `stash create` só escreve um objeto e devolve o sha. `stash push`
    // reverteria as mudanças do lado de cá, que não é o combinado.
    let mut stash = String::new();
    if carry_dirty && status.has_dirty_tracked {
        stash = git.run(&["stash", "create"], repo)?.trim().to_owned();
    }

    if let Some(parent) = Path::new(destination).parent() {
        std::fs::create_dir_all(parent).map_err(|e| Failure::Git {
            command: format!("mkdir {}", parent.display()),
            output: e.to_string(),
        })?;
    }

    git.run(&add, repo)?;

    // Branch nova sai do HEAD com árvore limpa, e ali o stash não tem com o que
    // conflitar. Branch que já existe tem histórico próprio: aplicar em cima
    // dela pode conflitar, e resolver conflito numa pasta que acabou de nascer
    // não é o que ninguém pediu. O objeto do stash fica criado e o log diz como
    // aplicá-lo à mão — nada se perde por não ter vindo junto.
    if !stash.is_empty() {
        if plan.is_fresh() {
            git.run(&["stash", "apply", &stash], Path::new(destination))?;
        } else {
            crate::log!(
                "worktree: {destination} abriu em {branch}, que tem histórico próprio — as \
                 mudanças não commitadas de {} NÃO vieram. Para levá-las: cd {destination} && \
                 git stash apply {stash}",
                status.branch
            );
            stash.clear();
        }
    }

    crate::log!(
        "worktree: {destination} aberta na branch {branch}{}",
        if stash.is_empty() {
            ""
        } else {
            ", com as mudanças não commitadas"
        }
    );

    Ok(Created {
        path: destination.to_owned(),
        branch: branch.to_owned(),
        carried_tracked_changes: !stash.is_empty(),
        reused: false,
    })
}

// ── Remoção ────────────────────────────────────────────────────────────────

/// Se este caminho é uma worktree ligada, e não o checkout principal.
///
/// Numa worktree ligada o `--git-dir` aponta para
/// `<principal>/.git/worktrees/<nome>`, enquanto o `--git-common-dir` continua
/// sendo `<principal>/.git`. No checkout principal os dois coincidem — é essa
/// diferença que impede oferecer "apagar a worktree" para o repositório de
/// verdade.
pub fn is_linked_worktree(git: &Git, path: &str) -> bool {
    let dir = Path::new(path);
    let (Ok(git_dir), Ok(common)) = (
        git.run(&["rev-parse", "--absolute-git-dir"], dir),
        git.run(
            &["rev-parse", "--path-format=absolute", "--git-common-dir"],
            dir,
        ),
    ) else {
        return false;
    };
    git_dir.trim() != common.trim()
}

/// Caminho do repositório principal. `worktree remove` não roda de dentro da
/// worktree que está sendo removida.
///
/// A primeira entrada de `worktree list` é sempre a principal — é a única forma
/// que vale para os dois layouts. Derivar do `--git-common-dir` cortando o
/// último componente só funciona num clone comum; num repositório bare o
/// common-dir É o próprio repositório.
pub fn main_worktree(git: &Git, path: &str) -> Option<String> {
    let listing = worktree_listing(git, path)?;
    lines(&listing)
        .into_iter()
        .find_map(|line| line.strip_prefix("worktree ").map(str::to_owned))
}

/// A raiz da worktree em que a pasta está (a ligada, se for uma). `None` fora
/// de git. Leve: sem o `status`, que custa num repositório grande.
pub fn top_level(git: &Git, path: &str) -> Option<String> {
    let root = git
        .run(&["rev-parse", "--show-toplevel"], Path::new(path))
        .ok()?;
    let root = root.trim();
    (!root.is_empty()).then(|| root.to_owned())
}

/// De qual repositório uma pasta faz parte, sempre pelo checkout principal.
///
/// `--show-toplevel` devolve a raiz da worktree LIGADA quando você está dentro
/// de uma, e usá-la para criar a próxima aninha worktree dentro de worktree:
/// legal para o git, e um desastre em disco — apagar a de fora leva a de dentro.
pub fn main_repo(git: &Git, path: &str) -> Option<String> {
    let status = status(git, path).ok()?;
    main_worktree(git, path).or(Some(status.repo_root))
}

/// O que desaparece se esta worktree for apagada.
pub fn losses(git: &Git, path: &str) -> Result<Losses, Failure> {
    let dir = Path::new(path);
    let modified = lines(&git.run(&["status", "--porcelain", "--untracked-files=no"], dir)?)
        .into_iter()
        .map(|line| line.chars().skip(3).collect())
        .collect();
    let untracked = lines(&git.run(&["ls-files", "--others", "--exclude-standard"], dir)?);
    // Sem upstream, `@{u}` falha — e aí "não enviado" não é medível, então 0.
    let ahead = git
        .run(&["rev-list", "--count", "@{u}..HEAD"], dir)
        .map(|out| out.trim().to_owned())
        .unwrap_or_else(|_| "0".to_owned());
    Ok(Losses {
        modified,
        untracked,
        unpushed_commits: ahead.parse().unwrap_or(0),
    })
}

/// Apaga a worktree do disco e limpa o registro do git.
///
/// `--force` é necessário na prática: a worktree nasce com as mudanças não
/// commitadas e com os arquivos ignorados copiados, e o git recusa remover uma
/// árvore suja sem ele. Quem chama tem de ter mostrado as perdas antes.
pub fn remove(git: &Git, path: &str) -> Result<(), Failure> {
    let main = main_worktree(git, path).ok_or_else(|| Failure::NotARepo(path.to_owned()))?;
    let main_dir = Path::new(&main);
    match git.run(&["worktree", "remove", "--force", path], main_dir) {
        Ok(_) => {}
        Err(error) => {
            // O git desfaz o REGISTRO da worktree ANTES de terminar de apagar a
            // árvore, e não volta atrás: se ele morre no meio, ela já não existe
            // para o git ("Directory not empty" — alguém criou arquivo durante a
            // remoção: watcher do editor, um `npm run dev` num terminal da
            // bancada, o Finder escrevendo .DS_Store — ou "Permission denied").
            //
            // O que sobrava era o pior dos mundos: pasta meio apagada, um alerta
            // segurando a bancada e, na segunda tentativa, uma pasta que já não
            // é worktree nenhuma. Terminar de apagar é o que você pediu.
            let registered = is_registered(git, path, &main);
            if finish_removal(path, registered, 5)? {
                let _ = git.run(&["worktree", "prune"], main_dir);
                crate::log!(
                    "worktree: git parou no meio de {path} ({error}) — o registro já tinha ido, \
                     a pasta foi apagada pelo app"
                );
                return Ok(());
            }
            return Err(error);
        }
    }
    // Registro órfão sobra quando a pasta já tinha sido apagada à mão.
    let _ = git.run(&["worktree", "prune"], main_dir);
    crate::log!("worktree: {path} removida do disco");
    Ok(())
}

/// Resolve os symlinks do que existe do caminho, e deixa o resto como está —
/// o `resolvingSymlinksInPath`, que também vale para pasta já apagada.
fn resolved(path: &str) -> PathBuf {
    let mut rest: Vec<std::ffi::OsString> = Vec::new();
    let mut head = PathBuf::from(path);
    loop {
        if let Ok(real) = std::fs::canonicalize(&head) {
            return rest.iter().rev().fold(real, |acc, part| acc.join(part));
        }
        match (
            head.file_name().map(|n| n.to_owned()),
            head.parent().map(Path::to_owned),
        ) {
            (Some(name), Some(parent)) => {
                rest.push(name);
                head = parent;
            }
            _ => return PathBuf::from(path_text::standardize(path)),
        }
    }
}

/// Este caminho ainda é uma worktree registrada em `main`?
///
/// Pelo `worktree list` do repositório, e não por `rev-parse` dentro da pasta:
/// no estado que importa aqui a pasta já não responde como git. Compara
/// caminhos resolvidos: em macOS o temporário é `/var/…` de um lado e
/// `/private/var/…` do outro.
pub fn is_registered(git: &Git, path: &str, main: &str) -> bool {
    let Some(listing) = worktree_listing(git, main) else {
        return false;
    };
    let target = resolved(path);
    lines(&listing)
        .iter()
        .filter_map(|line| line.strip_prefix("worktree "))
        .any(|listed| resolved(listed) == target)
}

/// A faxina depois de o git desistir no meio. Devolve se ela foi feita —
/// `false` quando a worktree ainda está registrada, e aí o erro do git é
/// legítimo e tem de subir.
///
/// Com tentativas porque quem derrubou o git derruba a remoção pelo mesmo
/// motivo: um arquivo que nasce dentro da pasta no meio dela. O escritor é um
/// watcher ou um processo que acabou de levar SIGTERM — ele se cala em seguida,
/// e insistir por um segundo separa "apagou" de "deixou lixo no disco".
pub fn finish_removal(path: &str, registered: bool, attempts: u32) -> Result<bool, Failure> {
    if registered {
        return Ok(false);
    }
    let attempts = attempts.max(1);
    let mut last: Option<std::io::Error> = None;
    for attempt in 1..=attempts {
        if !Path::new(path).exists() {
            return Ok(true);
        }
        match std::fs::remove_dir_all(path) {
            Ok(()) => return Ok(true),
            Err(error) => {
                last = Some(error);
                if attempt < attempts {
                    std::thread::sleep(Duration::from_millis(200));
                }
            }
        }
    }
    Err(Failure::Leftovers {
        path: path.to_owned(),
        reason: last.map_or_else(|| "motivo desconhecido".to_owned(), |e| e.to_string()),
    })
}

/// A branch continua existindo depois de remover a worktree — o trabalho
/// commitado não se perde. Apagar é decisão separada.
pub fn branch_of(git: &Git, path: &str) -> Option<String> {
    git.run(&["rev-parse", "--abbrev-ref", "HEAD"], Path::new(path))
        .ok()
        .map(|b| b.trim().to_owned())
}
