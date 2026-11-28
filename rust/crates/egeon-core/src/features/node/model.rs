//! O nó de uma bancada e o componente (preset de nó), porte do `NodeConfig`,
//! `NodeTemplate` e `RetiredNode`.
//!
//! A leitura é a do `JSONDecoder` do Swift: chave desconhecida é ignorada,
//! opcional ausente ou `null` é nulo, tipo errado derruba a lista inteira. Só
//! o tipo de nó aposentado é pulado.

use std::collections::BTreeMap;

use serde::de::Error as _;
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum NodeKind {
    /// Terminal comum.
    Shell,
    /// Terminal com IA.
    Agent,
    /// Navegador no canvas, com perfil próprio.
    Web,
    /// Fila de prompts, mandados um a um ao agente ligado.
    Queue,
}

/// Tipos de nó que saíram do app. O `editor` era o VSCode (code-server) no
/// card, removido no ADR-076.
pub const RETIRED_KINDS: &[&str] = &["editor"];

/// O que um CLI muda no componente.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Overrides {
    /// Comando completo, quando o padrão do perfil não serve.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cmd: Option<String>,
    /// Pasta de configuração do CLI: com qual conjunto de plugins, MCP,
    /// settings e credenciais este terminal sobe. Absoluto.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub config: Option<String>,
    /// Modelo pedido ao CLI. Nulo é o padrão dele.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    /// Esforço pedido ao CLI. Nulo é o padrão dele.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub effort: Option<String>,
    /// O papel escrito com este CLI na tela, quando você escreveu um
    /// diferente. Vazio = vale o geral.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompt: Option<String>,
    /// As regras escritas com este CLI na tela. **Substituem** as gerais.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rules: Option<String>,
}

impl Overrides {
    pub fn is_empty(&self) -> bool {
        self.cmd.is_none()
            && self.config.is_none()
            && self.model.is_none()
            && self.effort.is_none()
            && self.prompt.is_none()
            && self.rules.is_none()
    }
}

/// Posição e tamanho no canvas.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Frame {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

/// Um nó da bancada.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NodeConfig {
    #[serde(rename = "type")]
    pub kind: NodeKind,
    pub id: String,
    /// Chave em agents.json. Só usado por `type: agent`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent: Option<String>,
    /// Relativo à raiz da bancada.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    /// Comando inicial. Em `agent`, o padrão vem do perfil.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cmd: Option<String>,
    /// Pasta de configuração do CLI. Nulo é o padrão da CLI.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub config: Option<String>,
    /// Modelo pedido ao CLI. Só usado por `type: agent`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    /// Esforço pedido ao CLI.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub effort: Option<String>,
    /// Ultracode ligado: vale em qualquer esforço, por isso campo à parte.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ultracode: Option<bool>,
    /// Só usado por `type: web`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    /// Nome do perfil em web-profiles.json. Só usado por `type: web`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub profile: Option<String>,
    /// Mensagem entregue ao agente quando ele sobe — o papel deste terminal.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompt: Option<String>,
    /// As regras deste terminal, somadas às da bancada (ADR-056).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rules: Option<String>,
    /// Este terminal pode montar e reconfigurar a própria bancada pelo
    /// `egeon` (ADR-066). Só o usuário liga, no formulário.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub maestro: Option<bool>,
    /// O que você configurou para CADA CLI neste terminal (ADR-057).
    #[serde(default, rename = "byAgent", skip_serializing_if = "Option::is_none")]
    pub by_agent: Option<BTreeMap<String, Overrides>>,
    /// Componente que originou o nó. Só registro.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub component: Option<String>,
    /// Conversa deste terminal no CLI do agente. Vive no NÓ, não na pasta:
    /// dois agentes na mesma worktree têm conversas separadas.
    #[serde(
        default,
        rename = "conversationId",
        skip_serializing_if = "Option::is_none"
    )]
    pub conversation_id: Option<String>,
    /// Onde o CLI está gravando esta conversa, relatado pelo gancho.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub transcript: Option<String>,
    /// O terminal já subiu uma vez com esta conversa? Separado do id porque a
    /// estreia usa flag diferente da retomada.
    #[serde(
        default,
        rename = "conversationStarted",
        skip_serializing_if = "Option::is_none"
    )]
    pub conversation_started: Option<bool>,
    /// Nome antigo de `conversation_id`. **Não use**: existe só para ler
    /// arquivo antigo, é absorvido por [`NodeConfig::migrating_legacy_names`]
    /// e nunca volta ao disco.
    #[serde(default, rename = "sessionId", skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    /// Nome antigo de `conversation_started`. Ver `session_id`.
    #[serde(
        default,
        rename = "sessionStarted",
        skip_serializing_if = "Option::is_none"
    )]
    pub session_started: Option<bool>,
    /// Posição e tamanho no canvas; ausentes na primeira vez.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub x: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub y: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub w: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub h: Option<f64>,
}

