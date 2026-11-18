//! Clonar arquivo, pasta ou link: implementa `ports::file_clone::FileCloner`.

use std::fs::{self, OpenOptions};
use std::io;
use std::os::unix::fs::symlink;
use std::path::Path;

use egeon_core::ports::file_clone::FileCloner;

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
use macos as platform;

/// O clonador do sistema em que o programa roda.
#[derive(Debug, Clone, Copy, Default)]
pub struct SystemFileCloner;

impl FileCloner for SystemFileCloner {
    fn clone_entry(&self, from: &Path, to: &Path) -> io::Result<()> {
        // Clone do sistema de arquivos, e cópia comum quando ele não dá —
        // outro volume, outro sistema de arquivos.
        match platform::clone(from, to) {
            Ok(()) => Ok(()),
            Err(_) => copy_tree(from, to),
        }
    }
}

/// Cópia comum: nunca segue link, e nunca escreve por cima do que já existe
/// (o contrato é `to` ainda não existir; se existir, a cópia falha).
fn copy_tree(from: &Path, to: &Path) -> io::Result<()> {
    let meta = fs::symlink_metadata(from)?;
    let kind = meta.file_type();
    if kind.is_symlink() {
        return symlink(fs::read_link(from)?, to);
    }
    if kind.is_dir() {
        fs::create_dir(to)?;
        for entry in fs::read_dir(from)? {
            let entry = entry?;
            copy_tree(&entry.path(), &to.join(entry.file_name()))?;
        }
        // Depois dos filhos: uma pasta sem escrita não receberia os arquivos, e
        // gravar neles mudaria a data da pasta.
        return finish(to, &meta);
    }
    let mut source = fs::File::open(from)?;
    let mut target = OpenOptions::new().write(true).create_new(true).open(to)?;
    io::copy(&mut source, &mut target)?;
    target.set_modified(meta.modified()?)?;
    drop(target);
    fs::set_permissions(to, meta.permissions())
}

/// Permissões e data de modificação da pasta, como o `copyItem` do Swift.
fn finish(to: &Path, meta: &fs::Metadata) -> io::Result<()> {
    fs::set_permissions(to, meta.permissions())?;
    fs::File::open(to)?.set_modified(meta.modified()?)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tree(root: &Path) -> io::Result<()> {
        fs::create_dir_all(root.join("a/b"))?;
        fs::write(root.join("a/b/f.txt"), "conteúdo")?;
        fs::write(root.join("a/g.txt"), "g")?;
        symlink("b/f.txt", root.join("a/atalho"))?;
        symlink("nao-existe", root.join("a/quebrado"))?;
        Ok(())
    }

    #[test]
    fn copia_comum_leva_a_arvore_e_preserva_links() -> io::Result<()> {
        let dir = tempfile::tempdir()?;
        tree(&dir.path().join("origem"))?;
        copy_tree(&dir.path().join("origem"), &dir.path().join("copia"))?;
        let copy = dir.path().join("copia");
        assert_eq!(fs::read_to_string(copy.join("a/b/f.txt"))?, "conteúdo");
        assert_eq!(fs::read_link(copy.join("a/atalho"))?, Path::new("b/f.txt"));
        assert_eq!(
            fs::read_link(copy.join("a/quebrado"))?,
            Path::new("nao-existe")
        );
        Ok(())
    }

    #[test]
    fn copia_comum_guarda_a_data_de_modificacao() -> io::Result<()> {
        let dir = tempfile::tempdir()?;
        tree(&dir.path().join("origem"))?;
        let old = std::time::SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(1_000_000_000);
        for path in ["a/b/f.txt", "a/b", "a"] {
            fs::File::open(dir.path().join("origem").join(path))?.set_modified(old)?;
        }
        copy_tree(&dir.path().join("origem"), &dir.path().join("copia"))?;
        for path in ["a/b/f.txt", "a/b", "a"] {
            let copied = fs::metadata(dir.path().join("copia").join(path))?.modified()?;
            assert_eq!(copied, old, "{path}");
        }
        Ok(())
    }

    #[test]
    fn copia_comum_nao_escreve_por_cima() -> io::Result<()> {
        let dir = tempfile::tempdir()?;
        fs::write(dir.path().join("a"), "novo")?;
        fs::write(dir.path().join("b"), "velho")?;
        assert!(copy_tree(&dir.path().join("a"), &dir.path().join("b")).is_err());
        assert_eq!(fs::read_to_string(dir.path().join("b"))?, "velho");
        Ok(())
    }
}
