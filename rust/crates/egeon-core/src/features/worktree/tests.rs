//! Porte do WorktreeRemoveTests, UnversionedCopyTests e da parte de worktree do
//! NodeWorktreeTests, com git de verdade em repositórios temporários — mais os
//! caminhos de `create` que o Swift só verificava a olho (ADR-018).

use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use super::copy;
use super::duplicate::{self, Target};
use super::form;
use super::from_folder;
use super::git::Git;
use super::merge;
use super::model::{BranchPlan, Failure};
use super::node::{self, NodeWorktree};
use super::routes::{OrgSnapshot, WorktreeEffect};
use super::service;
use crate::commons::ids::BranchName;
use crate::features::node::model::{NodeConfig, NodeKind};
use crate::features::path_text;
use crate::features::workbench::model::WorkbenchConfig;
use crate::features::workbench::model::WorkbenchTemplate;
use crate::features::workspace::model::{ProjectConfig, WorkspaceConfig};
use crate::ports::file_clone::FileCloner;

/// O ambiente do processo sem as variáveis do git: um `GIT_DIR` herdado de um
/// gancho mandaria o teste mexer no repositório de quem o rodou.
fn git() -> Git {
    Git::new(
        std::env::vars_os()
            .filter(|(k, _)| !k.to_string_lossy().starts_with("GIT_"))
            .collect(),
    )
}

struct Sandbox {
    dir: tempfile::TempDir,
}

impl Sandbox {
    fn new() -> Sandbox {
        Sandbox {
            dir: tempfile::tempdir().unwrap(),
        }
    }

    /// O caminho real (sem symlink): `/var/…` e `/private/var/…` do macOS são a
    /// mesma pasta, e o git sempre devolve a segunda.
    fn root(&self) -> PathBuf {
        fs::canonicalize(self.dir.path()).unwrap()
    }

    fn path(&self, rel: &str) -> String {
        self.root().join(rel).to_string_lossy().into_owned()
    }

    /// O HOME do teste: a raiz, sem barra no fim (como o `NSHomeDirectory`).
    fn home(&self) -> String {
        self.root().to_string_lossy().into_owned()
    }

    fn git(&self, args: &[&str], dir: &str) -> String {
        git()
            .run(args, Path::new(dir))
            .unwrap_or_else(|e| panic!("{e}"))
    }

    /// Repositório com um commit (`a.txt`).
    fn repo(&self, name: &str) -> String {
        let repo = self.path(name);
        fs::create_dir_all(&repo).unwrap();
        self.git(&["init", "-q", "-b", "main", "."], &repo);
        self.git(&["config", "user.email", "teste@egeon"], &repo);
        self.git(&["config", "user.name", "teste"], &repo);
        fs::write(Path::new(&repo).join("a.txt"), "a").unwrap();
        self.git(&["add", "-A"], &repo);
        self.git(&["commit", "-qm", "init"], &repo);
        repo
    }

    /// Repositório com uma worktree aberta em `feat`.
    fn repo_with_worktree(&self) -> (String, String) {
        let repo = self.repo("repo");
        let worktree = self.path("wts/feat");
        self.git(&["worktree", "add", "-b", "feat", &worktree], &repo);
        (repo, worktree)
    }
}

fn branch(name: &str) -> BranchName {
    BranchName::new(name).unwrap()
}

// ── Leitura ────────────────────────────────────────────────────────────────

#[test]
fn status_le_a_raiz_a_branch_e_a_sujeira() {
    let s = Sandbox::new();
    let repo = s.repo("repo");
    let clean = service::status(&git(), &repo).unwrap();
    assert_eq!(clean.repo_root, repo);
    assert_eq!(clean.branch, "main");
    assert!(!clean.is_dirty());

    fs::write(Path::new(&repo).join("a.txt"), "mudou").unwrap();
    fs::write(Path::new(&repo).join("novo.txt"), "x").unwrap();
    let dirty = service::status(&git(), &repo).unwrap();
    assert!(dirty.has_dirty_tracked);
    assert_eq!(dirty.untracked, ["novo.txt"]);
    assert!(dirty.is_dirty());
}

#[test]
fn pasta_fora_de_git_nao_e_repositorio() {
    let s = Sandbox::new();
    let plain = s.path("solta");
    fs::create_dir_all(&plain).unwrap();
    assert!(service::status(&git(), &plain).is_err());
    assert_eq!(service::main_repo(&git(), &plain), None);
    assert_eq!(service::top_level(&git(), &plain), None);
    assert!(service::main_worktree(&git(), &plain).is_none());
    assert!(!service::is_linked_worktree(&git(), &plain));
    // Pasta que nem existe: o git nem roda, e o erro diz onde.
    assert!(matches!(
        service::status(&git(), "/nao/existe/mesmo"),
        Err(Failure::Git { .. })
    ));
}

#[test]
fn caminho_sugerido_fica_fora_do_repo_e_com_a_branch_achatada() {
    assert_eq!(
        service::suggested_path("/Users/eu/code/deck", &branch("feature/PROJ-1")),
        "/Users/eu/code/worktrees/deck/feature-PROJ-1"
    );
}

#[test]
fn nome_de_branch_livre_deriva_um_novo() {
    let s = Sandbox::new();
    let repo = s.repo("repo");
    assert_eq!(service::available_branch(&git(), "main", &repo), "main-2");
    s.git(&["branch", "main-2"], &repo);
    s.git(&["branch", "main-3"], &repo);
    assert_eq!(service::available_branch(&git(), "main", &repo), "main-4");
}

// ── Os quatro destinos de um nome de branch (ADR-018) ──────────────────────

#[test]
fn o_indice_diz_o_destino_de_cada_nome() {
    let s = Sandbox::new();
    let (repo, worktree) = s.repo_with_worktree();
    s.git(&["branch", "local-livre"], &repo);

    // Um remoto com uma branch que não existe local, e o `origin/HEAD`.
    let remote = s.path("remoto.git");
    s.git(&["init", "-q", "--bare", &remote], &s.home());
    s.git(&["remote", "add", "origin", &remote], &repo);
    s.git(
        &["push", "-q", "origin", "main:so-remota", "main:main"],
        &repo,
    );
    s.git(&["fetch", "-q", "origin"], &repo);
    s.git(&["remote", "set-head", "origin", "main"], &repo);

    let index = service::index(&git(), &repo);
    assert_eq!(index.plan("feat"), BranchPlan::AlreadyCheckedOut(worktree));
    assert_eq!(index.plan("local-livre"), BranchPlan::ExistingLocal);
    assert_eq!(
        index.plan("so-remota"),
        BranchPlan::Remote("origin/so-remota".to_owned())
    );
    assert_eq!(index.plan("nunca-vista"), BranchPlan::New);
    assert!(
        !index.remote.contains_key("HEAD"),
        "origin/HEAD não é uma branch"
    );
    // `main` existe local E remoto: local ganha; está aberta no checkout principal.
    assert_eq!(index.plan("main"), BranchPlan::AlreadyCheckedOut(repo));
}

#[test]
fn registro_de_pasta_apagada_a_mao_e_podado_ao_ler() {
    let s = Sandbox::new();
    let (repo, worktree) = s.repo_with_worktree();
    fs::remove_dir_all(&worktree).unwrap();
    // Reaproveitar o registro mandaria a bancada para um caminho que não existe.
    assert_eq!(
        service::index(&git(), &repo).plan("feat"),
        BranchPlan::ExistingLocal
    );
}

#[test]
fn as_frases_de_cada_destino() {
    let home = "/Users/eu";
    assert_eq!(
        BranchPlan::New.summary("main", true, home),
        "Branch nova · sai de main, no commit atual. As mudanças não commitadas vão junto."
    );
    assert_eq!(
        BranchPlan::New.summary("main", false, home),
        "Branch nova · sai de main, no commit atual."
    );
    assert_eq!(
        BranchPlan::ExistingLocal.summary("main", true, home),
        "Esta branch já existe · a worktree abre nela, no commit dela. As mudanças não \
         commitadas de main ficam onde estão."
    );
    assert_eq!(
        BranchPlan::Remote("origin/x".into()).summary("main", false, home),
        "Só existe em origin/x · a branch local nasce seguindo o remoto."
    );
    let open = BranchPlan::AlreadyCheckedOut("/Users/eu/wts/x".into());
    assert_eq!(
        open.summary("main", false, home),
        "Já está aberta em ~/wts/x · nada é criado, e é essa pasta que vai ser usada."
    );
    assert_eq!(open.short(home), "já aberta em ~/wts/x");
    assert_eq!(BranchPlan::New.short(home), "branch nova");
    assert_eq!(
        BranchPlan::ExistingLocal.short(home),
        "abre na branch que já existe"
    );
    assert_eq!(
        BranchPlan::Remote("origin/x".into()).short(home),
        "nasce seguindo origin/x"
    );
    assert!(BranchPlan::New.is_fresh() && !BranchPlan::ExistingLocal.is_fresh());
}

#[test]
fn branch_nova_nasce_do_head_e_leva_as_mudancas_nao_commitadas() {
    let s = Sandbox::new();
    let repo = s.repo("repo");
    fs::write(Path::new(&repo).join("a.txt"), "mudou").unwrap();
    let dest = service::suggested_path(&repo, &branch("feature/x"));

    let created = service::create(&git(), &repo, "feature/x", &dest, true).unwrap();
    assert_eq!(created.path, dest);
    assert!(created.carried_tracked_changes && !created.reused);
    assert_eq!(
        fs::read_to_string(Path::new(&dest).join("a.txt")).unwrap(),
        "mudou"
    );
    // `stash create` não toca no lado de cá: a mudança continua na origem.
    assert_eq!(
        fs::read_to_string(Path::new(&repo).join("a.txt")).unwrap(),
        "mudou"
    );
    assert_eq!(
        service::branch_of(&git(), &dest).as_deref(),
        Some("feature/x")
    );
}

