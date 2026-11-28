//! A bancada: modelo, `workbenches.json`, `templates.json`, cor, as regras de
//! achar e de copiar, a faixa de abas, as ativas e as pastas do terminal.

pub mod access;
pub mod active;
pub mod cleaner;
pub mod clock;
pub mod folders;
pub mod frames;
pub mod model;
pub mod removal;
pub mod service;
pub mod store;
pub mod tabs;

pub use model::{NodeDirectory, ViewMode, WorkbenchColor, WorkbenchConfig, WorkbenchTemplate};

#[cfg(test)]
mod tests;
#[cfg(test)]
mod tests_clean;
#[cfg(test)]
mod tests_frames;
#[cfg(test)]
mod tests_tabs;
