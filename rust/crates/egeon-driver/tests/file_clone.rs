//! Clone de verdade, em pasta temporária.

use std::fs;
use std::io;
use std::os::unix::fs::symlink;
use std::path::Path;

use egeon_core::ports::file_clone::FileCloner;
use egeon_driver::SystemFileCloner;

fn write_tree(root: &Path) -> io::Result<()> {
    fs::create_dir_all(root.join("node_modules/pacote"))?;
    for i in 0..300 {
        fs::write(
            root.join(format!("node_modules/pacote/f{i}.js")),
            format!("// {i}"),
        )?;
    }
    symlink("pacote/f1.js", root.join("node_modules/atalho"))?;
    symlink("nao-existe", root.join("node_modules/quebrado"))?;
    Ok(())
}

#[test]
fn clona_a_pasta_com_todos_os_arquivos_e_links_como_links() -> io::Result<()> {
    let dir = tempfile::tempdir()?;
    write_tree(&dir.path().join("origem"))?;
    let (from, to) = (
        dir.path().join("origem/node_modules"),
        dir.path().join("novo"),
    );
    fs::create_dir(&to)?;
    SystemFileCloner.clone_entry(&from, &to.join("node_modules"))?;

    let copy = to.join("node_modules");
    assert_eq!(fs::read_dir(copy.join("pacote"))?.count(), 300);
    assert_eq!(fs::read_to_string(copy.join("pacote/f42.js"))?, "// 42");
    assert_eq!(
        fs::read_link(copy.join("atalho"))?,
        Path::new("pacote/f1.js")
    );
    assert_eq!(
        fs::read_link(copy.join("quebrado"))?,
        Path::new("nao-existe")
    );
    Ok(())
}

#[test]
fn clone_e_independente_do_original() -> io::Result<()> {
    let dir = tempfile::tempdir()?;
    fs::write(dir.path().join("a"), "original")?;
    SystemFileCloner.clone_entry(&dir.path().join("a"), &dir.path().join("b"))?;
    fs::write(dir.path().join("b"), "mudou")?;
    assert_eq!(fs::read_to_string(dir.path().join("a"))?, "original");
    Ok(())
}

#[test]
fn link_simbolico_e_clonado_como_link_e_nunca_seguido() -> io::Result<()> {
    let dir = tempfile::tempdir()?;
    fs::create_dir(dir.path().join("alvo"))?;
    symlink("alvo", dir.path().join("l"))?;
    SystemFileCloner.clone_entry(&dir.path().join("l"), &dir.path().join("l2"))?;
    assert_eq!(fs::read_link(dir.path().join("l2"))?, Path::new("alvo"));
    Ok(())
}

#[test]
fn destino_que_ja_existe_nao_e_sobrescrito() -> io::Result<()> {
    let dir = tempfile::tempdir()?;
    fs::write(dir.path().join("a"), "novo")?;
    fs::write(dir.path().join("b"), "velho")?;
    assert!(
        SystemFileCloner
            .clone_entry(&dir.path().join("a"), &dir.path().join("b"))
            .is_err()
    );
    assert_eq!(fs::read_to_string(dir.path().join("b"))?, "velho");
    Ok(())
}

#[test]
fn origem_que_nao_existe_e_erro() -> io::Result<()> {
    let dir = tempfile::tempdir()?;
    let result = SystemFileCloner.clone_entry(&dir.path().join("nada"), &dir.path().join("x"));
    assert!(result.is_err());
    Ok(())
}

#[test]
fn link_e_bit_de_execucao() {
    use egeon_core::ports::links::FileLinks;
    use egeon_driver::SystemLinks;
    use std::os::unix::fs::PermissionsExt;

    let dir = tempfile::tempdir().unwrap();
    let target = dir.path().join("alvo");
    fs::write(&target, "x").unwrap();
    let link = dir.path().join("link");
    SystemLinks.symlink(&target, &link).unwrap();
    assert_eq!(fs::read_link(&link).unwrap(), target);
    assert!(
        SystemLinks.symlink(&target, &link).is_err(),
        "link existente é erro"
    );

    fs::set_permissions(&target, fs::Permissions::from_mode(0o600)).unwrap();
    SystemLinks.make_executable(&target).unwrap();
    assert_eq!(
        fs::metadata(&target).unwrap().permissions().mode() & 0o777,
        0o755
    );
}