#[test]
fn sem_carregar_a_sujeira_a_worktree_nasce_limpa() {
    let s = Sandbox::new();
    let repo = s.repo("repo");
    fs::write(Path::new(&repo).join("a.txt"), "mudou").unwrap();
    let dest = s.path("wts/limpa");
    let created = service::create(&git(), &repo, "limpa", &dest, false).unwrap();
    assert!(!created.carried_tracked_changes);
    assert_eq!(
        fs::read_to_string(Path::new(&dest).join("a.txt")).unwrap(),
        "a"
    );
}

#[test]
fn branch_que_ja_existe_abre_nela_e_nao_leva_a_sujeira() {
    let s = Sandbox::new();
    let repo = s.repo("repo");
    s.git(&["branch", "velha"], &repo);
    fs::write(Path::new(&repo).join("a.txt"), "mudou").unwrap();
    let dest = s.path("wts/velha");
    let created = service::create(&git(), &repo, "velha", &dest, true).unwrap();
    assert!(!created.carried_tracked_changes && !created.reused);
    assert_eq!(service::branch_of(&git(), &dest).as_deref(), Some("velha"));
    assert_eq!(
        fs::read_to_string(Path::new(&dest).join("a.txt")).unwrap(),
        "a"
    );
}

#[test]
fn branch_so_remota_nasce_seguindo_o_remoto() {
    let s = Sandbox::new();
    let repo = s.repo("repo");
    let remote = s.path("remoto.git");
    s.git(&["init", "-q", "--bare", &remote], &s.home());
    s.git(&["remote", "add", "origin", &remote], &repo);
    s.git(&["push", "-q", "origin", "main:so-remota"], &repo);
    s.git(&["fetch", "-q", "origin"], &repo);
    let dest = s.path("wts/so-remota");
    service::create(&git(), &repo, "so-remota", &dest, false).unwrap();
    let upstream = s.git(&["rev-parse", "--abbrev-ref", "so-remota@{u}"], &dest);
    assert_eq!(upstream.trim(), "origin/so-remota");
}

#[test]
fn branch_ja_aberta_reaproveita_a_pasta_sem_criar_nada() {
    let s = Sandbox::new();
    let (repo, worktree) = s.repo_with_worktree();
    let created = service::create(&git(), &repo, "feat", &s.path("wts/outra"), true).unwrap();
    assert_eq!(created.path, worktree);
    assert!(created.reused && !created.carried_tracked_changes);
    assert!(!Path::new(&s.path("wts/outra")).exists());
}

#[test]
fn destino_ocupado_e_erro_antes_de_mexer_em_disco() {
    let s = Sandbox::new();
    let repo = s.repo("repo");
    let dest = s.path("wts/ocupado");
    fs::create_dir_all(&dest).unwrap();
    let error = service::create(&git(), &repo, "nova", &dest, true).unwrap_err();
    assert_eq!(error, Failure::DestinationExists(dest));
    assert!(!service::index(&git(), &repo).local.contains("nova"));
}

#[test]
fn principal_ligada_e_perdas() {
    let s = Sandbox::new();
    let (repo, worktree) = s.repo_with_worktree();
    assert!(service::is_linked_worktree(&git(), &worktree));
    assert!(
        !service::is_linked_worktree(&git(), &repo),
        "o checkout principal não é worktree ligada"
    );
    assert_eq!(
        service::main_worktree(&git(), &worktree).as_deref(),
        Some(repo.as_str())
    );
    assert_eq!(
        service::main_repo(&git(), &worktree).as_deref(),
        Some(repo.as_str())
    );
    assert_eq!(
        service::top_level(&git(), &worktree).as_deref(),
        Some(worktree.as_str())
    );

    assert!(service::losses(&git(), &worktree).unwrap().is_empty());
    fs::write(Path::new(&worktree).join("a.txt"), "mudou").unwrap();
    fs::write(Path::new(&worktree).join("novo.txt"), "x").unwrap();
    s.git(&["config", "user.email", "t@e"], &worktree);
    let losses = service::losses(&git(), &worktree).unwrap();
    assert_eq!(losses.modified, ["a.txt"]);
    assert_eq!(losses.untracked, ["novo.txt"]);
    assert_eq!(losses.unpushed_commits, 0, "sem upstream não é medível");
    assert!(!losses.is_empty());
}

#[test]
fn commits_sem_enviar_contam_como_perda() {
    let s = Sandbox::new();
    let repo = s.repo("repo");
    let remote = s.path("remoto.git");
    s.git(&["init", "-q", "--bare", &remote], &s.home());
    s.git(&["remote", "add", "origin", &remote], &repo);
    s.git(&["push", "-q", "-u", "origin", "main"], &repo);
    fs::write(Path::new(&repo).join("b.txt"), "b").unwrap();
    s.git(&["add", "-A"], &repo);
    s.git(&["commit", "-qm", "segundo"], &repo);
    assert_eq!(service::losses(&git(), &repo).unwrap().unpushed_commits, 1);
}

// ── WorktreeRemoveTests ────────────────────────────────────────────────────

#[test]
fn remove_a_pasta_e_o_registro() {
    let s = Sandbox::new();
    let (repo, worktree) = s.repo_with_worktree();
    assert!(service::is_registered(&git(), &worktree, &repo));

    // Suja como a de verdade nasce: arquivos novos e ignorados copiados.
    fs::write(Path::new(&worktree).join("novo.txt"), "x").unwrap();

    service::remove(&git(), &worktree).unwrap();
    assert!(!Path::new(&worktree).exists());
    assert!(!service::is_registered(&git(), &worktree, &repo));
}

/// `is_registered` compara caminhos resolvidos: em macOS o temporário é `/var/…`
/// de um lado e `/private/var/…` do outro, e comparar texto cru diria "não
/// registrada" para a worktree que está ali.
#[test]
fn a_busca_do_registro_sobrevive_a_caminho_com_symlink() {
    if !cfg!(target_os = "macos") {
        return; // só o macOS tem /var → /private/var para exercitar
    }
    let s = Sandbox::new();
    let (repo, worktree) = s.repo_with_worktree();
    let outra = match worktree.strip_prefix("/private") {
        Some(rest) => rest.to_owned(),
        None => format!("/private{worktree}"),
    };
    assert_ne!(outra, worktree);
    assert!(
        service::is_registered(&git(), &outra, &repo),
        "o caminho com symlink deixou de reconhecer a worktree"
    );
}

/// O estado em que o git deixa as coisas quando desiste no meio: registro já
/// desfeito, pasta ainda no disco. Terminar de apagar é o que foi pedido.
#[test]
fn termina_a_remocao_em_que_o_git_desistiu() {
    let s = Sandbox::new();
    let leftover = s.path("wts/meio-apagada");
    fs::create_dir_all(&leftover).unwrap();
    fs::write(Path::new(&leftover).join("resto.txt"), "sobra").unwrap();
    assert_eq!(service::finish_removal(&leftover, false, 5), Ok(true));
    assert!(!Path::new(&leftover).exists());
}

/// Worktree ainda registrada é erro de verdade do git — a pasta fica e a
/// mensagem sobe. Apagar aqui seria passar por cima de uma recusa legítima.
#[test]
fn guarda_a_pasta_enquanto_a_worktree_esta_registrada() {
    let s = Sandbox::new();
    let (repo, worktree) = s.repo_with_worktree();
    assert_eq!(service::finish_removal(&worktree, true, 5), Ok(false));
    assert!(Path::new(&worktree).exists());
    assert!(service::is_registered(&git(), &worktree, &repo));
}

/// O bug como ele aparece: alguém escrevendo na worktree enquanto ela é apagada
/// — o watcher do editor, um `npm run dev` num terminal da bancada. O git morre
/// com "Directory not empty" depois de já ter desfeito o registro, e o app
/// precisa terminar o serviço. Com ou sem corrida o desfecho é o mesmo: pasta e
/// registro fora.
#[test]
fn a_remocao_termina_mesmo_com_alguem_escrevendo_na_pasta() {
    let s = Sandbox::new();
    let (repo, worktree) = s.repo_with_worktree();
    let ruido = PathBuf::from(&worktree).join("build");
    fs::create_dir_all(&ruido).unwrap();
    for i in 0..40 {
        fs::write(ruido.join(format!("f{i}.txt")), "x").unwrap();
    }

    // Um watcher: escreve em rajada por um instante e se cala.
    let (started_tx, started_rx) = std::sync::mpsc::channel();
    let writer = {
        let ruido = ruido.clone();
        std::thread::spawn(move || {
            started_tx.send(()).unwrap();
            for i in 0..250 {
                let _ = fs::write(ruido.join(format!("race{i}.tmp")), "y");
            }
        })
    };
    started_rx.recv().unwrap();

    service::remove(&git(), &worktree).unwrap();
    writer.join().unwrap();

    assert!(!service::is_registered(&git(), &worktree, &repo));
    assert!(
        !Path::new(&worktree).exists(),
        "sobrou pasta órfã — é o lixo que o bug deixava no disco"
    );
}