impl NodeConfig {
    pub fn new(kind: NodeKind, id: impl Into<String>) -> Self {
        Self {
            kind,
            id: id.into(),
            agent: None,
            cwd: None,
            cmd: None,
            config: None,
            model: None,
            effort: None,
            ultracode: None,
            url: None,
            profile: None,
            prompt: None,
            rules: None,
            maestro: None,
            by_agent: None,
            component: None,
            conversation_id: None,
            transcript: None,
            conversation_started: None,
            session_id: None,
            session_started: None,
            x: None,
            y: None,
            w: None,
            h: None,
        }
    }

    pub fn is_maestro(&self) -> bool {
        self.kind == NodeKind::Agent && self.maestro == Some(true)
    }

    /// O maestro responde os pedidos de permissão de ferramenta do time
    /// (ADR-080): quem monta o time é quem libera o trabalho dele.
    pub fn approves_team_permissions(&self) -> bool {
        self.is_maestro()
    }

    /// Ausente significa "nunca subiu": nó gravado antes do campo não o tem.
    pub fn has_started_conversation(&self) -> bool {
        self.conversation_started.unwrap_or(false)
    }

    fn agent_override(&self) -> Option<&Overrides> {
        let agent = self.agent.as_deref()?;
        self.by_agent.as_ref()?.get(agent)
    }

    /// O papel que sobe de fato: o do CLI em uso quando ele tem um próprio, o
    /// geral quando não.
    pub fn effective_prompt(&self) -> Option<&str> {
        self.agent_override()
            .and_then(|o| o.prompt.as_deref())
            .or(self.prompt.as_deref())
    }

    /// As regras que sobem de fato — mesma regra do papel.
    pub fn effective_rules(&self) -> Option<&str> {
        self.agent_override()
            .and_then(|o| o.rules.as_deref())
            .or(self.rules.as_deref())
    }

    /// O nó com os nomes antigos (`sessionId`, `sessionStarted`) absorvidos. O
    /// nome novo presente ganha do antigo.
    pub fn migrating_legacy_names(mut self) -> Self {
        if self.conversation_id.is_none() {
            self.conversation_id = self.session_id.take();
        }
        if self.conversation_started.is_none() {
            self.conversation_started = self.session_started.take();
        }
        self.session_id = None;
        self.session_started = None;
        self
    }

    /// O nó saído do formulário, com o que o formulário não mostra de volta.
    ///
    /// O formulário remonta o nó do zero pelo componente, e componente não tem
    /// conversa, ultracode nem URL: sem isto, renomear ou marcar maestro subia
    /// o agente numa conversa nova. A conversa só fica com o mesmo CLI na mesma
    /// pasta — o Claude Code guarda a conversa por diretório.
    pub fn keeping_state(mut self, previous: &NodeConfig) -> Self {
        if self.url.is_none() {
            self.url = previous.url.clone();
        }
        if self.profile.is_none() {
            self.profile = previous.profile.clone();
        }
        if self.kind != previous.kind || self.agent != previous.agent {
            return self;
        }
        if self.ultracode.is_none() {
            self.ultracode = previous.ultracode;
        }
        if self.cwd != previous.cwd {
            return self;
        }
        self.conversation_id = previous.conversation_id.clone();
        self.conversation_started = previous.conversation_started;
        self.transcript = previous.transcript.clone();
        self
    }

