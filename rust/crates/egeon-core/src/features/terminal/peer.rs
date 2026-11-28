//! De qual terminal partiu uma conexão: o pid do par, subindo a árvore de
//! pais até achar o shell de um nó.
//!
//! Vem do kernel e não do pedido de propósito: com o remetente num campo do
//! corpo, as guardas de cadeia ficavam penduradas em texto que o próprio
//! agente escrevia.

/// Saltos até desistir. Rede contra uma cadeia de `ppid` em ciclo: não deve
/// acontecer, e um laço infinito travaria a conexão.
const MAX_HOPS: usize = 32;

/// O primeiro de `pid` para cima que `known` reconhece — o próprio `pid`
/// inclusive. `None` quando a cadeia chega ao `launchd` (pid 1) sem dono: é
/// uma conexão sua, de um `curl` ou de um teste, não de um terminal.
///
/// `parent_of` é a tabela de processos (`ProcessDriver::parent_of`) e
/// bloqueia: chamar fora do ator.
pub fn owner(
    pid: u32,
    known: impl Fn(u32) -> bool,
    parent_of: impl Fn(u32) -> Option<u32>,
) -> Option<u32> {
    let mut current = pid;
    for _ in 0..MAX_HOPS {
        if known(current) {
            return Some(current);
        }
        match parent_of(current) {
            Some(parent) if parent > 1 => current = parent,
            _ => return None,
        }
    }
    None
}

/// `pid` e os pais dele, até o `launchd` ou o teto. A conexão lê a cadeia
/// fora do ator (a tabela de processos bloqueia), e o ator acha nela o dono
/// com [`owner`] sobre os shells que conhece.
pub fn ancestry(pid: u32, parent_of: impl Fn(u32) -> Option<u32>) -> Vec<u32> {
    let mut chain = vec![pid];
    let mut current = pid;
    for _ in 1..MAX_HOPS {
        match parent_of(current) {
            Some(parent) if parent > 1 => {
                chain.push(parent);
                current = parent;
            }
            _ => break,
        }
    }
    chain
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn table(pairs: &[(u32, u32)]) -> HashMap<u32, u32> {
        pairs.iter().copied().collect()
    }

    /// A cadeia lida de uma vez dá o mesmo dono que a subida com a tabela.
    #[test]
    fn ascendencia_da_o_mesmo_dono() {
        let parents = table(&[(900, 800), (800, 700), (700, 500), (500, 100), (100, 1)]);
        let chain = ancestry(900, |p| parents.get(&p).copied());
        assert_eq!(chain, [900, 800, 700, 500, 100]);
        let lookup = |p: u32| {
            chain
                .iter()
                .position(|c| *c == p)
                .and_then(|i| chain.get(i + 1).copied())
        };
        assert_eq!(owner(900, |p| p == 500, lookup), Some(500));
        assert_eq!(ancestry(10, |_| Some(1)), [10]);
        let cycle = table(&[(10, 11), (11, 10)]);
        assert_eq!(ancestry(10, |p| cycle.get(&p).copied()).len(), MAX_HOPS);
    }

    #[test]
    fn o_proprio_pid_pode_ser_o_dono() {
        let parents = table(&[(500, 1)]);
        assert_eq!(
            owner(500, |p| p == 500, |p| parents.get(&p).copied()),
            Some(500)
        );
    }

    #[test]
    fn sobe_a_arvore_ate_o_shell_do_no() {
        // egeon (900) ← bash do agente (800) ← claude (700) ← zsh do nó (500) ← app (100)
        let parents = table(&[(900, 800), (800, 700), (700, 500), (500, 100), (100, 1)]);
        let shells = [500, 501];
        assert_eq!(
            owner(900, |p| shells.contains(&p), |p| parents.get(&p).copied()),
            Some(500)
        );
    }

    #[test]
    fn sem_dono_ate_o_launchd_e_conexao_de_fora() {
        let parents = table(&[(900, 800), (800, 1)]);
        assert_eq!(owner(900, |p| p == 500, |p| parents.get(&p).copied()), None);
    }

    #[test]
    fn processo_que_sumiu_no_meio_da_subida_nao_tem_dono() {
        let parents = table(&[(900, 800)]);
        assert_eq!(owner(900, |p| p == 500, |p| parents.get(&p).copied()), None);
    }

    #[test]
    fn ciclo_de_ppid_desiste_no_teto() {
        let parents = table(&[(10, 11), (11, 10)]);
        let asked = std::cell::Cell::new(0);
        let found = owner(
            10,
            |_| false,
            |p| {
                asked.set(asked.get() + 1);
                parents.get(&p).copied()
            },
        );
        assert_eq!(found, None);
        assert_eq!(asked.get(), MAX_HOPS);
    }
}