/// O caminho inteiro quando o git morre no meio e nem o app consegue apagar (a
/// pasta está trancada): o que sobe é a mensagem que diz exatamente isso — não o
/// "use --force" do git, que não ajudaria ninguém.
#[cfg(unix)]
#[test]
fn avisa_das_sobras_quando_ninguem_consegue_apagar_a_pasta() {
    if crate::commons::testing::running_as_root() {
        return;
    }
    use std::os::unix::fs::PermissionsExt;
    let s = Sandbox::new();
    let (repo, worktree) = s.repo_with_worktree();
    let trancada = PathBuf::from(&worktree).join("vendor");
    fs::create_dir_all(&trancada).unwrap();
    fs::write(trancada.join("z.txt"), "z").unwrap();
    fs::set_permissions(&trancada, fs::Permissions::from_mode(0o500)).unwrap();

    let result = service::remove(&git(), &worktree);
    // Destrancar antes de qualquer asserção, senão o temporário fica para trás.
    fs::set_permissions(&trancada, fs::Permissions::from_mode(0o755)).unwrap();
    assert!(
        matches!(result, Err(Failure::Leftovers { .. })),
        "erro inesperado: {result:?}"
    );
    assert!(
        !service::is_registered(&git(), &worktree, &repo),
        "o git não volta atrás: o registro já foi mesmo tendo falhado"
    );
}

/// Pasta que já não existe não é falha: a faxina não tem o que fazer.
#[test]
fn nada_a_terminar_quando_a_pasta_ja_sumiu() {
    let s = Sandbox::new();
    assert_eq!(
        service::finish_removal(&s.path("nunca-existiu"), false, 5),
        Ok(true)
    );
}

#[test]
fn remover_o_que_nao_e_repositorio_e_erro() {
    let s = Sandbox::new();
    let plain = s.path("solta");
    fs::create_dir_all(&plain).unwrap();
    assert_eq!(
        service::remove(&git(), &plain),
        Err(Failure::NotARepo(plain))
    );
}

#[test]
fn as_mensagens_de_erro() {
    assert_eq!(
        Failure::NotARepo("/x".into()).to_string(),
        "/x não é um repositório git."
    );
    assert_eq!(
        Failure::DestinationExists("/x".into()).to_string(),
        "Já existe algo em /x — apague a pasta ou escolha outro caminho."
    );
    assert_eq!(
        Failure::Git {
            command: "status".into(),
            output: "boom".into()
        }
        .to_string(),
        "git status falhou:\nboom"
    );
    assert!(
        Failure::Leftovers {
            path: "/x".into(),
            reason: "porque sim".into()
        }
        .to_string()
        .contains("a pasta /x não pôde ser apagada — porque sim. Apague-a à mão.")
    );
}

// ── UnversionedCopyTests ───────────────────────────────────────────────────

/// Um clonador de teste: cópia comum de arquivos e pastas (o driver clona de
/// verdade).
struct PlainCopy;

fn copy_tree(from: &Path, to: &Path) -> io::Result<()> {
    if from.is_dir() {
        fs::create_dir_all(to)?;
        for entry in fs::read_dir(from)? {
            let entry = entry?;
            copy_tree(&entry.path(), &to.join(entry.file_name()))?;
        }
        Ok(())
    } else {
        fs::copy(from, to).map(|_| ())
    }
}

impl FileCloner for PlainCopy {
    fn clone_entry(&self, from: &Path, to: &Path) -> io::Result<()> {
        copy_tree(from, to)
    }
}

/// O script escrito pelo app é o de fábrica, mesmo com outro cabeçalho.
#[test]
fn script_escrito_pelo_app_e_de_fabrica_mesmo_com_outro_cabecalho() {
    let written = copy::STOCK_SCRIPT;
    assert!(copy::is_stock_script(written));
    let renamed = written.replace("# Egeon Deck —", "# mega-brain —");
    assert!(copy::is_stock_script(&renamed), "comentário não conta");
}

#[test]
fn script_editado_nao_e_de_fabrica() {
    let edited = copy::STOCK_SCRIPT.replace(
        ".git/|.git) continue ;;",
        ".git/|.git|node_modules/) continue ;;",
    );
    assert_ne!(edited, copy::STOCK_SCRIPT);
    assert!(!copy::is_stock_script(&edited));
}

#[test]
fn copia_o_nao_rastreado_e_o_ignorado_mas_nao_o_versionado() {
    let s = Sandbox::new();
    let root = s.root();
    let repo = root.join("repo");
    let wt = root.join("wt");
    fs::create_dir_all(repo.join("node_modules/pkg")).unwrap();
    fs::create_dir_all(&wt).unwrap();
    fs::write(repo.join(".gitignore"), "node_modules/\n.env\n").unwrap();
    fs::write(repo.join(".env"), "SECRET=1").unwrap();
    fs::write(repo.join("node_modules/pkg/index.js"), "x").unwrap();
    fs::write(repo.join("rascunho.md"), "novo").unwrap();
    let repo_s = repo.to_string_lossy().into_owned();
    let wt_s = wt.to_string_lossy().into_owned();
    s.git(&["init", "-q", "."], &repo_s);
    s.git(&["add", ".gitignore"], &repo_s);

    let entries = copy::entries(&git(), &repo_s);
    let mut sorted = entries.clone();
    sorted.sort();
    assert_eq!(sorted, [".env", "node_modules/", "rascunho.md"]);

    let outcome = copy::copy(&entries, &repo_s, &wt_s, &PlainCopy);
    assert_eq!(
        outcome,
        copy::Outcome {
            copied: 3,
            failed: vec![]
        }
    );
    assert_eq!(fs::read_to_string(wt.join(".env")).unwrap(), "SECRET=1");
    assert!(wt.join("node_modules/pkg/index.js").exists());
    assert!(!wt.join(".gitignore").exists(), "versionado não");
}

/// O que já existe no destino fica: a worktree pode ter sido reaproveitada.
#[test]
fn o_destino_que_ja_existe_fica() {
    let s = Sandbox::new();
    let root = s.root();
    fs::write(root.join("a"), "origem").unwrap();
    fs::write(root.join("b"), "seu").unwrap();
    assert!(copy::clone(&root.join("a"), &root.join("b"), &PlainCopy));
    assert_eq!(fs::read_to_string(root.join("b")).unwrap(), "seu");
}

#[test]
fn falha_do_clone_vai_para_a_lista_em_ordem() {
    struct Picky;
    impl FileCloner for Picky {
        fn clone_entry(&self, from: &Path, to: &Path) -> io::Result<()> {
            if from.ends_with("ruim") {
                return Err(io::Error::other("não deu"));
            }
            copy_tree(from, to)
        }
    }
    let s = Sandbox::new();
    let root = s.root();
    let (src, dst) = (root.join("src"), root.join("dst"));
    fs::create_dir_all(&src).unwrap();
    for name in ["bom", "ruim", "ainda-ruim"] {
        fs::write(src.join(name), "x").unwrap();
    }
    fs::write(src.join("ruim"), "x").unwrap();
    let entries: Vec<String> = ["ruim", "bom", "ainda-ruim"].map(String::from).to_vec();
    let out = copy::copy(
        &entries,
        src.to_str().unwrap(),
        dst.to_str().unwrap(),
        &Picky,
    );
    assert_eq!(out.copied, 2);
    assert_eq!(out.failed, ["ruim"]);
}

#[test]
fn instala_o_script_uma_vez_e_nao_reescreve_por_cima() {
    let s = Sandbox::new();
    let script = s.root().join("cfg/worktree-copy.sh");
    let chmods = std::cell::Cell::new(0);
    let make_exec = |_: &Path| chmods.set(chmods.get() + 1);
    copy::install_script(&script, &make_exec);
    assert_eq!(fs::read_to_string(&script).unwrap(), copy::STOCK_SCRIPT);
    assert_eq!(chmods.get(), 1);

    fs::write(&script, "# meu\necho oi\n").unwrap();
    copy::install_script(&script, &make_exec);
    assert_eq!(
        fs::read_to_string(&script).unwrap(),
        "# meu\necho oi\n",
        "ajuste do usuário não se apaga"
    );
    assert_eq!(chmods.get(), 1);
}

#[test]
fn copy_unversioned_usa_o_clone_com_o_script_de_fabrica_e_o_script_do_usuario_quando_editado() {
    let s = Sandbox::new();
    let root = s.root();
    let repo = root.join("repo");
    let wt = root.join("wt");
    fs::create_dir_all(&repo).unwrap();
    fs::create_dir_all(&wt).unwrap();
    fs::write(repo.join("rascunho.md"), "novo").unwrap();
    let (repo_s, wt_s) = (
        repo.to_string_lossy().into_owned(),
        wt.to_string_lossy().into_owned(),
    );
    s.git(&["init", "-q", "."], &repo_s);
    let script = root.join("worktree-copy.sh");

    let summary = copy::copy_unversioned(&git(), &script, &repo_s, &wt_s, &PlainCopy, &|_| {});
    assert!(
        summary.starts_with("1 entrada(s) clonada(s) em "),
        "{summary}"
    );
    assert_eq!(fs::read_to_string(wt.join("rascunho.md")).unwrap(), "novo");

    // Mexeu na lógica: vale o script dele, e a última linha da saída é o resumo.
    fs::write(&script, "#!/bin/bash\necho \"meu $1 $2\"\necho fim\n").unwrap();
    let summary = copy::copy_unversioned(&git(), &script, &repo_s, &wt_s, &PlainCopy, &|_| {});
    assert_eq!(summary, "fim");
}

// ── NodeWorktreeTests ──────────────────────────────────────────────────────

fn plan(inside: bool, repo: Option<&str>, branch: &str) -> NodeWorktree {
    NodeWorktree {
        node_id: "t".into(),
        current_path: "/repos/deck/api".into(),
        repo_root: repo.map(str::to_owned),
        inside_workbench: inside,
        enabled: false,
        branch: branch.into(),
        touched: false,
    }
}

#[test]
fn mesma_branch_dentro_da_bancada_vai_junto() {
    assert!(
        !plan(true, Some("/repos/deck"), "feat/x")
            .decided("feat/x")
            .enabled,
        "vai junto pelo cwd relativo"
    );
}

