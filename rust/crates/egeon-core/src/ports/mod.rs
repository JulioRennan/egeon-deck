//! Interfaces que o core define e que driver e terminal implementam.
//!
//! Têm o formato do que o core precisa, não o da API do sistema. Só existe
//! interface para o que varia de plataforma para plataforma.

pub mod file_clone;
pub mod folder_access;
pub mod installer;
pub mod links;
pub mod local_conn;
pub mod notifier;
pub mod opener;
pub mod procs;
pub mod pty;
pub mod screen;
