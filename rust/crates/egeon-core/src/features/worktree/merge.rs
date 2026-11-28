//! O que o git decidiu, aplicado sobre o estado de AGORA.
//!
//! A rota `/worktree` roda sobre uma cópia da organização e leva de segundos a
//! minutos; nesse meio-tempo você move, redimensiona e edita os nós. Gravar a
//! cópia por cima apagaria essas edições, então só entra o que a worktree
//! decidiu — a pasta nova e a conversa zerada — e o resto fica como está.

use crate::features::node::model::NodeConfig;
use crate::features::workbench::model::WorkbenchConfig;

/// O nó vivo abrindo na pasta que a worktree deu, sem a conversa (ela é da
/// pasta antiga). Posição, tamanho, modelo e o mais que mudou durante o git
/// continuam os de agora.
pub fn repoint_live(live: &NodeConfig, repointed: &NodeConfig) -> NodeConfig {
    let mut node = live.clone().without_conversation();
    node.cwd.clone_from(&repointed.cwd);
    node
}

/// A bancada viva apontada para a worktree (`Target::MoveCurrent`): o caminho
/// novo e a pasta de cada nó que já existia quando o git começou. Nó criado
/// durante a espera, ligações, nome, cor e tudo mais ficam como estão.
pub fn move_live(live: &WorkbenchConfig, moved: &WorkbenchConfig) -> WorkbenchConfig {
    let mut bench = live.clone();
    bench.path.clone_from(&moved.path);
    for node in &mut bench.nodes {
        if let Some(target) = moved.nodes.iter().find(|n| n.id == node.id) {
            *node = repoint_live(node, target);
        }
    }
    bench
}