#[test]
fn outra_branch_dentro_da_bancada_ganha_worktree_propria() {
    assert!(
        plan(true, Some("/repos/deck"), "fix/api")
            .decided("feat/x")
            .enabled
    );
}

#[test]
fn repo_vizinho_com_branch_ganha_worktree_propria_mesmo_na_mesma_branch() {
    assert!(
        plan(false, Some("/repos/deck"), "feat/x")
            .decided("feat/x")
            .enabled
    );
}

#[test]
fn branch_vazia_fica() {
    assert!(
        !plan(false, Some("/repos/deck"), "")
            .decided("feat/x")
            .enabled
    );
}

#[test]
fn pasta_fora_de_git_nunca_ganha_worktree() {
    assert!(!plan(false, None, "feat/x").decided("feat/x").enabled);
}

#[test]
fn destino_so_existe_para_quem_vai() {
    let mut p = plan(false, Some("/repos/deck"), "feat/x");
    assert_eq!(p.destination(), None, "desligado");
    p.enabled = true;
    assert_eq!(
        p.destination().as_deref(),
        Some("/repos/worktrees/deck/feat-x")
    );
    p.branch = "  ".into();
    assert_eq!(p.destination(), None, "branch em branco não é destino");
    assert_eq!(p.repo_name(), "deck");
    assert_eq!(plan(false, None, "x").repo_name(), "api");
}

#[test]
fn o_caminho_curto_vai_com_til() {
    assert_eq!(node::short("/Users/eu/x", "/Users/eu"), "~/x");
    assert_eq!(node::short("/outro/x", "/Users/eu"), "/outro/x");
}

#[test]
fn inspecionar_levanta_cada_no_com_pasta_e_pula_o_web() {
    let s = Sandbox::new();
    let repo = s.repo("repo");
    let neighbor = s.repo("vizinho");
    let mut config = WorkbenchConfig::new("deck", repo.clone(), vec![]);
    let mut dentro = NodeConfig::new(NodeKind::Shell, "dentro");
    dentro.cwd = None;
    let mut fora = NodeConfig::new(NodeKind::Agent, "fora");
    fora.cwd = Some(neighbor.clone());
    let mut perdido = NodeConfig::new(NodeKind::Shell, "perdido");
    perdido.cwd = Some("/nao/existe/mesmo".into());
    let web = NodeConfig::new(NodeKind::Web, "docs");
    config.nodes = vec![dentro, fora, perdido, web];

    let plans = node::inspect(&git(), &config, &repo, "feat/x", "/h");
    let ids: Vec<_> = plans.iter().map(|p| p.node_id.as_str()).collect();
    assert_eq!(ids, ["dentro", "fora", "perdido"], "web não abre pasta");
    assert!(
        plans[0].inside_workbench && !plans[0].enabled,
        "dentro vai junto"
    );
    assert!(
        !plans[1].inside_workbench && plans[1].enabled,
        "vizinho ganha a própria"
    );
    assert_eq!(plans[1].repo_root.as_deref(), Some(neighbor.as_str()));
    assert!(
        plans[2].repo_root.is_none() && !plans[2].enabled,
        "sem pasta, sem repositório"
    );
}

#[test]
fn materializar_divide_a_mesma_worktree_e_deixa_o_que_falha_na_origem() {
    let s = Sandbox::new();
    let neighbor = s.repo("vizinho");
    let broken = s.path("quebrado");
    fs::create_dir_all(&broken).unwrap();
    let make = |id: &str, repo: &str, branch: &str| NodeWorktree {
        node_id: id.into(),
        current_path: repo.into(),
        repo_root: Some(repo.into()),
        inside_workbench: false,
        enabled: true,
        branch: branch.into(),
        touched: false,
    };
    let plans = [
        make("a", &neighbor, "feat/x"),
        make("b", &neighbor, "feat/x"),
        make("c", &neighbor, "outra"),
        make("d", &broken, "feat/x"),
        NodeWorktree {
            enabled: false,
            ..make("e", &neighbor, "feat/x")
        },
    ];
    let mut created = Vec::new();
    let cwds = node::materialize(&git(), &plans, "/h", |repo, path| {
        created.push((repo.to_owned(), path.to_owned()));
    });

    let a = service::suggested_path(&neighbor, &branch("feat/x"));
    let c = service::suggested_path(&neighbor, &branch("outra"));
    assert_eq!(cwds["a"], a);
    assert_eq!(cwds["b"], a, "mesmo repo e mesma branch dividem a worktree");
    assert_eq!(cwds["c"], c);
    assert_eq!(
        cwds["d"], broken,
        "o que falha segue apontando para o repositório original"
    );
    assert!(!cwds.contains_key("e"), "desligado não entra");
    assert_eq!(
        created.len(),
        2,
        "o git é chamado uma vez por destino: {created:?}"
    );
}

// ── Duplicar a bancada ─────────────────────────────────────────────────────

fn node_with_cwd(id: &str, cwd: Option<&str>) -> NodeConfig {
    let mut n = NodeConfig::new(NodeKind::Agent, id);
    n.cwd = cwd.map(str::to_owned);
    n.conversation_id = Some("C1".into());
    n.conversation_started = Some(true);
    n
}

/// `../nexus-backend` na origem é a pasta de projetos; na worktree seria outro
/// lugar. O terminal apontaria para a raiz em silêncio.
#[test]
fn reapontar_resolve_cada_pasta_contra_a_raiz_da_origem() {
    let nodes = [
        node_with_cwd("raiz", None),
        node_with_cwd("api", Some("packages/api")),
        node_with_cwd("a-propria-raiz", Some(".")),
        node_with_cwd("vizinho", Some("../nexus-backend")),
        node_with_cwd("absoluto", Some("/outra/casa")),
        node_with_cwd("casa", Some("~/x")),
        node_with_cwd("com-worktree", Some("../nexus-backend")),
    ];
    let cwds = BTreeMap::from([("com-worktree".to_owned(), "~/worktrees/nb/feat".to_owned())]);
    let out = duplicate::repointed(&nodes, "/Users/eu/repos/deck", &cwds, "/Users/eu");
    let cwd = |id: &str| out.iter().find(|n| n.id == id).unwrap().cwd.clone();
    assert_eq!(cwd("raiz"), None);
    assert_eq!(cwd("api").as_deref(), Some("packages/api"));
    assert_eq!(cwd("a-propria-raiz"), None);
    assert_eq!(cwd("vizinho").as_deref(), Some("~/repos/nexus-backend"));
    assert_eq!(cwd("absoluto").as_deref(), Some("/outra/casa"));
    assert_eq!(cwd("casa").as_deref(), Some("~/x"));
    assert_eq!(cwd("com-worktree").as_deref(), Some("~/worktrees/nb/feat"));
    // A conversa nunca vem junto.
    assert!(
        out.iter()
            .all(|n| n.conversation_id.is_none() && n.conversation_started.is_none())
    );
}

#[test]
fn duplicar_cria_a_worktree_reaponta_os_nos_e_monta_a_bancada_nova() {
    let s = Sandbox::new();
    let repo = s.repo("repo");
    let home = s.home();
    let mut origin = WorkbenchConfig::new(
        "deck",
        repo.clone(),
        vec![
            node_with_cwd("raiz", None),
            node_with_cwd("api", Some("packages/api")),
        ],
    );
    origin.project = Some("p1".into());
    origin.template = Some("padrao".into());
    origin.edges = Some(vec![crate::features::edge::EdgeConfig::new(
        "raiz",
        "api",
        Some(3),
    )]);
    origin.view = Some(crate::features::workbench::model::ViewMode::Chat);
    origin.rules = Some("regra".into());

    let b = branch("feature/login");
    let done = duplicate::duplicate(&git(), &origin, &repo, &b, &[], &home).unwrap();
    let dest = service::suggested_path(&repo, &b);
    assert_eq!(done.created.path, dest);
    assert_eq!(done.pending_copies(&repo), [(repo.clone(), dest.clone())]);
    assert_eq!(done.nodes[1].cwd.as_deref(), Some("packages/api"));

    let existing = [origin.clone()];
    let fresh = duplicate::new_workbench(&origin, &done, &existing);
    assert_eq!(fresh.name, "feature-login", "a branch achatada vira o nome");
    assert_eq!(fresh.path, done.worktree_path);
    assert_eq!(
        fresh.project.as_deref(),
        Some("p1"),
        "a worktree é do mesmo projeto: saiu dele"
    );
    assert_eq!(fresh.template.as_deref(), Some("padrao"));
    assert_eq!(fresh.edges, origin.edges, "as ligações vêm junto");
    assert_eq!(fresh.view, origin.view);
    assert_eq!(
        fresh.rules, None,
        "regras não vêm na duplicação simples, como no Swift"
    );
    assert!(fresh.color.is_some());
    assert_ne!(fresh.id, origin.id);

    let moved = duplicate::moved(&origin, &done);
    assert_eq!(moved.id, origin.id);
    assert_eq!(moved.path, done.worktree_path);
    assert_eq!(moved.nodes, done.nodes);
    let _ = Target::NewWorkbench;

    // Reaproveitar a mesma worktree não pede cópia por cima.
    let again = duplicate::duplicate(&git(), &origin, &repo, &b, &[], &home).unwrap();
    assert!(again.created.reused);
    assert!(again.pending_copies(&repo).is_empty());
}

#[test]
fn nome_da_bancada_nova_nao_repete_o_de_nenhuma_outra() {
    let s = Sandbox::new();
    let repo = s.repo("repo");
    let origin = WorkbenchConfig::new("deck", repo.clone(), vec![]);
    let done = duplicate::duplicate(&git(), &origin, &repo, &branch("x"), &[], &s.home()).unwrap();
    let taken = [origin.clone(), WorkbenchConfig::new("x", "/t", vec![])];
    assert_eq!(duplicate::new_workbench(&origin, &done, &taken).name, "x-2");
}

