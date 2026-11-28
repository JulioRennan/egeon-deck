//! A bancada: o que ela é em disco, o modo de olhá-la, a cor e o template.
//! Porte do `WorkbenchConfig`, `ViewMode`, `WorkbenchColor` e
//! `WorkbenchTemplate`.
//!
//! A leitura é tolerante como a do Swift: o que saiu do app (`maxVisits`, o
//! modo `mosaic`, uma cor fora da paleta, o nó `editor`) não derruba o arquivo.

use std::path::Path;

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;

use crate::commons::ids::WorkbenchId;
use crate::features::edge::EdgeConfig;
use crate::features::node::model::{NodeConfig, decode_nodes};
use crate::features::path_text;

/// Oito hex de um UUID: único o bastante para uma máquina, curto o bastante
/// para ser nome de pasta (`WorkbenchConfig.newID`).
pub fn new_id() -> String {
    WorkbenchId::generate().into()
}

/// Ausente ou `null` ganha um id novo — o `decodeIfPresent ?? newID()` do
/// Swift. O id gerado só vale se for gravado em seguida: sem isso a bancada se
/// desliga da pasta dela a cada carga.
pub(crate) fn id_or_new<'de, D: Deserializer<'de>>(de: D) -> Result<String, D::Error> {
    Ok(Option::<String>::deserialize(de)?.unwrap_or_else(new_id))
}

// ── ViewMode ───────────────────────────────────────────────────────────────

/// De que jeito você está olhando a bancada.
///
/// Os modos não são duas cópias do nó: o card é o MESMO, e o que muda é quem
/// lhe dá o frame — por isso trocar de modo não toca no processo.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ViewMode {
    /// Bancada livre: posição, tamanho, zoom e arestas.
    Canvas,
    /// A bancada como conversa: participantes, thread e composer.
    Chat,
}

impl ViewMode {
    /// Os modos na ordem em que aparecem na barra e nas teclas ⌥⌘1 e ⌥⌘2.
    pub const ALL: [ViewMode; 2] = [ViewMode::Canvas, ViewMode::Chat];

    pub fn raw(self) -> &'static str {
        match self {
            ViewMode::Canvas => "canvas",
            ViewMode::Chat => "chat",
        }
    }

    /// Valor desconhecido vira canvas: um modo que saiu do app (`mosaic`)
    /// continua gravado no arquivo de quem o usou.
    pub fn from_raw(raw: &str) -> ViewMode {
        match raw {
            "chat" => ViewMode::Chat,
            _ => ViewMode::Canvas,
        }
    }
}

impl<'de> Deserialize<'de> for ViewMode {
    fn deserialize<D: Deserializer<'de>>(de: D) -> Result<Self, D::Error> {
        Ok(ViewMode::from_raw(&String::deserialize(de)?))
    }
}

// ── WorkbenchColor ─────────────────────────────────────────────────────────

/// A cor de uma bancada: a sombra em volta do canvas e o ponto ao lado do
/// título, para reconhecer a bancada antes de ler o nome (ADR-086).
///
/// A paleta são os tons 400 do Material, na ordem do círculo cromático. A
/// escolha automática fica nas sete de [`WorkbenchColor::AUTOMATIC`]: laranja,
/// verde e vermelho são "precisa de você", "terminou" e erro nos badges e
/// anéis (ADR-024). Escolhida à mão, vale qualquer uma.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum WorkbenchColor {
    Red,
    Coral,
    Peach,
    Orange,
    Amber,
    Sand,
    Yellow,
    Lime,
    LightGreen,
    Green,
    Teal,
    Cyan,
    Sky,
    Blue,
    Indigo,
    DeepPurple,
    Violet,
    Purple,
    Magenta,
    Pink,
    Raspberry,
    Brown,
    Slate,
    Grey,
}

type Rgb = (f64, f64, f64);

const fn hex(value: u32) -> Rgb {
    (
        ((value >> 16) & 0xFF) as f64 / 255.0,
        ((value >> 8) & 0xFF) as f64 / 255.0,
        (value & 0xFF) as f64 / 255.0,
    )
}

use WorkbenchColor as C;