    /// O mesmo nó, sem a conversa — pronto para nascer em outro lugar.
    ///
    /// Copiar um nó é copiar a montagem, nunca o que foi dito dentro dele. Com
    /// o `conversationId` junto, o clone e o original apontam para a MESMA
    /// conversa e o segundo a subir não consegue abri-la. O transcript é da
    /// conversa, não da montagem.
    pub fn without_conversation(mut self) -> Self {
        self.conversation_id = None;
        self.conversation_started = None;
        self.transcript = None;
        self
    }

    /// `None` até haver os quatro valores e largura e altura positivas.
    pub fn frame(&self) -> Option<Frame> {
        match (self.x, self.y, self.w, self.h) {
            (Some(x), Some(y), Some(w), Some(h)) if w > 0.0 && h > 0.0 => {
                Some(Frame { x, y, w, h })
            }
            _ => None,
        }
    }

    pub fn set_frame(&mut self, frame: Frame) {
        self.x = Some(frame.x.round());
        self.y = Some(frame.y.round());
        self.w = Some(frame.w.round());
        self.h = Some(frame.h.round());
    }
}

/// O item de uma lista gravada é de um tipo que saiu do app? Olha `type` e
/// `kind`: nó de bancada e de template usam o primeiro, componente o segundo.
fn is_retired(item: &Value) -> bool {
    ["type", "kind"].iter().any(|key| {
        item.get(key)
            .and_then(Value::as_str)
            .is_some_and(|raw| RETIRED_KINDS.contains(&raw))
    })
}

/// A lista de nós sem os de tipo aposentado; ausente ou `null` é lista vazia.
///
/// Sem isto, um único card de editor em `workbenches.json` derrubava a leitura
/// do arquivo inteiro. Só o tipo aposentado é pulado; qualquer outro erro
/// continua sendo erro.
pub fn decode_nodes<'de, D: Deserializer<'de>>(de: D) -> Result<Vec<NodeConfig>, D::Error> {
    let Some(items) = Option::<Vec<Value>>::deserialize(de)? else {
        return Ok(Vec::new());
    };
    items
        .into_iter()
        .filter(|item| !is_retired(item))
        .map(|item| serde_json::from_value(item).map_err(D::Error::custom))
        .collect()
}

/// O que um CLI substitui no componente, já resolvido sobre a base.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Resolved {
    pub cmd: Option<String>,
    pub config: Option<String>,
    pub model: Option<String>,
    pub effort: Option<String>,
    pub prompt: Option<String>,
    pub rules: Option<String>,
}

/// Preset de um terminal: o papel que ele cumpre.
///
/// Três camadas, e esta é a do meio: `agents.json` diz COMO falar com um CLI,
/// o componente diz O QUE este terminal é, e `templates.json` diz o ARRANJO
/// dos nós no canvas.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NodeTemplate {
    /// Nome que virou o id do nó, e por isso aparece no endereço de dispatch.
    pub name: String,
    /// `shell` ou `agent`. Editar um nó pode trocar de um para o outro.
    pub kind: NodeKind,
    /// Relativo à raiz da bancada — nunca absoluto. Não é do CLI: é onde o
    /// terminal abre.
    pub cwd: Option<String>,
    /// Mensagem entregue ao agente quando ele sobe.
    pub prompt: Option<String>,
    /// As regras deste terminal, somadas às da bancada (ADR-056). Um CLI pode
    /// SUBSTITUIR este texto pelo dele em `by_agent` (ADR-057).
    pub rules: Option<String>,
    /// O que o shell roda. Só de shell: comando de agente é do CLI e mora em
    /// `by_agent`. Vazio é o zsh de login.
    pub command: Option<String>,
    /// Com qual CLI este componente nasce. É escolha, não identidade.
    pub agent: Option<String>,
    /// O terminal nasce maestro (ADR-066).
    pub maestro: Option<bool>,
    /// O que muda de um CLI para outro, por chave do `agents.json`.
    pub by_agent: Option<BTreeMap<String, Overrides>>,
}