#[cfg(unix)]
fn make_link(target: &Path, at: &Path) -> io::Result<()> {
    std::os::unix::fs::symlink(target, at)
}

#[cfg(unix)]
#[test]
fn multi_projeto_abre_a_mesma_branch_em_cada_repo_e_o_que_recusa_nao_derruba_os_outros() {
    let s = Sandbox::new();
    let web = s.repo("src/web");
    let back = s.repo("src/back");
    let home = s.home();
    // O backend já tem `feat` aberta em outro lugar: vira link.
    let elsewhere = s.path("fora/back-feat");
    s.git(&["worktree", "add", "-b", "feat", &elsewhere], &back);
    let project = |id: &str, name: &str, path: &str| {
        let mut p = ProjectConfig::new(name, path);
        p.id = id.into();
        p
    };
    let (w, b) = (project("web", "web", &web), project("back", "back", &back));
    let multi = {
        let mut m = project("m", "Nexus", &s.path("links"));
        m.members = Some(vec!["web".into(), "back".into()]);
        m
    };

    let opened = duplicate::open_multi(
        &git(),
        &multi,
        &[&w, &b],
        "feat",
        &BTreeMap::new(),
        &home,
        &make_link,
    );
    assert!(opened.any_opened, "{:?}", opened.failures);
    assert!(opened.failures.is_empty(), "{:?}", opened.failures);
    assert_eq!(opened.root, s.path("src/worktrees/Nexus/feat"));
    // O web nasceu; o back já existia, então só é ligado — e não entra na cópia.
    assert!(Path::new(&opened.root).join("web/a.txt").exists());
    assert_eq!(
        fs::read_link(Path::new(&opened.root).join("back")).unwrap(),
        Path::new(&elsewhere)
    );
    assert_eq!(opened.pending.len(), 1);
    assert_eq!(opened.pending[0].0, web);

    // Um repo que recusa não derruba o outro; todos recusando, não há bancada.
    let ruim = project("ruim", "ruim", &s.path("nao-e-repo"));
    fs::create_dir_all(&ruim.path).unwrap();
    let multi2 = project("m2", "Outro", &s.path("links2"));
    let partial = duplicate::open_multi(
        &git(),
        &multi2,
        &[&w, &ruim],
        "feat2",
        &BTreeMap::new(),
        &home,
        &make_link,
    );
    assert!(partial.any_opened);
    assert_eq!(partial.failures.len(), 1);
    assert!(
        partial.failures[0].starts_with("ruim: "),
        "{:?}",
        partial.failures
    );
    let none = duplicate::open_multi(
        &git(),
        &multi2,
        &[&ruim],
        "feat3",
        &BTreeMap::new(),
        &home,
        &make_link,
    );
    assert!(!none.any_opened);
    assert!(
        !Path::new(&none.root).exists(),
        "a pasta só de links foi podada"
    );
}

#[test]
fn bancada_do_multi_projeto_leva_origem_ou_template() {
    let home = "/Users/eu";
    let mut origin = WorkbenchConfig::new(
        "deck",
        "/Users/eu/repos/deck",
        vec![node_with_cwd("a", Some("web"))],
    );
    origin.template = Some("padrao".into());
    origin.rules = Some("regra".into());
    origin.view = Some(crate::features::workbench::model::ViewMode::Chat);
    origin.edges = Some(vec![]);

    let from_origin = duplicate::multi_workbench(
        "m",
        "feat/x",
        "/Users/eu/w/Nexus/feat-x",
        Some(&origin),
        None,
        &[],
        home,
    );
    assert_eq!(from_origin.name, "feat-x");
    assert_eq!(from_origin.path, "~/w/Nexus/feat-x");
    assert_eq!(from_origin.project.as_deref(), Some("m"));
    assert_eq!(from_origin.template.as_deref(), Some("padrao"));
    assert_eq!(
        from_origin.rules.as_deref(),
        Some("regra"),
        "o multi herda as regras, a duplicação simples não"
    );
    assert_eq!(from_origin.nodes[0].cwd.as_deref(), Some("web"));

    let nodes = vec![NodeConfig::new(NodeKind::Shell, "sh")];
    let from_template = duplicate::multi_workbench(
        "m",
        "x",
        "/r",
        None,
        Some(("modelo", nodes.clone())),
        &[],
        home,
    );
    assert_eq!(from_template.template.as_deref(), Some("modelo"));
    assert_eq!(from_template.nodes, nodes);
    let empty = duplicate::multi_workbench("m", "x", "/r", None, None, &[], home);
    assert!(empty.nodes.is_empty() && empty.template.is_none());
}

// ── A rota /worktree ───────────────────────────────────────────────────────

mod route {
    use std::collections::HashMap;

    use serde_json::{Value, json};

    use super::*;
    #[cfg(unix)]
    use crate::features::workspace::model::WorkspaceConfig;
    use crate::features::worktree::routes::{OrgSnapshot, WorktreeEffect, worktree};
    use crate::protocol::handler::RouteRequest;

    fn request(query: &[(&str, &str)]) -> RouteRequest {
        let query: HashMap<String, String> = query
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect();
        RouteRequest {
            method: "GET".into(),
            target: "/worktree".into(),
            path: "/worktree".into(),
            query,
            body: vec![],
            origin: None,
        }
    }

    #[cfg(unix)]
    fn link(target: &Path, at: &Path) -> io::Result<()> {
        std::os::unix::fs::symlink(target, at)
    }
    #[cfg(not(unix))]
    fn link(_: &Path, _: &Path) -> io::Result<()> {
        Err(io::Error::other("sem symlink"))
    }

    fn run(q: &[(&str, &str)], org: &OrgSnapshot, home: &str) -> (u16, Value, Vec<WorktreeEffect>) {
        let (reply, effects) = worktree(&request(q), org, home, &git(), &link);
        (reply.status, reply.json, effects)
    }

    fn org(workbenches: Vec<WorkbenchConfig>) -> OrgSnapshot {
        OrgSnapshot {
            workbenches,
            workspaces: vec![],
        }
    }

    #[test]
    fn bancada_ou_no_desconhecidos_e_pasta_fora_de_git() {
        let s = Sandbox::new();
        let plain = s.path("solta");
        fs::create_dir_all(&plain).unwrap();
        let mut bench = WorkbenchConfig::new("deck", plain.clone(), vec![]);
        bench.nodes = vec![NodeConfig::new(NodeKind::Shell, "sh")];
        let snapshot = org(vec![bench]);
        let home = s.home();

        let (status, body, effects) = run(&[("target", "nada")], &snapshot, &home);
        assert_eq!(status, 400);
        assert_eq!(
            body,
            json!({"ok": false, "error": "bancada desconhecida 'nada'"})
        );
        assert!(effects.is_empty());
        assert_eq!(
            run(&[], &snapshot, &home).1["error"],
            "bancada desconhecida ''"
        );

        let (_, body, _) = run(&[("target", "deck/fantasma")], &snapshot, &home);
        assert_eq!(
            body,
            json!({"ok": false, "error": "nó desconhecido 'fantasma'"})
        );

        let (status, body, _) = run(&[("target", "deck/sh")], &snapshot, &home);
        assert_eq!(status, 400);
        assert_eq!(body["error"], format!("{plain} não é repositório git"));
        let (_, body, _) = run(&[("target", "deck"), ("branch", "x")], &snapshot, &home);
        assert_eq!(body["error"], format!("{plain} não é repositório git"));
        // `deck/` é a bancada, não um nó vazio.
        assert_eq!(
            run(&[("target", "deck/"), ("branch", "x")], &snapshot, &home).1["error"],
            body["error"]
        );
    }

    #[test]
    fn duplica_a_bancada_em_worktree_e_responde_com_as_chaves_de_hoje() {
        let s = Sandbox::new();
        let repo = s.repo("repo");
        let neighbor = s.repo("vizinho");
        let mut origin = WorkbenchConfig::new("deck", repo.clone(), vec![]);
        let mut back = NodeConfig::new(NodeKind::Agent, "back");
        back.cwd = Some(neighbor.clone());
        origin.nodes = vec![NodeConfig::new(NodeKind::Shell, "sh"), back];
        let snapshot = org(vec![origin]);
        let home = s.home();

        let (status, body, effects) = run(
            &[
                ("target", "deck"),
                ("branch", "feature/x"),
                ("nodes", "back:fix/api"),
            ],
            &snapshot,
            &home,
        );
        assert_eq!(status, 200, "{body}");
        let wt = service::suggested_path(&repo, &branch("feature/x"));
        assert_eq!(
            body,
            json!({"ok": true, "workbench": "feature-x", "branch": "feature/x", "path": wt,
                   "nodes": [{"id": "back", "repo": "vizinho"}]})
        );
        let [WorktreeEffect::AddWorkbench { config, copies }] = effects.as_slice() else {
            panic!("{effects:?}");
        };
        assert_eq!(config.name, "feature-x");
        let neighbor_wt = service::suggested_path(&neighbor, &branch("fix/api"));
        assert_eq!(
            config.nodes[1].cwd.as_deref(),
            Some(node::short(&neighbor_wt, &s.home()).as_str()),
            "o do vizinho abre na dele, com ~"
        );
        assert_eq!(config.nodes[0].cwd, None, "quem está dentro vai junto");
        assert_eq!(
            copies,
            &[(repo.clone(), wt.clone()), (neighbor.clone(), neighbor_wt)]
        );
        assert!(Path::new(&wt).join("a.txt").exists());
    }

