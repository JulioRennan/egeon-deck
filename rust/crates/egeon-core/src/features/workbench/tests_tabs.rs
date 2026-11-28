//! Porte do WorkbenchTabTests, WorkbenchTabOrderTests, ActiveWorkbenchesTests,
//! TabDragLayoutTests (a conta) e dos testes de pasta do terminal.

use std::collections::HashMap;
use std::time::{Duration, SystemTime};

use super::active::ActiveWorkbenches;
use super::folders;
use super::model::WorkbenchConfig;
use super::tabs::*;
use crate::features::activity::model::ActivitySummary;

fn bench(name: &str) -> WorkbenchConfig {
    WorkbenchConfig::new(name, format!("~/{name}"), vec![])
}

fn summary(working: u32, attention: u32, done: u32, background: u32) -> ActivitySummary {
    ActivitySummary {
        working,
        attention,
        done,
        background,
        ..ActivitySummary::default()
    }
}

fn strings(items: &[&str]) -> Vec<String> {
    items.iter().map(|s| (*s).to_owned()).collect()
}

fn build(
    configs: &[WorkbenchConfig],
    open: &[String],
    active: Option<&str>,
    activity: &[(&str, ActivitySummary)],
) -> Vec<WorkbenchTab> {
    let map: HashMap<String, ActivitySummary> = activity
        .iter()
        .map(|(name, s)| ((*name).to_owned(), *s))
        .collect();
    build_tabs(open, configs, active, &map)
}

fn tab_names(tabs: &[WorkbenchTab]) -> Vec<&str> {
    tabs.iter().map(|t| t.name.as_str()).collect()
}

// ── WorkbenchTabTests ──────────────────────────────────────────────────────

#[test]
fn abas_seguem_a_ordem_em_que_voce_abriu() {
    let configs = [bench("um"), bench("dois"), bench("três")];
    let open = vec![configs[2].id.clone(), configs[0].id.clone()];
    let tabs = build(&configs, &open, Some(&configs[0].id), &[]);
    assert_eq!(
        tab_names(&tabs),
        ["três", "um"],
        "a faixa não é a ordem da lateral"
    );
    assert_eq!(
        tabs.iter().map(|t| t.is_active).collect::<Vec<_>>(),
        [false, true]
    );
}

/// Só o que está aberto entra — é a diferença entre a faixa e o catálogo.
#[test]
fn bancada_fechada_nao_e_aba() {
    let configs = [bench("um"), bench("dois")];
    let tabs = build(
        &configs,
        &[configs[1].id.clone()],
        Some(&configs[1].id),
        &[],
    );
    assert_eq!(tab_names(&tabs), ["dois"]);
}

/// Bancada removida enquanto a aba dela estava aberta não vira aba órfã.
#[test]
fn aba_de_bancada_removida_some() {
    let configs = [bench("um")];
    let tabs = build(
        &configs,
        &["sumida".to_owned(), configs[0].id.clone()],
        None,
        &[],
    );
    assert_eq!(tab_names(&tabs), ["um"]);
}

/// Os três avisos convivem e a ordem é fixa (ADR-024).
#[test]
fn os_tres_avisos_juntos_em_ordem_fixa() {
    let configs = [bench("deck")];
    let tabs = build(
        &configs,
        &[configs[0].id.clone()],
        None,
        &[("deck", summary(1, 1, 2, 0))],
    );
    assert_eq!(tabs[0].line(), "  deck ⠿ ●! ●");
    assert!(tabs[0].is_working() && tabs[0].wants_attention() && tabs[0].is_done());
}

/// Trabalho de fundo tem a ampulheta própria, não o spinner (ADR-063).
#[test]
fn fundo_mostra_a_ampulheta_e_nao_o_spinner() {
    let configs = [bench("deck")];
    let tabs = build(
        &configs,
        &[configs[0].id.clone()],
        None,
        &[("deck", summary(0, 0, 0, 1))],
    );
    assert_eq!(tabs[0].line(), "  deck ⏳");
    assert!(!tabs[0].is_working());
}

/// O estado vem por NOME de bancada e a aba é por id: renomear não apaga o badge.
#[test]
fn atividade_casa_pelo_nome_da_bancada() {
    let configs = [bench("nexus")];
    let tabs = build(
        &configs,
        &[configs[0].id.clone()],
        None,
        &[("nexus", summary(0, 1, 0, 0))],
    );
    assert!(tabs[0].wants_attention());
    assert_eq!(tabs[0].line(), "  nexus ●!");
}

#[test]
fn bancada_quieta_nao_tem_selo() {
    let configs = [bench("quieta")];
    let tabs = build(
        &configs,
        &[configs[0].id.clone()],
        Some(&configs[0].id),
        &[("quieta", ActivitySummary::default())],
    );
    assert_eq!(tabs[0].line(), "▸ quieta");
}