/// Cada cor com o nome gravado, o rótulo do menu e o RGB, na ordem da paleta.
const TABLE: [(WorkbenchColor, &str, &str, Rgb); 24] = [
    (C::Red, "red", "Vermelho", hex(0xEF5350)),
    (C::Coral, "coral", "Coral", hex(0xFF7043)),
    (C::Peach, "peach", "Pêssego", hex(0xFFAB91)),
    (C::Orange, "orange", "Laranja", hex(0xFFA726)),
    (C::Amber, "amber", "Âmbar", hex(0xFFCA28)),
    (C::Sand, "sand", "Areia", (0.93, 0.80, 0.45)),
    (C::Yellow, "yellow", "Amarelo", hex(0xFFEE58)),
    (C::Lime, "lime", "Lima", hex(0xD4E157)),
    (C::LightGreen, "lightGreen", "Verde-claro", hex(0x9CCC65)),
    (C::Green, "green", "Verde", hex(0x66BB6A)),
    (C::Teal, "teal", "Verde-azulado", hex(0x26A69A)),
    (C::Cyan, "cyan", "Ciano", (0.25, 0.82, 0.95)),
    (C::Sky, "sky", "Celeste", hex(0x29B6F6)),
    (C::Blue, "blue", "Azul", (0.29, 0.56, 1.00)),
    (C::Indigo, "indigo", "Anil", (0.40, 0.42, 0.95)),
    (C::DeepPurple, "deepPurple", "Roxo", hex(0x7E57C2)),
    (C::Violet, "violet", "Violeta", (0.62, 0.42, 1.00)),
    (C::Purple, "purple", "Púrpura", hex(0xAB47BC)),
    (C::Magenta, "magenta", "Magenta", (0.88, 0.30, 0.90)),
    (C::Pink, "pink", "Rosa", (1.00, 0.45, 0.70)),
    (C::Raspberry, "raspberry", "Framboesa", hex(0xEC407A)),
    (C::Brown, "brown", "Marrom", hex(0x8D6E63)),
    (C::Slate, "slate", "Ardósia", hex(0x78909C)),
    (C::Grey, "grey", "Cinza", hex(0xBDBDBD)),
];

impl WorkbenchColor {
    /// As 24, na ordem da grade que a bolinha do título abre.
    pub const ALL: [WorkbenchColor; 24] = [
        C::Red,
        C::Coral,
        C::Peach,
        C::Orange,
        C::Amber,
        C::Sand,
        C::Yellow,
        C::Lime,
        C::LightGreen,
        C::Green,
        C::Teal,
        C::Cyan,
        C::Sky,
        C::Blue,
        C::Indigo,
        C::DeepPurple,
        C::Violet,
        C::Purple,
        C::Magenta,
        C::Pink,
        C::Raspberry,
        C::Brown,
        C::Slate,
        C::Grey,
    ];

    /// As que o app escolhe sozinho, na ordem de preferência.
    pub const AUTOMATIC: [WorkbenchColor; 7] = [
        C::Blue,
        C::Violet,
        C::Pink,
        C::Cyan,
        C::Indigo,
        C::Sand,
        C::Magenta,
    ];

    fn row(self) -> &'static (WorkbenchColor, &'static str, &'static str, Rgb) {
        // A tabela tem todas as variantes na ordem de `ALL`; o teste confere.
        TABLE
            .iter()
            .find(|(color, ..)| *color == self)
            .unwrap_or(&TABLE[13])
    }

    /// O nome que vai para o disco.
    pub fn raw(self) -> &'static str {
        self.row().1
    }

    /// O nome na grade e no menu.
    pub fn label(self) -> &'static str {
        self.row().2
    }

    pub fn rgb(self) -> (f64, f64, f64) {
        self.row().3
    }

    /// Só o nome gravado, sem tolerância: é o que o arquivo guarda.
    pub fn from_raw(raw: &str) -> Option<WorkbenchColor> {
        TABLE.iter().find(|(_, r, ..)| *r == raw).map(|row| row.0)
    }

    /// Aceita o nome do caso ou o rótulo, sem caixa nem acento — é o que chega
    /// pela rota de controle.
    pub fn named(raw: &str) -> Option<WorkbenchColor> {
        let key = fold(raw);
        TABLE
            .iter()
            .find(|(_, r, label, _)| fold(r) == key || fold(label) == key)
            .map(|row| row.0)
    }
}

/// Sem caixa nem acento (`caseInsensitive` e `diacriticInsensitive` do
/// Foundation). Cobre as letras latinas acentuadas, que são as dos rótulos e
/// as que alguém digitaria.
fn fold(text: &str) -> String {
    text.chars()
        .flat_map(char::to_lowercase)
        .map(|c| match c {
            'à' | 'á' | 'â' | 'ã' | 'ä' | 'å' | 'ā' | 'ă' | 'ą' => 'a',
            'ç' | 'ć' | 'č' => 'c',
            'è' | 'é' | 'ê' | 'ë' | 'ē' | 'ę' | 'ě' => 'e',
            'ì' | 'í' | 'î' | 'ï' | 'ī' => 'i',
            'ñ' | 'ń' | 'ň' => 'n',
            'ò' | 'ó' | 'ô' | 'õ' | 'ö' | 'ø' | 'ō' => 'o',
            'ù' | 'ú' | 'û' | 'ü' | 'ū' | 'ů' => 'u',
            'ý' | 'ÿ' => 'y',
            other => other,
        })
        .collect()
}

