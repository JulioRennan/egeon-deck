//! Porte de WorkbenchConfigTests, WorkbenchStoreTests, WorkbenchColorTests,
//! WorkbenchLookupTests e da parte de bancada de RetiredNodeTests.

use std::fs;

use super::model::*;
use super::service::*;
use super::store;
use crate::commons::ids::Address;
use crate::features::node::model::{NodeConfig, NodeKind};

const HOME: &str = "/Users/eu";

fn workbench(json: &str) -> WorkbenchConfig {
    serde_json::from_str(json).unwrap()
}

fn bench(name: &str, color: Option<WorkbenchColor>) -> WorkbenchConfig {
    let mut w = WorkbenchConfig::new(name, "/tmp", vec![]);
    w.color = color;
    w
}

// ── WorkbenchConfigTests ───────────────────────────────────────────────────

#[test]
fn endereco_e_bancada_barra_no() {
    let ws = workbench(
        r#"{"name":"deck","path":"/tmp/deck","nodes":[{"type":"agent","id":"revisor"}]}"#,
    );
    assert_eq!(ws.address_of(&ws.nodes[0]), "deck/revisor");
}

#[test]
fn alvos_sao_so_as_arestas_de_saida() {
    let ws = workbench(
        r#"{"name":"deck","path":"/tmp/deck","nodes":[],
            "edges":[{"from":"a","to":"b"},{"from":"b","to":"a"},{"from":"a","to":"c"}]}"#,
    );
    assert_eq!(ws.targets("a"), ["b", "c"]);
    assert!(ws.targets("c").is_empty());
}

// O teto de visitas da bancada saiu (ADR-077): o campo gravado antes não
// quebra a leitura.
#[test]
fn maxvisits_antigo_e_ignorado() {
    let ws = workbench(r#"{"name":"deck","path":"/t","nodes":[],"maxVisits":10}"#);
    assert_eq!(ws.name, "deck");
}

// As três formas de cwd, cada uma com seu motivo. `..` resolve só pelo texto.
#[test]
fn resolve_cwd_nas_tres_formas() {
    let root = "/repos/deck";
    assert_eq!(
        WorkbenchConfig::resolve("packages/api", root, HOME),
        "/repos/deck/packages/api"
    );
    assert_eq!(
        WorkbenchConfig::resolve("/outra/casa", root, HOME),
        "/outra/casa"
    );
    assert_eq!(
        WorkbenchConfig::resolve("../vizinho", root, HOME),
        "/repos/vizinho"
    );
    assert_eq!(WorkbenchConfig::resolve("~", root, HOME), HOME);
    assert_eq!(WorkbenchConfig::resolve("~/x", root, HOME), "/Users/eu/x");
}

#[test]
fn diretorio_resolvido_sem_cwd_e_a_raiz() {
    let ws = workbench(r#"{"name":"d","path":"/repos/deck","nodes":[{"type":"shell","id":"t1"}]}"#);
    assert_eq!(ws.resolved_directory(&ws.nodes[0], HOME), "/repos/deck");
}

#[test]
fn cwd_que_nao_existe_cai_na_raiz_falando() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().to_str().unwrap().to_owned();
    fs::create_dir_all(dir.path().join("api")).unwrap();
    let mut ws = WorkbenchConfig::new("deck", root.clone(), vec![]);
    let mut ok = NodeConfig::new(NodeKind::Shell, "ok");
    ok.cwd = Some("api".into());
    let mut perdido = NodeConfig::new(NodeKind::Shell, "perdido");
    perdido.cwd = Some("../nexus-backend".into());
    let solto = NodeConfig::new(NodeKind::Shell, "solto");
    ws.nodes = vec![ok.clone(), perdido.clone(), solto.clone()];

    let achado = ws.directory(&ok, HOME);
    assert_eq!(achado.path, format!("{root}/api"));
    assert_eq!(achado.warning, None);

    let caiu = ws.directory(&perdido, HOME);
    assert_eq!(caiu.path, root);
    let aviso = caiu.warning.unwrap();
    assert!(
        aviso.contains("perdido") && aviso.contains("../nexus-backend"),
        "{aviso}"
    );

    assert_eq!(ws.directory(&solto, HOME).warning, None);
    assert_eq!(ws.unresolved_directories(HOME).len(), 1);
    assert_eq!(ws.unresolved_directories(HOME)[0].0, "perdido");
}

#[test]
fn pasta_da_bancada_expande_til_e_nome_da_pasta() {
    let ws = WorkbenchConfig::new("d", "~/repos/deck/", vec![]);
    assert_eq!(ws.url_path(HOME), "/Users/eu/repos/deck");
    assert_eq!(ws.folder_name(HOME), "deck");
    assert!(!ws.exists(HOME));
}

// ── WorkbenchTemplateTests ─────────────────────────────────────────────────

// Um molde não carrega o que foi dito dentro dele.
#[test]
fn captura_tira_a_conversa_e_reduz_o_web_a_origem() {
    let ws = workbench(
        r#"{"name":"deck","path":"/tmp/deck","nodes":[
          {"type":"agent","id":"a","agent":"claude","conversationId":"C1",
           "conversationStarted":true,"transcript":"/t.jsonl","prompt":"papel"},
          {"type":"web","id":"w","url":"http://localhost:3000/farms/123?x=1"}]}"#,
    );
    let template = capture_template(&ws);
    assert_eq!(template.nodes[0].conversation_id, None);
    assert_eq!(template.nodes[0].transcript, None);
    assert_eq!(template.nodes[0].prompt.as_deref(), Some("papel"));
    // Reabrir a rota exata herdaria o estado de navegação de outra bancada.
    assert_eq!(
        template.nodes[1].url.as_deref(),
        Some("http://localhost:3000")
    );
    assert_eq!(template.base_path.as_deref(), Some("/tmp/deck"));
}