#[test]
fn trabalhando_e_terminou_sao_selos_diferentes() {
    let configs = [bench("a"), bench("b")];
    let open: Vec<String> = configs.iter().map(|c| c.id.clone()).collect();
    let tabs = build(
        &configs,
        &open,
        None,
        &[("a", summary(2, 0, 0, 0)), ("b", summary(0, 0, 1, 0))],
    );
    assert!(tabs[0].is_working() && !tabs[0].is_done());
    assert!(tabs[1].is_done() && !tabs[1].is_working());
    // Subindo também conta como trabalhando.
    let starting = WorkbenchTab {
        id: "x".into(),
        name: "x".into(),
        is_active: false,
        summary: ActivitySummary {
            starting: 1,
            ..ActivitySummary::default()
        },
    };
    assert!(starting.is_working());
}

/// Fechar leva para a vizinha da direita; na última, para a da esquerda.
#[test]
fn fechar_uma_aba_escolhe_a_vizinha() {
    let open = strings(&["a", "b", "c"]);
    assert_eq!(neighbour("a", &open), Some("b"));
    assert_eq!(neighbour("b", &open), Some("c"));
    assert_eq!(neighbour("c", &open), Some("b"));
    assert_eq!(neighbour("a", &strings(&["a"])), None);
    assert_eq!(neighbour("x", &open), None);
}

// ── WorkbenchTabOrderTests ─────────────────────────────────────────────────