    #[test]
    fn branch_vazia_e_sugerida_e_back_sem_branch_nao_leva_o_terminal() {
        let s = Sandbox::new();
        let repo = s.repo("repo");
        let neighbor = s.repo("vizinho");
        let mut origin = WorkbenchConfig::new("deck", repo.clone(), vec![]);
        let mut back = NodeConfig::new(NodeKind::Agent, "back");
        back.cwd = Some(neighbor.clone());
        origin.nodes = vec![back];
        let snapshot = org(vec![origin]);
        let (status, body, effects) = run(
            &[("target", "deck"), ("nodes", "back:")],
            &snapshot,
            &s.home(),
        );
        assert_eq!(status, 200, "{body}");
        assert_eq!(body["branch"], "main-2");
        assert_eq!(body["nodes"], json!([]));
        let [WorktreeEffect::AddWorkbench { config, .. }] = effects.as_slice() else {
            panic!()
        };
        // `back` ficou apontando para o repositório original, em caminho absoluto.
        assert_eq!(
            config.nodes[0].cwd.as_deref(),
            Some(node::short(&neighbor, &s.home()).as_str())
        );
    }

    #[test]
    fn um_terminal_so_vai_para_a_worktree_e_perde_a_conversa() {
        let s = Sandbox::new();
        let repo = s.repo("repo");
        let neighbor = s.repo("vizinho");
        let mut origin = WorkbenchConfig::new("deck", repo, vec![]);
        let mut back = NodeConfig::new(NodeKind::Agent, "back");
        back.cwd = Some(neighbor.clone());
        back.conversation_id = Some("C1".into());
        origin.nodes = vec![back];
        let id = origin.id.clone();
        let snapshot = org(vec![origin]);

        let (status, body, effects) = run(
            &[("target", "deck/back"), ("branch", "spike")],
            &snapshot,
            &s.home(),
        );
        assert_eq!(status, 200, "{body}");
        let wt = service::suggested_path(&neighbor, &branch("spike"));
        assert_eq!(
            body,
            json!({"ok": true, "node": "back", "repo": neighbor, "branch": "spike",
                   "path": wt, "reused": false})
        );
        let [
            WorktreeEffect::RepointNode {
                workbench_id,
                node,
                copies,
            },
        ] = effects.as_slice()
        else {
            panic!("{effects:?}");
        };
        assert_eq!(workbench_id, &id);
        assert_eq!(
            node.cwd.as_deref(),
            Some(node::short(&wt, &s.home()).as_str())
        );
        assert_eq!(node.conversation_id, None);
        assert_eq!(copies, &[(neighbor.clone(), wt.clone())]);

        // A mesma branch de novo: a pasta já existe, é reaproveitada e não copia.
        let (_, again, effects) = run(
            &[("target", "deck/back"), ("branch", "spike")],
            &snapshot,
            &s.home(),
        );
        assert_eq!(again["reused"], true);
        let [WorktreeEffect::RepointNode { copies, .. }] = effects.as_slice() else {
            panic!()
        };
        assert!(copies.is_empty());
    }

    #[cfg(unix)]
    #[test]
    fn multi_projeto_pede_branch_e_abre_uma_worktree_por_repo() {
        use crate::features::workspace::model::ProjectConfig;
        let s = Sandbox::new();
        let web = s.repo("src/web");
        let back = s.repo("src/back");
        let project = |id: &str, name: &str, path: &str| {
            let mut p = ProjectConfig::new(name, path);
            p.id = id.into();
            p
        };
        let mut multi = project("m", "Nexus", &s.path("links"));
        multi.members = Some(vec!["web".into(), "back".into()]);
        let mut space = WorkspaceConfig::new("Agro");
        space.projects = vec![
            project("web", "web", &web),
            project("back", "back", &back),
            multi,
        ];
        let mut origin = WorkbenchConfig::new("nexus", s.path("links"), vec![]);
        origin.project = Some("m".into());
        let snapshot = OrgSnapshot {
            workbenches: vec![origin],
            workspaces: vec![space],
        };

        let (status, body, _) = run(&[("target", "nexus")], &snapshot, &s.home());
        assert_eq!(
            (status, body),
            (
                400,
                json!({"ok": false, "error": "multi-projeto pede branch"})
            )
        );

        let (status, body, effects) = run(
            &[
                ("target", "nexus"),
                ("branch", "feat/login"),
                ("nodes", "back:fix/api"),
            ],
            &snapshot,
            &s.home(),
        );
        assert_eq!(status, 200, "{body}");
        let root = s.path("src/worktrees/Nexus/feat-login");
        assert_eq!(
            body,
            json!({"ok": true, "path": root, "failed": [], "workbench": "feat-login"})
        );
        let [WorktreeEffect::AddWorkbench { config, copies }] = effects.as_slice() else {
            panic!()
        };
        assert_eq!(config.project.as_deref(), Some("m"));
        assert_eq!(copies.len(), 2);
        assert_eq!(
            service::branch_of(&git(), &format!("{root}/back")).as_deref(),
            Some("fix/api")
        );
        assert_eq!(
            service::branch_of(&git(), &format!("{root}/web")).as_deref(),
            Some("feat/login")
        );
    }
}

// ── O que remover uma bancada leva do disco ────────────────────────────────

mod removal_plan_tests {
    use serde_json::json;

    use super::*;
    use crate::features::workbench::removal::{Removal, RemovalTarget};
    #[cfg(unix)]
    use crate::features::worktree::removal_plan::multi_roots;
    use crate::features::worktree::removal_plan::{RemovalContext, involved, loss_lines, payload};

    fn bench_at(path: &str, nodes: Vec<NodeConfig>) -> WorkbenchConfig {
        WorkbenchConfig::new("deck", path, nodes)
    }

    #[test]
    fn so_worktree_ligada_entra_e_o_checkout_principal_nunca() {
        let s = Sandbox::new();
        let (repo, worktree) = s.repo_with_worktree();
        let ctx = RemovalContext::default();
        // A bancada no checkout principal: nada a apagar do disco.
        assert!(involved(&git(), &bench_at(&repo, vec![]), &ctx, &s.home()).is_empty());

        let found = involved(&git(), &bench_at(&worktree, vec![]), &ctx, &s.home());
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].path, worktree);
        assert_eq!(found[0].repo, "repo");
        assert_eq!(found[0].branch.as_deref(), Some("feat"));
        assert_eq!(found[0].owners, ["bancada"]);
        assert_eq!(found[0].used_by, None);
    }

    #[test]
    fn no_dentro_da_bancada_nao_conta_duas_vezes_e_no_de_fora_entra_com_o_dono() {
        let s = Sandbox::new();
        let (_, worktree) = s.repo_with_worktree();
        let neighbor = s.repo("vizinho");
        let neighbor_wt = s.path("wts/vizinho-feat");
        s.git(&["worktree", "add", "-b", "feat", &neighbor_wt], &neighbor);
        fs::create_dir_all(Path::new(&worktree).join("api")).unwrap();

        let mut inside = NodeConfig::new(NodeKind::Shell, "dentro");
        inside.cwd = Some("api".into());
        let mut outside = NodeConfig::new(NodeKind::Agent, "back");
        outside.cwd = Some(neighbor_wt.clone());
        let mut another = NodeConfig::new(NodeKind::Agent, "back2");
        another.cwd = Some(neighbor_wt.clone());
        let web = NodeConfig::new(NodeKind::Web, "docs");
        let config = bench_at(&worktree, vec![inside, outside, another, web]);
        let ctx = RemovalContext {
            is_multi: false,
            others: vec![("outra".into(), neighbor_wt.clone())],
        };
        let found = involved(&git(), &config, &ctx, &s.home());
        let paths: Vec<_> = found.iter().map(|w| w.path.as_str()).collect();
        let mut expected = vec![worktree.as_str(), neighbor_wt.as_str()];
        expected.sort_unstable();
        assert_eq!(paths, expected);
        let nb = found.iter().find(|w| w.path == neighbor_wt).unwrap();
        assert_eq!(nb.owners, ["back", "back2"]);
        assert_eq!(
            nb.used_by.as_deref(),
            Some("outra"),
            "outra bancada abre a mesma pasta"
        );
        assert_eq!(nb.repo, "vizinho");
    }

    #[cfg(unix)]
    #[test]
    fn multi_projeto_em_worktree_conta_as_subpastas_de_verdade_e_nao_os_links() {
        let s = Sandbox::new();
        let web = s.repo("src/web");
        let back = s.repo("src/back");
        let root = s.path("multi/feat");
        fs::create_dir_all(&root).unwrap();
        s.git(
            &["worktree", "add", "-b", "feat", &format!("{root}/web")],
            &web,
        );
        s.git(
            &["worktree", "add", "-b", "feat", &s.path("fora/back-feat")],
            &back,
        );
        std::os::unix::fs::symlink(s.path("fora/back-feat"), format!("{root}/back")).unwrap();

        let config = bench_at(&root, vec![]);
        let ctx = RemovalContext {
            is_multi: true,
            others: vec![],
        };
        let found = involved(&git(), &config, &ctx, &s.home());
        assert_eq!(
            found.iter().map(|w| w.path.clone()).collect::<Vec<_>>(),
            [format!("{root}/web")]
        );

        // A pasta-mãe sai junto; a de links do checkout principal fica.
        let mut project = ProjectConfig::new("Nexus", s.path("links"));
        project.members = Some(vec![]);
        assert_eq!(
            multi_roots(&config, Some(&project), &s.home()),
            [PathBuf::from(&root)]
        );
        let at_links = bench_at(&s.path("links"), vec![]);
        assert!(multi_roots(&at_links, Some(&project), &s.home()).is_empty());
        assert!(multi_roots(&config, None, &s.home()).is_empty());
    }

    #[test]
    fn as_linhas_do_alerta_dizem_o_que_se_perde_em_cada_worktree() {
        let s = Sandbox::new();
        let (_, worktree) = s.repo_with_worktree();
        let clean = involved(
            &git(),
            &bench_at(&worktree, vec![]),
            &RemovalContext::default(),
            &s.home(),
        );
        assert!(loss_lines(&git(), &clean).is_empty(), "limpa não alerta");

        for i in 0..8 {
            fs::write(Path::new(&worktree).join(format!("m{i}.txt")), "x").unwrap();
        }
        fs::write(Path::new(&worktree).join("a.txt"), "mudou").unwrap();
        s.git(
            &[
                "add", "m0.txt", "m1.txt", "m2.txt", "m3.txt", "m4.txt", "m5.txt", "m6.txt",
            ],
            &worktree,
        );
        let lines = loss_lines(&git(), &clean);
        assert_eq!(lines[0], "repo · feat");
        assert!(
            lines[1].starts_with("8 arquivo(s) com mudanças não commitadas:"),
            "{lines:?}"
        );
        // Seis arquivos e a linha do "e outros".
        assert_eq!(lines.iter().filter(|l| l.starts_with("   ")).count(), 7);
        assert!(lines.contains(&"   … e outros 2".to_owned()), "{lines:?}");
        assert!(
            lines
                .iter()
                .any(|l| l == "1 arquivo(s) novo(s), nunca commitados."),
            "{lines:?}"
        );
    }

    #[test]
    fn a_resposta_da_rota_remove_tem_as_chaves_do_swift() {
        let wt = |path: &str, used: Option<&str>| super::super::removal_plan::BenchWorktree {
            path: path.into(),
            repo: "repo".into(),
            branch: Some("feat".into()),
            owners: vec!["bancada".into()],
            used_by: used.map(str::to_owned),
        };
        let list = [wt("/a", None), wt("/b", Some("outra"))];
        // Sem apagar nada do disco (worktrees=0).
        assert_eq!(
            payload("deck", &list, None),
            json!({"ok": true, "workbench": "deck", "removed": [], "sweeping": [],
                   "kept": [{"path": "/b", "usedBy": "outra"}],
                   "worktrees": [{"path": "/a", "repo": "repo", "branch": "feat", "owners": ["bancada"]},
                                 {"path": "/b", "repo": "repo", "branch": "feat", "owners": ["bancada"]}]})
        );
        let target = |p: &str| RemovalTarget {
            path: p.into(),
            label: p.into(),
        };
        let done = Removal {
            removed: vec![target("/a")],
            leftovers: vec!["/a".into()],
            failures: vec![],
        };
        let body = payload("deck", &list, Some(&done));
        assert_eq!(
            (
                body["ok"].clone(),
                body["removed"].clone(),
                body["sweeping"].clone()
            ),
            (json!(true), json!(["/a"]), json!(["/a"]))
        );
        let failed = Removal {
            removed: vec![],
            leftovers: vec![],
            failures: vec![(
                target("/a"),
                Failure::Git {
                    command: "x".into(),
                    output: "boom".into(),
                },
            )],
        };
        let body = payload("deck", &list, Some(&failed));
        assert_eq!(body["ok"], false);
        assert_eq!(body["error"], "worktree não removida");
        assert_eq!(body["failed"], json!(["/a: git x falhou:\nboom"]));
    }
}

