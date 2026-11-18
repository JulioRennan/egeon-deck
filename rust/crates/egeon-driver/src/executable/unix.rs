//! `access(X_OK)`, como o `isExecutableFile` do Swift: vale o bit de quem roda
//! (dono, grupo ou outros), seguindo links como o `PATH` faz.

use std::ffi::CString;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;

pub(super) fn is_executable(path: &Path) -> bool {
    let Ok(path) = CString::new(path.as_os_str().as_bytes()) else {
        return false;
    };
    // SAFETY: `path` é uma string C válida durante a chamada.
    unsafe { libc::access(path.as_ptr(), libc::X_OK) == 0 }
}