impl NodeTemplate {
    pub fn new(name: impl Into<String>, kind: NodeKind) -> Self {
        Self {
            name: name.into(),
            kind,
            cwd: None,
            prompt: None,
            rules: None,
            command: None,
            agent: None,
            maestro: None,
            by_agent: None,
        }
    }

    /// Os valores efetivos para um CLI: o que vem da base, com o que aquele CLI
    /// substitui.
    ///
    /// Comando, configuração e modelo saem SÓ do mapa: não atravessam CLI
    /// nenhum. Papel e regras são gerais, e o mapa só entra quando você
    /// escreveu algo diferente com aquele CLI na tela (ADR-057).
    pub fn resolved(&self, cli: Option<&str>) -> Resolved {
        let over = cli.and_then(|cli| self.by_agent.as_ref()?.get(cli));
        Resolved {
            cmd: over.and_then(|o| o.cmd.clone()),
            config: over.and_then(|o| o.config.clone()),
            model: over.and_then(|o| o.model.clone()),
            effort: over.and_then(|o| o.effort.clone()),
            prompt: over
                .and_then(|o| o.prompt.clone())
                .or_else(|| self.prompt.clone()),
            rules: over
                .and_then(|o| o.rules.clone())
                .or_else(|| self.rules.clone()),
        }
    }

    /// Guarda o que estava na tela no CLI que estava na tela.
    ///
    /// É esta a regra que substitui um checkbox de escopo: quem decide de quem
    /// é o texto é o CLI selecionado quando você escreveu. Duas bordas a fazem
    /// usável: o primeiro texto vale para todos, senão o componente nasceria
    /// preso ao CLI em que foi escrito; e texto igual ao geral não vira
    /// exceção, senão um trecho nunca mais voltaria a ser de todos (ADR-057).
    pub fn remembering(&self, cli: Option<&str>, on_screen: Resolved) -> NodeTemplate {
        let Some(cli) = cli else {
            return self.clone();
        };
        let mut out = self.clone();
        let mut over = out
            .by_agent
            .as_ref()
            .and_then(|m| m.get(cli))
            .cloned()
            .unwrap_or_default();
        over.cmd = on_screen.cmd;
        over.config = on_screen.config;
        over.model = on_screen.model;
        over.effort = on_screen.effort;

        let virgin = out.prompt.is_none()
            && out.rules.is_none()
            && out
                .by_agent
                .iter()
                .flatten()
                .all(|(_, o)| o.prompt.is_none() && o.rules.is_none());
        if virgin {
            out.prompt = on_screen.prompt;
            out.rules = on_screen.rules;
            over.prompt = None;
            over.rules = None;
        } else {
            over.prompt = if on_screen.prompt == out.prompt {
                None
            } else {
                on_screen.prompt
            };
            over.rules = if on_screen.rules == out.rules {
                None
            } else {
                on_screen.rules
            };
        }

        let mut map = out.by_agent.take().unwrap_or_default();
        if over.is_empty() {
            map.remove(cli);
        } else {
            map.insert(cli.to_owned(), over);
        }
        out.by_agent = if map.is_empty() { None } else { Some(map) };
        out
    }

    /// O que este CLI guarda de próprio, para o formulário mostrar ao trocar.
    pub fn overrides(&self, cli: Option<&str>) -> Overrides {
        cli.and_then(|cli| self.by_agent.as_ref()?.get(cli))
            .cloned()
            .unwrap_or_default()
    }
}