// ── O formulário de worktree (decisão 37) ──────────────────────────────────

#[test]
fn info_diz_o_que_acontece_com_cada_terminal() {
    use crate::protocol::org::WorktreeNodeState::{FollowsWorkbench, NoRepo, OwnWorktree};
    let s = Sandbox::new();
    let repo = s.repo("repo");
    let neighbor = s.repo("vizinho");
    fs::write(Path::new(&repo).join("novo.txt"), "x").unwrap();
    let mut config = WorkbenchConfig::new("deck", repo.clone(), vec![]);
    let dentro = NodeConfig::new(NodeKind::Shell, "dentro");
    let mut fora = NodeConfig::new(NodeKind::Agent, "fora");
    fora.cwd = Some(neighbor);
    let mut perdido = NodeConfig::new(NodeKind::Shell, "perdido");
    perdido.cwd = Some("/nao/existe/mesmo".into());
    config.nodes = vec![
        dentro,
        fora,
        perdido,
        NodeConfig::new(NodeKind::Web, "docs"),
    ];
    s.git(&["branch", "main-2"], &repo);

    let info = form::info(&git(), &config, &s.home(), "~/.egeon/worktree-copy.sh").unwrap();
    assert_eq!(info.suggested_branch, "main-3", "pula o nome que já existe");
    assert!(
        info.summary
            .starts_with("1 arquivo(s) novo(s) vão junto.\n")
    );
    assert!(info.summary.ends_with("por ~/.egeon/worktree-copy.sh."));
    let rows: Vec<_> = info
        .nodes
        .iter()
        .map(|n| (n.node.as_str(), n.state, n.branch.as_deref()))
        .collect();
    assert_eq!(
        rows,
        [
            ("dentro", FollowsWorkbench, None),
            ("fora", OwnWorktree, Some("main-3")),
            ("perdido", NoRepo, None),
        ],
        "o web não abre pasta, e só quem ganha worktree própria leva branch"
    );

    let outside = WorkbenchConfig::new("solto", s.path("solto"), vec![]);
    assert!(
        form::info(&git(), &outside, &s.home(), "x")
            .unwrap_err()
            .ends_with("não é repositório git")
    );
}

#[test]
fn plano_dá_o_veredito_a_pasta_e_a_linha_de_cada_nome() {
    use crate::protocol::org::BranchVerdict::{AlreadyOpen, Create, FollowRemote, OpenExisting};
    let s = Sandbox::new();
    let (repo, worktree) = s.repo_with_worktree();
    s.git(&["branch", "local-livre"], &repo);
    let remote = s.path("remoto.git");
    s.git(&["init", "-q", "--bare", &remote], &s.home());
    s.git(&["remote", "add", "origin", &remote], &repo);
    s.git(
        &["push", "-q", "origin", "main:so-remota", "main:main"],
        &repo,
    );
    s.git(&["fetch", "-q", "origin"], &repo);
    let config = WorkbenchConfig::new("deck", repo.clone(), vec![]);
    let home = s.home();
    let plan = |branch: &str| form::plan(&git(), &config, branch, &home).unwrap();

    let new = plan("nunca-vista");
    assert_eq!(new.verdict, Create);
    assert_eq!(new.folder, "~/worktrees/repo/nunca-vista");
    assert_eq!(
        new.message.as_deref(),
        Some("Branch nova · sai de main, no commit atual.")
    );
    assert_eq!(plan("local-livre").verdict, OpenExisting);
    let remote_plan = plan("so-remota");
    assert_eq!(remote_plan.verdict, FollowRemote);
    assert!(
        remote_plan
            .message
            .is_some_and(|m| m.contains("Só existe em origin/so-remota"))
    );
    let open = plan("feat");
    assert_eq!(open.verdict, AlreadyOpen);
    assert_eq!(open.folder, path_text::abbreviate_tilde(&worktree, &home));

    assert_eq!(
        form::plan(&git(), &config, "  ", &home).unwrap_err(),
        "branch inválida '  '"
    );
}

// ── Bancada nova numa worktree de uma pasta, sem origem ────────────────────

fn snapshot(workspaces: Vec<WorkspaceConfig>) -> OrgSnapshot {
    OrgSnapshot {
        workbenches: vec![WorkbenchConfig::new("existente", "/x", vec![])],
        workspaces,
    }
}

fn dupla() -> (String, WorkbenchTemplate) {
    let mut preset = WorkbenchTemplate {
        nodes: vec![
            NodeConfig::new(NodeKind::Shell, "a"),
            NodeConfig::new(NodeKind::Shell, "b"),
        ],
        base_path: None,
        view: None,
    };
    preset.view = Some(crate::features::workbench::model::ViewMode::Chat);
    ("dupla".to_owned(), preset)
}

fn no_link(_: &Path, _: &Path) -> io::Result<()> {
    Ok(())
}

#[test]
fn pasta_escolhida_vira_bancada_nova_com_os_nos_do_template() {
    let s = Sandbox::new();
    let repo = s.repo("repo");
    fs::write(Path::new(&repo).join(".env"), "x").unwrap();
    let org = snapshot(vec![]);
    let source = from_folder::Source {
        path: Some(&repo),
        project: None,
    };
    let template = dupla();
    let (reply, effects) = from_folder::from_folder(
        &git(),
        &org,
        source,
        from_folder::Branches {
            branch: "feature/x",
            repos: &BTreeMap::new(),
        },
        Some(&template),
        &s.home(),
        &no_link,
    );
    assert_eq!(reply.status, 200, "{}", reply.json);
    assert_eq!(reply.json["workbench"], "feature-x");
    assert_eq!(reply.json["branch"], "feature/x");
    let WorktreeEffect::AddWorkbench { config, copies } = &effects[0] else {
        panic!("{effects:?}");
    };
    assert_eq!(config.name, "feature-x");
    assert_eq!(config.path, "~/worktrees/repo/feature-x");
    assert_eq!(config.template.as_deref(), Some("dupla"));
    assert_eq!(config.view, template.1.view);
    assert!(config.project.is_none());
    assert!(config.color.is_some());
    let ids: Vec<_> = config.nodes.iter().map(|n| n.id.as_str()).collect();
    assert_eq!(ids, ["a", "b"]);
    assert_eq!(
        copies,
        &[(
            repo.clone(),
            reply.json["path"].as_str().unwrap().to_owned()
        )]
    );
    assert!(
        Path::new(&reply.json["path"].as_str().unwrap())
            .join("a.txt")
            .exists()
    );
}

