//! `clonefile` do APFS: clona uma árvore inteira numa chamada só.

use std::ffi::CString;
use std::io;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;

/// `CLONE_NOFOLLOW` do `<sys/clonefile.h>`: link simbólico é clonado como link.
const CLONE_NOFOLLOW: u32 = 0x0001;

pub(super) fn clone(from: &Path, to: &Path) -> io::Result<()> {
    let from = CString::new(from.as_os_str().as_bytes())?;
    let to = CString::new(to.as_os_str().as_bytes())?;
    // SAFETY: as duas são strings C válidas durante a chamada.
    if unsafe { libc::clonefile(from.as_ptr(), to.as_ptr(), CLONE_NOFOLLOW) } == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::*;

    /// O `TMPDIR` do macOS é APFS: aqui o clone nativo tem de funcionar, e não a
    /// cópia comum que o esconderia.
    #[test]
    fn clona_a_pasta_inteira_no_apfs() -> io::Result<()> {
        let dir = tempfile::tempdir()?;
        fs::create_dir_all(dir.path().join("a/b"))?;
        fs::write(dir.path().join("a/b/f"), "x")?;
        clone(&dir.path().join("a"), &dir.path().join("c"))?;
        assert_eq!(fs::read_to_string(dir.path().join("c/b/f"))?, "x");
        Ok(())
    }
}