impl Serialize for WorkbenchColor {
    fn serialize<S: Serializer>(&self, ser: S) -> Result<S::Ok, S::Error> {
        ser.serialize_str(self.raw())
    }
}

impl<'de> Deserialize<'de> for WorkbenchColor {
    fn deserialize<D: Deserializer<'de>>(de: D) -> Result<Self, D::Error> {
        let raw = String::deserialize(de)?;
        WorkbenchColor::from_raw(&raw)
            .ok_or_else(|| serde::de::Error::custom(format!("cor desconhecida: {raw:?}")))
    }
}

/// Pelo texto: cor que saiu da paleta, ou de tipo errado, não pode derrubar a
/// lista inteira — vira nula e ganha outra no carregar.
fn lenient_color<'de, D: Deserializer<'de>>(de: D) -> Result<Option<WorkbenchColor>, D::Error> {
    let value = Option::<Value>::deserialize(de)?;
    Ok(value
        .as_ref()
        .and_then(Value::as_str)
        .and_then(WorkbenchColor::from_raw))
}

// ── WorkbenchConfig ────────────────────────────────────────────────────────

/// Uma frente de trabalho: uma pasta e os nós abertos sobre ela.
///
/// Bancada, e não projeto: nada impede duas bancadas apontarem para o mesmo
/// repositório em worktrees diferentes. Elas são independentes de propósito.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorkbenchConfig {
    /// Identidade que o nome não dá: nasce com a bancada e nunca muda. Bancada
    /// gravada antes de existir ganha um ao carregar.
    #[serde(default = "new_id", deserialize_with = "id_or_new")]
    pub id: String,
    /// Renomeável. É também a primeira parte do endereço de dispatch.
    pub name: String,
    pub path: String,
    #[serde(default, deserialize_with = "decode_nodes")]
    pub nodes: Vec<NodeConfig>,
    /// Template que originou a bancada. Só registro.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub template: Option<String>,
    /// Projeto (id) a que a bancada pertence, na árvore workspace → projeto →
    /// bancada (ADR-043). Ausente = ainda não conciliado.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub project: Option<String>,
    /// Quem pode acionar quem, dentro desta bancada.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub edges: Option<Vec<EdgeConfig>>,
    /// As regras desta bancada: valem para TODO agente que abre aqui, e cada
    /// nó pode somar as suas (ADR-056).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rules: Option<String>,
    /// De que jeito esta bancada estava sendo olhada. Ausente = canvas.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub view: Option<ViewMode>,
    /// Esta bancada estava ABERTA na faixa de abas quando o app fechou, e em que
    /// ordem. Nulo = fechada.
    #[serde(default, rename = "tabOrder", skip_serializing_if = "Option::is_none")]
    pub tab_order: Option<i64>,
    /// Esta era a bancada na frente. Separado de `tab_order` porque a ordem das
    /// abas não muda quando você troca de aba.
    #[serde(default, rename = "tabActive", skip_serializing_if = "Option::is_none")]
    pub tab_active: Option<bool>,
    /// Escolhida sozinha ao nascer, a menos usada (ADR-086).
    #[serde(
        default,
        deserialize_with = "lenient_color",
        skip_serializing_if = "Option::is_none"
    )]
    pub color: Option<WorkbenchColor>,
}

/// Onde o processo de um nó é lançado, e o aviso quando o `cwd` pedido não
/// existe.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NodeDirectory {
    pub path: String,
    /// `Some` quando o `cwd` do nó não resolveu e caiu na raiz da bancada.
    ///
    /// Calado, este fallback é o pior defeito que o Swift já teve: o terminal
    /// abre na pasta errada, com a cara do terminal certo, e o agente trabalha
    /// no repositório vizinho sem ninguém suspeitar. Quem chama tem de logar.
    pub warning: Option<String>,
}

impl WorkbenchConfig {
    pub fn new(name: impl Into<String>, path: impl Into<String>, nodes: Vec<NodeConfig>) -> Self {
        Self {
            id: new_id(),
            name: name.into(),
            path: path.into(),
            nodes,
            template: None,
            project: None,
            edges: None,
            rules: None,
            view: None,
            tab_order: None,
            tab_active: None,
            color: None,
        }
    }

    pub fn view_mode(&self) -> ViewMode {
        self.view.unwrap_or(ViewMode::Canvas)
    }

    pub fn edge_list(&self) -> &[EdgeConfig] {
        self.edges.as_deref().unwrap_or(&[])
    }

    /// Para onde `node` pode mandar mensagem.
    pub fn targets(&self, node: &str) -> Vec<&str> {
        self.edge_list()
            .iter()
            .filter(|e| e.from == node)
            .map(|e| e.to.as_str())
            .collect()
    }