#[test]
fn projeto_de_pasta_da_o_repositorio_e_a_bancada_fica_nele() {
    let s = Sandbox::new();
    let repo = s.repo("repo");
    let project = ProjectConfig::new("repo", repo.clone());
    let project_id = project.id.clone();
    let mut space = WorkspaceConfig::new("w");
    space.projects.push(project);
    let org = snapshot(vec![space]);
    let (reply, effects) = from_folder::from_folder(
        &git(),
        &org,
        from_folder::Source {
            path: None,
            project: Some(&project_id),
        },
        from_folder::Branches {
            branch: "",
            repos: &BTreeMap::new(),
        },
        None,
        &s.home(),
        &no_link,
    );
    // Sem branch, o app sugere uma livre a partir da atual.
    assert_eq!(reply.status, 200, "{}", reply.json);
    assert_eq!(reply.json["branch"], "main-2");
    let WorktreeEffect::AddWorkbench { config, .. } = &effects[0] else {
        panic!("{effects:?}");
    };
    assert_eq!(config.project.as_deref(), Some(project_id.as_str()));
    assert!(config.nodes.is_empty(), "sem template nasce vazia");
}

#[test]
fn multi_projeto_sem_origem_abre_uma_worktree_por_repo_e_usa_o_template() {
    let s = Sandbox::new();
    let (a, b) = (s.repo("api"), s.repo("web"));
    let (pa, pb) = (ProjectConfig::new("api", a), ProjectConfig::new("web", b));
    let mut multi = ProjectConfig::new("Nexus", s.path("links"));
    multi.members = Some(vec![pa.id.clone(), pb.id.clone()]);
    let multi_id = multi.id.clone();
    let mut space = WorkspaceConfig::new("w");
    space.projects = vec![pa, pb, multi];
    let org = snapshot(vec![space]);
    let template = dupla();
    let source = from_folder::Source {
        path: None,
        project: Some(&multi_id),
    };

    let (refused, _) = from_folder::from_folder(
        &git(),
        &org,
        source,
        from_folder::Branches {
            branch: "",
            repos: &BTreeMap::new(),
        },
        None,
        &s.home(),
        &no_link,
    );
    assert_eq!(refused.json["error"], "multi-projeto pede branch");

    let (reply, effects) = from_folder::from_folder(
        &git(),
        &org,
        source,
        from_folder::Branches {
            branch: "frente",
            repos: &BTreeMap::new(),
        },
        Some(&template),
        &s.home(),
        &no_link,
    );
    assert_eq!(reply.status, 200, "{}", reply.json);
    let WorktreeEffect::AddWorkbench { config, copies } = &effects[0] else {
        panic!("{effects:?}");
    };
    assert_eq!(config.project.as_deref(), Some(multi_id.as_str()));
    assert_eq!(config.template.as_deref(), Some("dupla"));
    assert_eq!(config.nodes.len(), 2);
    assert_eq!(copies.len(), 2, "uma cópia por repositório");
}

#[test]
fn pasta_sem_git_projeto_ou_pasta_ausentes_sao_recusados() {
    let s = Sandbox::new();
    let org = snapshot(vec![]);
    let run = |source: from_folder::Source<'_>| {
        from_folder::from_folder(
            &git(),
            &org,
            source,
            from_folder::Branches {
                branch: "x",
                repos: &BTreeMap::new(),
            },
            None,
            &s.home(),
            &no_link,
        )
        .0
        .json["error"]
            .as_str()
            .unwrap()
            .to_owned()
    };
    let plain = s.path("solta");
    fs::create_dir_all(&plain).unwrap();
    assert_eq!(
        run(from_folder::Source {
            path: Some(&plain),
            project: None
        }),
        format!("{plain} não é repositório git")
    );
    assert_eq!(
        run(from_folder::Source {
            path: None,
            project: Some("fantasma")
        }),
        "projeto desconhecido 'fantasma'"
    );
    assert_eq!(
        run(from_folder::Source::default()),
        "pede a pasta do repositório"
    );
}

// ── O que o git decidiu, sobre o estado de agora ───────────────────────────

#[test]
fn reapontar_o_no_vivo_leva_so_a_pasta_e_zera_a_conversa() {
    let mut live = NodeConfig::new(NodeKind::Agent, "dev");
    live.x = Some(500.0);
    live.model = Some("opus".into());
    live.conversation_id = Some("c".into());
    let mut snapshot = NodeConfig::new(NodeKind::Agent, "dev");
    snapshot.x = Some(1.0);
    snapshot.model = Some("sonnet".into());
    snapshot.cwd = Some("/wt/spike".into());

    let merged = merge::repoint_live(&live, &snapshot);
    assert_eq!(merged.cwd.as_deref(), Some("/wt/spike"));
    assert_eq!(
        merged.x,
        Some(500.0),
        "o card movido durante o git fica onde está"
    );
    assert_eq!(merged.model.as_deref(), Some("opus"));
    assert_eq!(merged.conversation_id, None);
}

#[test]
fn mover_a_bancada_viva_guarda_o_que_mudou_e_o_que_nasceu_durante_o_git() {
    let mut a = NodeConfig::new(NodeKind::Shell, "a");
    a.cwd = Some("api".into());
    let mut b = NodeConfig::new(NodeKind::Shell, "b");
    b.x = Some(7.0);
    let mut moved = WorkbenchConfig::new("deck", "~/worktrees/repo/x", vec![a.clone(), b.clone()]);
    moved.nodes[0].cwd = Some("api".into());

    let mut live = WorkbenchConfig::new("renomeada", "/repo", vec![a, b]);
    live.nodes[1].x = Some(900.0);
    live.nodes.push(NodeConfig::new(NodeKind::Shell, "novo"));
    live.color = Some(crate::features::workbench::model::WorkbenchColor::Teal);

    let merged = merge::move_live(&live, &moved);
    assert_eq!(merged.path, "~/worktrees/repo/x");
    assert_eq!(merged.name, "renomeada");
    assert_eq!(merged.color, live.color);
    let ids: Vec<_> = merged.nodes.iter().map(|n| n.id.as_str()).collect();
    assert_eq!(
        ids,
        ["a", "b", "novo"],
        "o nó criado durante a espera não some"
    );
    assert_eq!(merged.nodes[1].x, Some(900.0));
    assert_eq!(merged.nodes[0].cwd.as_deref(), Some("api"));
}

#[test]
fn multi_projeto_sem_origem_respeita_a_branch_de_cada_repositorio() {
    let s = Sandbox::new();
    let (a, b) = (s.repo("api"), s.repo("web"));
    let (pa, pb) = (ProjectConfig::new("api", a), ProjectConfig::new("web", b));
    let mut multi = ProjectConfig::new("Nexus", s.path("links"));
    multi.members = Some(vec![pa.id.clone(), pb.id.clone()]);
    let multi_id = multi.id.clone();
    let mut space = WorkspaceConfig::new("w");
    space.projects = vec![pa, pb, multi];
    let org = snapshot(vec![space]);
    let repos = BTreeMap::from([("web".to_owned(), "fix/web".to_owned())]);
    let (reply, effects) = from_folder::from_folder(
        &git(),
        &org,
        from_folder::Source {
            path: None,
            project: Some(&multi_id),
        },
        from_folder::Branches {
            branch: "frente",
            repos: &repos,
        },
        None,
        &s.home(),
        &no_link,
    );
    assert_eq!(reply.status, 200, "{}", reply.json);
    assert!(matches!(effects[0], WorktreeEffect::AddWorkbench { .. }));
    let root = reply.json["path"].as_str().unwrap().to_owned();
    let branch_of = |repo: &str| s.git(&["branch", "--show-current"], &format!("{root}/{repo}"));
    assert_eq!(branch_of("api").trim(), "frente");
    assert_eq!(branch_of("web").trim(), "fix/web", "a do repositório vence");
    assert!(
        root.ends_with("frente"),
        "a raiz é da branch da bancada: {root}"
    );
}

#[test]
fn formulario_sem_origem_le_a_pasta_e_da_o_nome_do_repositorio() {
    let s = Sandbox::new();
    let repo = s.repo("repo");
    let info = form::info_at(&git(), &repo, "~/repo", "copia.sh").unwrap();
    assert_eq!(info.suggested_branch, "main-2");
    assert_eq!(info.repo, "repo");
    assert!(info.nodes.is_empty(), "sem bancada não há terminais");
    assert!(info.multi.is_none());
    let plan = form::plan_at(&git(), &repo, "~/repo", "nova", &s.home()).unwrap();
    assert_eq!(plan.verdict, crate::protocol::org::BranchVerdict::Create);
    assert_eq!(plan.folder, "~/worktrees/repo/nova");

    let plain = s.path("solta");
    fs::create_dir_all(&plain).unwrap();
    assert_eq!(
        form::info_at(&git(), &plain, "~/solta", "x").unwrap_err(),
        "~/solta não é repositório git"
    );
}

#[test]
fn formulario_de_multi_projeto_da_um_campo_por_repositorio() {
    let s = Sandbox::new();
    let (pa, pb) = (
        ProjectConfig::new("api", s.path("a/api")),
        ProjectConfig::new("api", s.path("b/api")),
    );
    let mut multi = ProjectConfig::new("Nexus", s.path("links"));
    multi.members = Some(vec![pa.id.clone(), pb.id.clone()]);
    let info = form::multi_info(&multi, &[&pa, &pb], &s.home()).unwrap();
    let detail = info.multi.unwrap();
    assert_eq!(detail.project, "Nexus");
    assert_eq!(
        detail.repos,
        ["api", "api-2"],
        "o nome do link, sem repetir"
    );
    assert!(info.suggested_branch.is_empty());
    assert_eq!(
        form::multi_info(&multi, &[], &s.home()).unwrap_err(),
        "\"Nexus\" não junta pasta nenhuma"
    );
}