// Template salvo por versão antiga pode ter conversa dentro; instanciar zera de
// novo para não ressuscitar a conversa alheia.
#[test]
fn instanciar_zera_a_conversa_de_novo() {
    let old: WorkbenchTemplate = serde_json::from_str(
        r#"{"nodes":[{"type":"agent","id":"a","conversationId":"VELHA"}],"basePath":"/tmp/deck"}"#,
    )
    .unwrap();
    assert_eq!(old.instantiate()[0].conversation_id, None);
}

#[test]
fn origem_da_url_do_template() {
    assert_eq!(
        base_url("http://localhost:3000/farms/123"),
        "http://localhost:3000"
    );
    assert_eq!(base_url("https://x.dev"), "https://x.dev");
    assert_eq!(
        base_url("https://u:p@x.dev:8443/a?b#c"),
        "https://x.dev:8443"
    );
    assert_eq!(base_url("https://x.dev?q=1"), "https://x.dev");
    assert_eq!(base_url("http://[::1]:3000/a"), "http://[::1]:3000");
    // Não é URL com esquema e host: volta como veio.
    assert_eq!(base_url("localhost:3000/a"), "localhost:3000/a");
    assert_eq!(base_url("http://"), "http://");
    assert_eq!(base_url("http://a b/c"), "http://a b/c");
}

#[test]
fn resumo_do_template_conta_por_tipo_e_cita_a_pasta() {
    let ws = workbench(
        r#"{"name":"deck","path":"~/deck","nodes":[
            {"type":"agent","id":"a"},{"type":"agent","id":"b"},
            {"type":"shell","id":"c"},{"type":"queue","id":"f"}]}"#,
    );
    assert_eq!(
        template_summary(&ws),
        "2 agentes, 1 terminal — com posição, tamanho, pasta de cada nó e ~/deck como pasta inicial."
    );
    let web = workbench(
        r#"{"name":"w","path":"/tmp","nodes":[{"type":"web","id":"w1"},{"type":"web","id":"w2"}]}"#,
    );
    assert!(template_summary(&web).starts_with("2 webs — "));
}