    /// A pasta da bancada, com `~` expandido e sem barra no fim.
    pub fn url_path(&self, home: &str) -> String {
        path_text::normalize(&self.path, home)
    }

    pub fn folder_name(&self, home: &str) -> String {
        path_text::last_component(&self.url_path(home))
    }

    pub fn exists(&self, home: &str) -> bool {
        Path::new(&self.url_path(home)).exists()
    }

    /// Endereço de dispatch: estável, independe de título de janela ou posição
    /// na tela.
    pub fn address_of(&self, node: &NodeConfig) -> String {
        format!("{}/{}", self.name, node.id)
    }

    /// Para onde um `cwd` de nó aponta, sem perguntar ao disco.
    ///
    /// Três formas são legítimas e cada uma tem seu motivo:
    ///
    /// - **relativo** (`packages/api`) é o caso normal, e é o que faz o nó valer
    ///   em qualquer checkout — é dele que a duplicação em worktree depende;
    /// - **absoluto** (`~/Documents/agrosmart/nexus-backend`) é um repositório
    ///   vizinho, sem equivalente dentro da worktree da bancada;
    /// - **relativo saindo da raiz** (`../nexus-backend`) também aponta para
    ///   fora, e é onde mora a armadilha: o mesmo texto significa pastas
    ///   diferentes em checkouts diferentes.
    ///
    /// O `..` resolve só pelo texto: o caminho tem de ser previsível, sem
    /// depender de symlink.
    pub fn resolve(cwd: &str, root: &str, home: &str) -> String {
        if cwd.starts_with('~') || path_text::is_absolute(cwd) {
            return path_text::expand_tilde(cwd, home);
        }
        path_text::standardize(&path_text::join(root, cwd))
    }

    pub fn resolved_directory(&self, node: &NodeConfig, home: &str) -> String {
        match &node.cwd {
            None => self.url_path(home),
            Some(cwd) => Self::resolve(cwd, &self.url_path(home), home),
        }
    }

    /// Onde o processo deste nó é lançado. `cwd` que não resolve cai na raiz da
    /// bancada, **falando**: ver [`NodeDirectory::warning`].
    pub fn directory(&self, node: &NodeConfig, home: &str) -> NodeDirectory {
        let root = self.url_path(home);
        let Some(cwd) = &node.cwd else {
            return NodeDirectory {
                path: root,
                warning: None,
            };
        };
        let candidate = self.resolved_directory(node, home);
        if Path::new(&candidate).exists() {
            return NodeDirectory {
                path: candidate,
                warning: None,
            };
        }
        let warning = format!(
            "bancada {}: nó \"{}\" pede cwd \"{cwd}\", que resolve em {candidate} e não existe — \
             vai abrir na raiz {root}",
            self.name, node.id
        );
        NodeDirectory {
            path: root,
            warning: Some(warning),
        }
    }

    /// Nós cujo `cwd` não resolve, com o caminho que cada um tentou. Serve para
    /// dizer na cara, na hora de montar a bancada, em vez de deixar o usuário
    /// descobrir pelo `pwd` três horas depois.
    pub fn unresolved_directories(&self, home: &str) -> Vec<(String, String)> {
        self.nodes
            .iter()
            .filter(|node| node.cwd.is_some())
            .filter_map(|node| {
                let candidate = self.resolved_directory(node, home);
                (!Path::new(&candidate).exists()).then(|| (node.id.clone(), candidate))
            })
            .collect()
    }
}

// ── WorkbenchTemplate ──────────────────────────────────────────────────────

/// Preset de canvas: quantos nós, de que tipo, onde, com qual agente e qual
/// url base. Nasce de um canvas montado ("salvar como template"), não de
/// edição de arquivo.
///
/// Guarda o caminho do projeto como valor inicial e o dos nós como `cwd`
/// relativo a ele: é essa combinação que faz o template servir para worktree.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorkbenchTemplate {
    #[serde(default, deserialize_with = "decode_nodes")]
    pub nodes: Vec<NodeConfig>,
    /// Pasta do projeto, usada como valor inicial ao criar a bancada.
    #[serde(default, rename = "basePath", skip_serializing_if = "Option::is_none")]
    pub base_path: Option<String>,
    /// Em que modo a bancada abre. Faz parte da montagem tanto quanto a posição
    /// dos nós.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub view: Option<ViewMode>,
}

impl WorkbenchTemplate {
    /// Instancia os nós para uma bancada nova.
    ///
    /// A conversa é zerada de novo, embora `capture` já não a guarde:
    /// templates salvos por uma versão anterior têm o `conversationId` do
    /// molde dentro, e sem isto continuariam ressuscitando a conversa alheia a
    /// cada bancada nova.
    pub fn instantiate(&self) -> Vec<NodeConfig> {
        self.nodes
            .iter()
            .cloned()
            .map(NodeConfig::without_conversation)
            .collect()
    }
}