/// O formato em disco, lido de qualquer época. Componente escrito antes da
/// ADR-057 tem `cmd`/`config`/`model` na raiz.
#[derive(Deserialize)]
struct TemplateWire {
    name: String,
    kind: NodeKind,
    #[serde(default)]
    agent: Option<String>,
    #[serde(default)]
    cwd: Option<String>,
    #[serde(default)]
    prompt: Option<String>,
    #[serde(default)]
    rules: Option<String>,
    #[serde(default, rename = "byAgent")]
    by_agent: Option<BTreeMap<String, Overrides>>,
    #[serde(default)]
    maestro: Option<bool>,
    #[serde(default)]
    cmd: Option<String>,
    #[serde(default)]
    config: Option<String>,
    #[serde(default)]
    model: Option<String>,
}

impl<'de> Deserialize<'de> for NodeTemplate {
    /// As chaves da raiz eram do CLI o tempo todo, então viram o mapa daquele
    /// CLI. Sem migração de disco: o arquivo velho continua válido e é
    /// reescrito na forma nova quando o componente é salvo.
    fn deserialize<D: Deserializer<'de>>(de: D) -> Result<Self, D::Error> {
        let wire = TemplateWire::deserialize(de)?;
        let mut by_agent = wire.by_agent;
        // `cmd` na raiz: num agente é o formato de antes da ADR-057; num shell
        // é o comando dele, que nunca teve CLI para onde migrar.
        let command = if wire.kind == NodeKind::Shell {
            wire.cmd.clone()
        } else {
            None
        };
        let legacy = Overrides {
            cmd: wire.cmd,
            config: wire.config,
            model: wire.model,
            ..Overrides::default()
        };
        if let Some(agent) = &wire.agent
            && !legacy.is_empty()
            && !by_agent.as_ref().is_some_and(|m| m.contains_key(agent))
        {
            by_agent
                .get_or_insert_with(BTreeMap::new)
                .insert(agent.clone(), legacy);
        }
        Ok(NodeTemplate {
            name: wire.name,
            kind: wire.kind,
            cwd: wire.cwd,
            prompt: wire.prompt,
            rules: wire.rules,
            command,
            agent: wire.agent,
            maestro: wire.maestro,
            by_agent,
        })
    }
}

#[derive(Serialize)]
struct TemplateOut<'a> {
    name: &'a str,
    kind: NodeKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    agent: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    maestro: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    cwd: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    prompt: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    rules: Option<&'a str>,
    #[serde(rename = "byAgent", skip_serializing_if = "Option::is_none")]
    by_agent: Option<&'a BTreeMap<String, Overrides>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    cmd: Option<&'a str>,
}

impl Serialize for NodeTemplate {
    /// Grava só na forma nova: as chaves legadas existem para ler o que já
    /// está no disco, não para continuar escrevendo nelas.
    fn serialize<S: Serializer>(&self, ser: S) -> Result<S::Ok, S::Error> {
        TemplateOut {
            name: &self.name,
            kind: self.kind,
            agent: self.agent.as_deref(),
            maestro: if self.maestro == Some(true) {
                Some(true)
            } else {
                None
            },
            cwd: self.cwd.as_deref(),
            prompt: self.prompt.as_deref(),
            rules: self.rules.as_deref(),
            by_agent: self.by_agent.as_ref().filter(|m| !m.is_empty()),
            cmd: if self.kind == NodeKind::Shell {
                self.command.as_deref()
            } else {
                None
            },
        }
        .serialize(ser)
    }
}

/// Um mapa de componentes lido do disco, sem os de tipo aposentado. Qualquer
/// outro erro derruba o mapa inteiro, como no Swift.
pub fn decode_components(bytes: &[u8]) -> Option<BTreeMap<String, NodeTemplate>> {
    let raw: BTreeMap<String, Value> = crate::features::json_file::parse(bytes).ok()?;
    raw.into_iter()
        .filter(|(_, item)| !is_retired(item))
        .map(|(name, item)| Some((name, serde_json::from_value(item).ok()?)))
        .collect()
}