// ── WorkbenchIDTests ───────────────────────────────────────────────────────

#[test]
fn id_novo_tem_oito_hex_e_nao_repete() {
    let id = new_id();
    assert_eq!(id.len(), 8);
    assert!(
        id.bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    );
    assert_ne!(id, new_id());
}

#[test]
fn arquivo_antigo_ganha_id_e_o_guarda() {
    let ws = workbench(r#"{"name":"deck","path":"/tmp/deck","nodes":[]}"#);
    assert_eq!(ws.id.len(), 8);
    let again: WorkbenchConfig =
        serde_json::from_str(&serde_json::to_string(&ws).unwrap()).unwrap();
    assert_eq!(again.id, ws.id);
}

#[test]
fn id_gravado_vence() {
    let ws = workbench(r#"{"id":"3f9a2c1d","name":"deck","path":"/tmp/deck","nodes":[]}"#);
    assert_eq!(ws.id, "3f9a2c1d");
    // `null` conta como ausente.
    assert_eq!(
        workbench(r#"{"id":null,"name":"d","path":"/t"}"#).id.len(),
        8
    );
}

// Duas bancadas com o mesmo nome são duas bancadas.
#[test]
fn mesmo_nome_ids_diferentes() {
    let a = WorkbenchConfig::new("deck", "/tmp/a", vec![]);
    let b = WorkbenchConfig::new("deck", "/tmp/a", vec![]);
    assert_ne!(a.id, b.id);
}

/// O campo novo que não entra na leitura E na gravação some do disco sem erro
/// nenhum — foi o que aconteceu com as regras (ADR-056).
#[test]
fn regras_sobrevivem_a_gravar_e_reler() {
    let json = r#"{"name":"deck","path":"/tmp","nodes":[],
        "rules":"escreva em português\npeça antes de commitar"}"#;
    let decoded = workbench(json);
    assert_eq!(
        decoded.rules.as_deref(),
        Some("escreva em português\npeça antes de commitar")
    );
    let again: WorkbenchConfig =
        serde_json::from_str(&serde_json::to_string(&decoded).unwrap()).unwrap();
    assert_eq!(
        again.rules, decoded.rules,
        "gravar e reler não pode perder a regra"
    );
}

/// Todo campo da bancada vai e volta — a guarda contra o campo esquecido num
/// dos dois lados.
#[test]
fn todo_campo_da_bancada_vai_e_volta() {
    let mut w = WorkbenchConfig::new(
        "deck",
        "~/deck",
        vec![NodeConfig::new(NodeKind::Shell, "t")],
    );
    w.template = Some("padrao".into());
    w.project = Some("p1".into());
    w.edges = Some(vec![crate::features::edge::EdgeConfig::new(
        "a",
        "b",
        Some(4),
    )]);
    w.rules = Some("r".into());
    w.view = Some(ViewMode::Chat);
    w.tab_order = Some(3);
    w.tab_active = Some(true);
    w.color = Some(WorkbenchColor::DeepPurple);
    let text = serde_json::to_string(&w).unwrap();
    for key in [
        "template",
        "project",
        "edges",
        "rules",
        "view",
        "tabOrder",
        "tabActive",
        "color",
    ] {
        assert!(text.contains(&format!("\"{key}\"")), "{key} sumiu: {text}");
    }
    let back: WorkbenchConfig = serde_json::from_str(&text).unwrap();
    assert_eq!(back, w);
    assert_eq!(back.edges.unwrap()[0].max_sends, Some(4));
}

// ── ViewMode ───────────────────────────────────────────────────────────────

// Modo que sai do app continua gravado no arquivo de quem o usou — o `mosaic`,
// removido. Valor desconhecido vira canvas em vez de derrubar a carga.
#[test]
fn modo_desconhecido_vira_canvas() {
    let w = workbench(r#"{"name":"a","path":"/t","nodes":[],"view":"mosaic"}"#);
    assert_eq!(w.view, Some(ViewMode::Canvas));
    assert_eq!(
        workbench(r#"{"name":"a","path":"/t","view":"chat"}"#).view_mode(),
        ViewMode::Chat
    );
    assert_eq!(
        workbench(r#"{"name":"a","path":"/t"}"#).view_mode(),
        ViewMode::Canvas
    );
    assert_eq!(
        workbench(r#"{"name":"a","path":"/t","view":null}"#).view,
        None
    );
    // Não é texto: erro, como no Swift.
    assert!(
        serde_json::from_str::<WorkbenchConfig>(r#"{"name":"a","path":"/t","view":5}"#).is_err()
    );
}

// ── RetiredNodeTests (bancada e template) ──────────────────────────────────

#[test]
fn bancada_tira_o_editor_e_guarda_o_resto() {
    let json = r#"{"name":"deck","path":"/tmp","nodes":[
        {"type":"editor","id":"code"},
        {"type":"agent","id":"claude","agent":"claude"},
        {"type":"shell","id":"sh"}]}"#;
    let ids: Vec<_> = workbench(json).nodes.into_iter().map(|n| n.id).collect();
    assert_eq!(ids, ["claude", "sh"]);
}

#[test]
fn outro_no_ruim_continua_sendo_erro() {
    let json = r#"{"name":"deck","path":"/tmp","nodes":[{"type":"robo","id":"x"}]}"#;
    assert!(serde_json::from_str::<WorkbenchConfig>(json).is_err());
}

#[test]
fn template_de_bancada_tira_o_editor() {
    let json = r#"{"basePath":"/tmp","view":"chat","nodes":[{"type":"editor","id":"code"},{"type":"web","id":"docs"}]}"#;
    let t: WorkbenchTemplate = serde_json::from_str(json).unwrap();
    assert_eq!(
        t.nodes.iter().map(|n| n.id.as_str()).collect::<Vec<_>>(),
        ["docs"]
    );
    assert_eq!(t.view, Some(ViewMode::Chat));
    assert_eq!(t.base_path.as_deref(), Some("/tmp"));
}

// ── WorkbenchColorTests ────────────────────────────────────────────────────

use WorkbenchColor as C;

#[test]
fn escolhe_a_menos_usada_e_a_primeira_no_empate() {
    assert_eq!(pick_color(&[]), C::Blue);
    assert_eq!(pick_color(&[Some(C::Blue), None]), C::Violet);
    let mut all: Vec<_> = C::AUTOMATIC.iter().copied().map(Some).collect();
    all.extend([Some(C::Blue), Some(C::Violet)]);
    assert_eq!(pick_color(&all), C::Pink);
}

// Escolhida à mão vale qualquer uma; o app sozinho nunca dá laranja, verde ou
// vermelho, que falam de estado nos badges (ADR-024).
#[test]
fn cores_de_estado_ficam_fora_da_escolha_automatica() {
    for color in C::AUTOMATIC {
        let (r, g, b) = color.rgb();
        assert!(
            !(r > 0.8 && g < 0.6 && b < 0.3),
            "{color:?} lembra laranja ou vermelho"
        );
        assert!(!(g > 0.7 && r < 0.5 && b < 0.5), "{color:?} lembra verde");
    }
}

#[test]
fn lista_antiga_ganha_cores_distintas_em_ordem_e_guarda_o_que_tinha() {
    let mut list = vec![
        bench("a", None),
        bench("b", Some(C::Blue)),
        bench("c", None),
        bench("d", None),
    ];
    assign_missing_colors(&mut list);
    let colors: Vec<_> = list.iter().map(|w| w.color).collect();
    assert_eq!(
        colors,
        [Some(C::Violet), Some(C::Blue), Some(C::Pink), Some(C::Cyan)]
    );
}

#[test]
fn bancada_nova_e_colorida_contra_as_outras() {
    let others = [bench("a", Some(C::Blue)), bench("b", Some(C::Violet))];
    assert_eq!(
        colored_among(bench("c", None), &others).color,
        Some(C::Pink)
    );
    assert_eq!(
        colored_among(bench("c", Some(C::Sand)), &others).color,
        Some(C::Sand)
    );
}

#[test]
fn cor_vai_e_volta_e_a_desconhecida_nao_quebra_a_lista() {
    let text = serde_json::to_string(&[bench("a", Some(C::Indigo))]).unwrap();
    let back: Vec<WorkbenchConfig> = serde_json::from_str(&text).unwrap();
    assert_eq!(back[0].color, Some(C::Indigo));

    let old = r#"[{"name":"a","path":"/tmp","nodes":[],"color":"gold"}]"#;
    let list: Vec<WorkbenchConfig> = serde_json::from_str(old).unwrap();
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].color, None);
    // Cor de tipo errado também vira nula, nunca erro.
    let odd = r#"[{"name":"a","path":"/tmp","nodes":[],"color":7}]"#;
    assert_eq!(
        serde_json::from_str::<Vec<WorkbenchConfig>>(odd).unwrap()[0].color,
        None
    );
}

// A rota de controle recebe o nome do caso ou o rótulo do menu, como vier.
#[test]
fn cor_achada_pelo_nome_ou_pelo_rotulo() {
    assert_eq!(C::named("sand"), Some(C::Sand));
    assert_eq!(C::named("Areia"), Some(C::Sand));
    assert_eq!(C::named("MAGENTA"), Some(C::Magenta));
    assert_eq!(C::named("anil"), Some(C::Indigo));
    assert_eq!(C::named("dourado"), None);
    assert_eq!(C::named(""), None);
    assert_eq!(C::named("lightgreen"), Some(C::LightGreen));
}

#[test]
fn paleta_tem_vinte_e_quatro_cores_com_nome() {
    let labels: Vec<_> = C::ALL.iter().map(|c| c.label()).collect();
    assert_eq!(labels.len(), 24);
    let mut unique = labels.clone();
    unique.sort_unstable();
    unique.dedup();
    assert_eq!(unique.len(), labels.len());
    assert!(C::AUTOMATIC.iter().all(|c| C::ALL.contains(c)));
    assert_eq!(C::named("verde-azulado"), Some(C::Teal));
    assert_eq!(C::named("pessego"), Some(C::Peach));
    // A tabela e `ALL` andam juntas: cada cor acha a própria linha.
    for color in C::ALL {
        assert_eq!(C::from_raw(color.raw()), Some(color));
    }
}

// A paleta cresceu, mas o que já estava gravado no disco continua lendo.
#[test]
fn cores_gravadas_antes_da_paleta_grande_ainda_abrem() {
    for raw in [
        "blue", "violet", "pink", "cyan", "indigo", "sand", "magenta",
    ] {
        assert!(C::from_raw(raw).is_some(), "{raw}");
    }
    assert_eq!(C::from_raw("deepPurple"), Some(C::DeepPurple));
    assert_eq!(C::from_raw("lightGreen"), Some(C::LightGreen));
}

// ── WorkbenchLookupTests ───────────────────────────────────────────────────

fn plain(name: &str) -> WorkbenchConfig {
    WorkbenchConfig::new(name, format!("~/{name}"), vec![])
}

#[test]
fn indice_e_id_andam_nos_dois_sentidos() {
    let configs = [plain("um"), plain("dois"), plain("três")];
    assert_eq!(id_at(1, &configs), Some(configs[1].id.as_str()));
    assert_eq!(index_of_id(&configs[2].id, &configs), Some(2));
    assert_eq!(index_of_name("um", &configs), Some(0));
    assert_eq!(id_of_name("três", &configs), Some(configs[2].id.as_str()));
}

#[test]
fn fora_da_faixa_e_desconhecido_sao_none_e_nao_pânico() {
    let configs = [plain("um")];
    assert_eq!(id_at(-1, &configs), None);
    assert_eq!(id_at(1, &configs), None);
    assert_eq!(index_of_id("sumida", &configs), None);
    assert_eq!(index_of_name("sumida", &configs), None);
    assert_eq!(id_at(0, &[]), None);
}

/// O ponto do passo: remover a do meio desloca as outras, e quem guardou
/// posição passa a apontar para a bancada errada — quem guardou id, não.
#[test]
fn id_sobrevive_a_remocao_e_a_posicao_nao() {
    let mut configs = vec![plain("um"), plain("dois"), plain("três")];
    let terceira = configs[2].id.clone();
    assert_eq!(index_of_id(&terceira, &configs), Some(2));

    configs.remove(0);
    assert_eq!(
        index_of_id(&terceira, &configs),
        Some(1),
        "o id acompanhou o deslocamento"
    );
    assert_ne!(id_at(2, &configs), Some(terceira.as_str()));
}

/// Rename não mexe no id: é o que permite uma janela sobreviver ao nome novo.
#[test]
fn rename_mantem_o_id() {
    let mut configs = vec![plain("antes")];
    let id = configs[0].id.clone();
    configs[0].name = "depois".into();
    assert_eq!(index_of_id(&id, &configs), Some(0));
    assert_eq!(index_of_name("antes", &configs), None);
    assert_eq!(index_of_name("depois", &configs), Some(0));
}

// O `split` do endereço mora em `commons::ids`; aqui a paridade com os casos
// do WorkbenchLookupTests.
#[test]
fn endereco_parte_na_primeira_barra() {
    let a = Address::parse("deck/revisor").unwrap();
    assert_eq!((a.workbench.as_str(), a.node.as_str()), ("deck", "revisor"));
    assert_eq!(
        Address::parse("minha bancada/claude").unwrap().workbench,
        "minha bancada"
    );
    assert_eq!(Address::parse("deck/a/b").unwrap().node, "a/b");
    assert!(Address::parse("deck").is_err());
    assert!(Address::parse("/claude").is_err());
    assert!(Address::parse("deck/").is_err());
}

// ── WorkbenchStoreTests ────────────────────────────────────────────────────

struct Dir {
    dir: tempfile::TempDir,
}

impl Dir {
    fn new() -> Dir {
        Dir {
            dir: tempfile::tempdir().unwrap(),
        }
    }
    fn config(&self) -> std::path::PathBuf {
        self.dir.path().join(store::FILE)
    }
    fn legacy(&self) -> std::path::PathBuf {
        self.dir.path().join(store::LEGACY_FILE)
    }
    fn names(&self) -> Vec<String> {
        store::load(&self.config(), &self.legacy())
            .workbenches
            .into_iter()
            .map(|w| w.name)
            .collect()
    }
}

const OLD: &str = r#"[{"name":"velha","path":"~/velha","nodes":[]}]"#;

#[test]
fn arquivo_antigo_so_vale_quando_o_novo_nunca_existiu() {
    let d = Dir::new();
    fs::write(d.legacy(), OLD).unwrap();
    assert_eq!(d.names(), ["velha"]);
    let loaded = store::load(&d.config(), &d.legacy());
    assert_eq!(loaded.source, store::Source::Legacy);
    assert!(loaded.needs_save, "a próxima gravação vai para o nome novo");
}

#[test]
fn lista_vazia_e_um_estado_e_nao_traz_as_antigas_de_volta() {
    let d = Dir::new();
    fs::write(d.legacy(), OLD).unwrap();
    // O formato real: é assim que sai quando a última bancada é apagada.
    store::save(&d.config(), &[]).unwrap();
    assert_eq!(fs::read_to_string(d.config()).unwrap(), "[]");
    assert_eq!(d.names(), Vec::<String>::new());
    assert_eq!(
        store::load(&d.config(), &d.legacy()).source,
        store::Source::Config
    );
}

#[test]
fn o_arquivo_novo_vence_o_antigo() {
    let d = Dir::new();
    fs::write(d.legacy(), OLD).unwrap();
    fs::write(
        d.config(),
        r#"[{"name":"nova","path":"~/nova","nodes":[]}]"#,
    )
    .unwrap();
    assert_eq!(d.names(), ["nova"]);
}

#[test]
fn arquivo_novo_quebrado_nao_cai_no_antigo() {
    let d = Dir::new();
    fs::write(d.legacy(), OLD).unwrap();
    fs::write(d.config(), "{quebrado").unwrap();
    assert_eq!(d.names(), Vec::<String>::new());
    let loaded = store::load(&d.config(), &d.legacy());
    assert_eq!(loaded.source, store::Source::Broken);
    assert!(
        !loaded.needs_save,
        "não sobrescreve o que não conseguiu ler"
    );
}

#[test]
fn sem_nada_em_disco_comeca_vazio() {
    let d = Dir::new();
    let loaded = store::load(&d.config(), &d.legacy());
    assert!(loaded.workbenches.is_empty());
    assert_eq!(loaded.source, store::Source::Nothing);
}

// Arquivo gravado antes do rename traz `sessionId`/`sessionStarted`; sem
// absorver, todo agente perderia a conversa no primeiro arranque.
#[test]
fn nomes_antigos_de_conversa_sao_absorvidos_na_carga() {
    let d = Dir::new();
    fs::write(
        d.config(),
        r#"[{"id":"aaaa1111","name":"d","path":"/t","nodes":[
            {"type":"agent","id":"a","sessionId":"S1","sessionStarted":true}]}]"#,
    )
    .unwrap();
    let loaded = store::load(&d.config(), &d.legacy());
    let node = &loaded.workbenches[0].nodes[0];
    assert_eq!(node.conversation_id.as_deref(), Some("S1"));
    assert_eq!(node.conversation_started, Some(true));
    assert_eq!(node.session_id, None);
    assert!(loaded.needs_save);
}

