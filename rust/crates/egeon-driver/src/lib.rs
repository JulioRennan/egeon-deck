//! Driver do Egeon Deck: só o acesso ao sistema operacional que muda de uma
//! plataforma para outra.
//!
//! Implementa as interfaces de `egeon_core::ports`. Um módulo por capacidade
//! e, dentro dele, um arquivo por plataforma escolhido na compilação.

// `println!` e `eprintln!` entram em pânico com stdout/stderr num cano quebrado
// (a UI morta com kill -9). O driver não escreve em nenhum dos dois; o
// compilador garante que continue assim.
#![deny(clippy::print_stdout, clippy::print_stderr)]

pub mod apps;
pub mod environment;
pub mod executable;
pub mod file_clone;
pub mod folder_access;
pub mod installer;
pub mod links;
pub mod local_conn;
pub mod main_loop;
pub mod notifier;
pub mod opener;
pub mod procs;
pub mod pty;
pub mod signals;

pub use apps::SystemApps;
pub use executable::is_executable;
pub use file_clone::SystemFileCloner;
pub use folder_access::SystemFolderPermissions;
pub use installer::SystemInstaller;
pub use links::SystemLinks;
pub use local_conn::SystemLocalConn;
pub use notifier::SystemNotifier;
pub use opener::SystemOpener;
pub use procs::SystemProcs;
pub use pty::SystemPty;