/// Arquivo antigo não tem a chave — e tem de carregar como se estivesse
/// fechada, sem uma linha de migração.
#[test]
fn arquivo_sem_a_chave_carrega() {
    let config: WorkbenchConfig =
        serde_json::from_str(r#"{"name":"deck","path":"~/deck","nodes":[]}"#).unwrap();
    assert_eq!(config.tab_order, None);
    assert_eq!(config.name, "deck");
}

#[test]
fn a_ordem_da_aba_vai_e_volta() {
    let mut config = bench("deck");
    config.tab_order = Some(2);
    let back: WorkbenchConfig =
        serde_json::from_str(&serde_json::to_string(&config).unwrap()).unwrap();
    assert_eq!(back.tab_order, Some(2));
    assert_eq!(back.id, config.id);
}

/// Fechada não grava posição: o campo é o que separa "estava na faixa" de
/// "está só no catálogo".
#[test]
fn bancada_fechada_nao_tem_ordem() {
    let text = serde_json::to_string(&bench("parada")).unwrap();
    assert!(
        !text.contains("tabOrder"),
        "bancada fechada não escreve a chave"
    );
}

/// A ordem de reabertura é a da faixa, não a da barra lateral.
#[test]
fn reabrir_segue_as_posicoes_gravadas() {
    let mut a = bench("a");
    a.tab_order = Some(1);
    let b = bench("b");
    let mut c = bench("c");
    c.tab_order = Some(0);
    let configs = [a, b, c];
    let names: Vec<_> = tabs_to_reopen(&configs)
        .into_iter()
        .map(|w| w.name.as_str())
        .collect();
    assert_eq!(names, ["c", "a"], "b estava fechada e não reabre");
}

// ── ActiveWorkbenchesTests ─────────────────────────────────────────────────

fn now() -> SystemTime {
    SystemTime::UNIX_EPOCH + Duration::from_secs(1_800_000_000)
}

fn ago(hours: f64) -> SystemTime {
    now() - Duration::from_secs_f64(hours * 3600.0)
}

#[test]
fn so_as_de_pe_mais_novas_primeiro_cortadas_em_24_horas() {
    let last: HashMap<usize, SystemTime> = HashMap::from([
        (0, ago(30.0)),
        (1, ago(0.1)),
        (2, ago(23.9)),
        (3, ago(72.0)),
        (4, ago(0.0)),
        (5, ago(5.0)),
    ]);
    let list = ActiveWorkbenches::new(&[0, 1, 2, 3, 5], &last, now());
    assert_eq!(list.recent, [1, 5, 2]);
    assert_eq!(list.stale, [0, 3], "a 4 rodou agora, mas não está de pé");
}

#[test]
fn nunca_rodou_vai_por_ultimo_e_o_empate_guarda_a_ordem_da_lista() {
    let last: HashMap<usize, SystemTime> =
        HashMap::from([(7, ago(40.0)), (2, ago(1.0)), (9, ago(1.0))]);
    let list = ActiveWorkbenches::new(&[4, 2, 7, 9], &last, now());
    assert_eq!(list.recent, [2, 9]);
    assert_eq!(list.stale, [7, 4]);
}

#[test]
fn vazio() {
    let last = HashMap::from([(0, now())]);
    assert!(ActiveWorkbenches::new(&[], &last, now()).is_empty());
    assert!(!ActiveWorkbenches::new(&[0], &last, now()).is_empty());
}

#[test]
fn instante_no_futuro_conta_como_agora_e_a_borda_de_24h_ja_e_parada() {
    let last = HashMap::from([(0, now() + Duration::from_secs(60)), (1, ago(24.0))]);
    let list = ActiveWorkbenches::new(&[0, 1], &last, now());
    assert_eq!(list.recent, [0]);
    assert_eq!(list.stale, [1]);
}

// ── TabDragLayoutTests ─────────────────────────────────────────────────────

const WIDTHS: [f64; 3] = [100.0, 160.0, 120.0];
const START: f64 = 10.0;
const GAP: f64 = 4.0;

fn center_of(index: usize) -> f64 {
    tab_offsets(&WIDTHS, START, GAP)[index] + WIDTHS[index] / 2.0
}

fn destination(center: f64, dragging: usize) -> usize {
    tab_destination(center, dragging, &WIDTHS, START, GAP)
}

#[test]
fn deslocamentos_empilham_com_o_vao() {
    assert_eq!(tab_offsets(&WIDTHS, START, GAP), [10.0, 114.0, 278.0]);
    assert!(tab_offsets(&[], START, GAP).is_empty());
}

#[test]
fn parado_guarda_a_posicao() {
    for i in 0..WIDTHS.len() {
        assert_eq!(destination(center_of(i), i), i);
    }
}

/// Só troca depois de passar o CENTRO da vizinha — encostar não basta.
#[test]
fn encostar_na_vizinha_nao_basta() {
    assert_eq!(destination(center_of(1) - 1.0, 0), 0);
    assert_eq!(destination(center_of(1) + 1.0, 0), 1);
}

#[test]
fn arrastar_ate_o_fim_e_ate_o_comeco() {
    assert_eq!(destination(10_000.0, 0), 2);
    assert_eq!(destination(-10_000.0, 2), 0);
}

/// Arrastar para fora da faixa não inventa índice: prende nas pontas.
#[test]
fn alem_das_bordas_prende_em_vez_de_estourar() {
    let alvo = destination(99_999.0, 1);
    assert_eq!(alvo, 2);
    assert!(alvo < WIDTHS.len());
}

#[test]
fn moved_tira_e_poe_de_volta() {
    let abc = strings(&["a", "b", "c"]);
    assert_eq!(moved(&abc, 0, 2), ["b", "c", "a"]);
    assert_eq!(moved(&abc, 2, 0), ["c", "a", "b"]);
    assert_eq!(moved(&abc, 1, 1), ["a", "b", "c"]);
    assert_eq!(moved(&abc, 5, 0), ["a", "b", "c"]);
    assert_eq!(moved(&abc, 0, 5), ["a", "b", "c"]);
    assert_eq!(moved::<String>(&[], 0, 0), Vec::<String>::new());
}

/// Índice fora da lista não derruba nem reordena nada — é o estado em que o
/// arrasto fica se a bancada sair da faixa no meio dele.
#[test]
fn indice_desconhecido_e_inerte() {
    assert_eq!(destination(50.0, 9), 9);
}

// ── FolderSuggestions / opções de pasta ────────────────────────────────────

#[test]
fn so_o_que_esta_dentro_da_bancada_relativo() {
    assert_eq!(folders::list(&strings(&["web", "back"])), ["back", "web"]);
}

#[cfg(unix)]
#[test]
fn filhos_de_repo_sao_pastas_ou_links_com_git() {
    let tmp = tempfile::tempdir().unwrap();
    let root = tmp.path();
    std::fs::create_dir_all(root.join("repo/.git")).unwrap();
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::create_dir_all(root.join(".oculta/.git")).unwrap();
    std::os::unix::fs::symlink(root.join("repo"), root.join("link")).unwrap();
    let mut found = folders::repo_children(root);
    found.sort();
    assert_eq!(found, ["link", "repo"]);
}

#[test]
fn a_raiz_aparece_como_root_para_vazio() {
    assert_eq!(folders::shown(None), "root");
    assert_eq!(folders::shown(Some("")), "root");
    assert_eq!(folders::shown(Some("nexus-backend")), "nexus-backend");
}

#[test]
fn a_lista_de_pasta_comeca_na_raiz_e_guarda_a_atual_customizada() {
    assert_eq!(
        folders::folder_options("", &strings(&["web", "back"])),
        ["", "web", "back"]
    );
    assert_eq!(
        folders::folder_options("~/outro", &strings(&["web"])),
        ["", "web", "~/outro"]
    );
    assert_eq!(
        folders::folder_options("web", &strings(&["web"])),
        ["", "web"]
    );
    assert_eq!(
        folders::folder_options("", &strings(&["", "web"])),
        ["", "web"]
    );
}