// O id gerado na carga tem de ser gravado em seguida, senão a bancada se
// desliga da pasta dela (`workbenches/<id>/`) a cada arranque.
#[test]
fn bancada_sem_id_pede_para_gravar_e_o_id_fica() {
    let d = Dir::new();
    fs::write(d.config(), r#"[{"name":"d","path":"/t","nodes":[]}]"#).unwrap();
    let first = store::load(&d.config(), &d.legacy());
    assert!(first.needs_save);
    store::save(&d.config(), &first.workbenches).unwrap();
    let second = store::load(&d.config(), &d.legacy());
    assert!(!second.needs_save);
    assert_eq!(second.workbenches[0].id, first.workbenches[0].id);
}

#[test]
fn templates_gravam_leem_poem_e_tiram() {
    let d = Dir::new();
    let file = d.dir.path().join(store::TEMPLATES_FILE);
    assert!(store::load_templates(&file).is_empty());

    let mut ws = WorkbenchConfig::new(
        "deck",
        "/tmp/deck",
        vec![NodeConfig::new(NodeKind::Shell, "sh")],
    );
    ws.view = Some(ViewMode::Chat);
    store::put_template(&file, "zeta", capture_template(&ws)).unwrap();
    store::put_template(&file, "alfa", capture_template(&ws)).unwrap();
    assert_eq!(store::template_names(&file), ["alfa", "zeta"]);
    assert_eq!(store::template(&file, "zeta"), Some(capture_template(&ws)));

    store::remove_template(&file, "alfa").unwrap();
    assert_eq!(store::template_names(&file), ["zeta"]);
    fs::write(&file, "nada").unwrap();
    assert!(store::load_templates(&file).is_empty());
}
