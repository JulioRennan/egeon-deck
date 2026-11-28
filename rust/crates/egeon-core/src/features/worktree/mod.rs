//! Worktree do git: abrir uma segunda frente do mesmo repositório sem mexer no
//! checkout onde você está, uma por bancada e uma por terminal, e levar junto o
//! que o git não versiona.

pub mod copy;
pub mod duplicate;
pub mod form;
pub mod from_folder;
pub mod git;
pub mod merge;
pub mod model;
pub mod node;
pub mod removal_plan;
pub mod routes;
pub mod service;

pub use git::Git;
pub use model::{BranchIndex, BranchPlan, Created, Failure, Losses, Status};
pub use node::NodeWorktree;

#[cfg(test)]
mod tests;
