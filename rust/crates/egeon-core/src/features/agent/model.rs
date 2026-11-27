//! O perfil de um agente CLI e as configurações que o compõem. Os nomes de chave
//! do JSON são os do Swift (camelCase): o `agents.json` de hoje abre como está.
//!
//! Leitura tolerante a chave faltando nas configurações aninhadas (`idle`,
//! `inject`, `attention`): o decoder sintetizado do Swift derrubava o arquivo
//! inteiro por uma chave a menos e o app regravava os padrões — o oposto de
//! "trocar de agente é editar JSON" (ADR-009) —, então lá cada campo ausente herda
//! o padrão, e aqui também. O perfil em si continua exigindo `displayName` e
//! `command`, como no Swift: sem eles o arquivo é descartado e os padrões voltam.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::Duration;

use serde::{Deserialize, Serialize};

use super::model_catalog::ModelCatalog;

/// Como saber que o agente terminou de trabalhar. Só existe `silence` hoje: TUI
/// de agente redesenha a tela com ANSI, spinner e movimento de cursor, então
/// parsear saída quebra a cada release do CLI. Silêncio no pty é barato e
/// estável (ADR-008).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct IdleConfig {
    pub strategy: String,
    pub ms: i64,
    /// Tempo mínimo desde o start do processo antes de considerar a bancada
    /// utilizável. Sem isso, uma pausa durante o boot da TUI passa por
    /// ociosidade e o prompt é entregue antes de existir quem o leia — some sem
    /// deixar rastro.
    pub warmup_ms: i64,
}

impl Default for IdleConfig {
    fn default() -> Self {
        IdleConfig {
            strategy: "silence".to_owned(),
            ms: 1500,
            warmup_ms: 4000,
        }
    }
}

/// Como entregar um prompt na bancada.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct InjectConfig {
    /// `bracketed-paste` para TUI (senão cada \n vira um submit separado),
    /// `plain` para CLI que lê linha a linha.
    pub mode: String,
    pub submit: String,
    /// Pausa entre colar e apertar Enter. TUI em Ink (Claude Code) processa a
    /// entrada de forma assíncrona: o `\r` enviado no mesmo instante do fim do
    /// paste é engolido e o prompt fica parado na caixa de input.
    pub submit_delay_ms: i64,
}

impl Default for InjectConfig {
    fn default() -> Self {
        InjectConfig {
            mode: "bracketed-paste".to_owned(),
            submit: "\r".to_owned(),
            submit_delay_ms: 150,
        }
    }
}

impl InjectConfig {
    pub fn submit_delay(&self) -> Duration {
        millis(self.submit_delay_ms)
    }
}

/// Qual marcador o agente escreveu — o tipo é o da feature `dispatch`, que é
/// quem decide o que fazer com ele.
pub use crate::features::dispatch::marker::Marker;

/// Protocolo de fim de turno (ADR-011): o tipo é o da feature `dispatch`, que
/// é quem lê o marcador e decide o que fazer com ele.
pub use crate::features::dispatch::marker::MarkerConfig;

fn default_sound() -> Option<String> {
    Some("Tink".to_owned())
}

fn default_marker() -> Option<MarkerConfig> {
    Some(MarkerConfig::default())
}

/// Como o terminal avisa que parou e precisa de você.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AttentionConfig {
    /// Som tocado na transição para "precisa de você". Nome de
    /// `/System/Library/Sounds` ou `~/Library/Sounds`. Vazio ou `null` desliga o
    /// som e mantém o aviso visual. Chave ausente herda `Tink` (o mais curto do
    /// catálogo do sistema), nulo explícito desliga — são coisas diferentes.
    #[serde(default = "default_sound", skip_serializing_if = "Option::is_none")]
    pub sound: Option<String>,
    /// 0…1, relativo ao volume de alerta do sistema.
    pub volume: f64,
    /// Rajada mínima de saída para o silêncio seguinte valer um aviso. Só vale
    /// como desempate — quando o agente escreve o marcador, o sinal é explícito
    /// e o limiar não entra.
    pub min_work_ms: i64,
    #[serde(default = "default_marker", skip_serializing_if = "Option::is_none")]
    pub marker: Option<MarkerConfig>,
    /// Regex sobre as últimas linhas visíveis, tentadas quando não há marcador
    /// na tela. Existe para o diálogo de permissão do PRÓPRIO CLI, que não
    /// carrega marcador nenhum. Vazio por padrão (ADR-011).
    pub patterns: Vec<String>,
}

impl Default for AttentionConfig {
    fn default() -> Self {
        AttentionConfig {
            sound: default_sound(),
            volume: 0.3,
            min_work_ms: 2000,
            marker: default_marker(),
            patterns: Vec::new(),
        }
    }
}

impl AttentionConfig {
    pub fn min_work(&self) -> Duration {
        millis(self.min_work_ms)
    }

    /// Marcador ativo, ou `None` quando desligado.
    pub fn active_marker(&self) -> Option<&MarkerConfig> {
        self.marker.as_ref().filter(|m| m.enabled)
    }
}

/// Perfil de um agente CLI. Nada no resto do código conhece "Claude Code" —
/// trocar de agente é editar o `agents.json` do flavor (ADR-009).
///
/// A régua de leitura é a do Swift: `AgentProfile` (`AgentProfile.swift:214`) usa o
/// `Codable` sintetizado, então `displayName` e `command` são obrigatórios — sem
/// eles o arquivo inteiro é descartado e os padrões voltam — e os opcionais
/// ausentes são `nil`. Já `IdleConfig`, `InjectConfig`, `MarkerConfig` e
/// `AttentionConfig` têm `init(from:)` próprio com `decodeIfPresent ?? padrão`
/// (`AgentProfile.swift:45-64` e `178-210`), e por isso lá o `serde(default)` por
/// campo é a leitura fiel.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentProfile {
    pub display_name: String,
    pub command: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub idle: Option<IdleConfig>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub inject: Option<InjectConfig>,
    /// Como retomar uma conversa existente. `{sessionId}` é substituído.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub resume: Option<Vec<String>>,
    /// Como criar a conversa com um id que NÓS escolhemos. Os dois flags são
    /// necessários: `--session-id` num id que já existe responde `Session ID …
    /// is already in use` e sai com 1. Criar e retomar são verbos diferentes para
    /// o CLI.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub new_session: Option<Vec<String>>,
    /// Como pedir ao CLI que avise qual conversa está aberta. `{file}` é
    /// substituído pelo caminho do arquivo de hooks que o app escreve.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub report_session: Option<Vec<String>>,
    /// Como passar o papel do terminal já no arranque, com `{prompt}`
    /// substituído pelo texto. Não gasta um turno, não aparece na conversa e não
    /// se dilui depois de vinte mensagens.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub system_prompt: Option<Vec<String>>,
    /// O comando de barra que zera a conversa dentro da TUI (`/clear`); `None`
    /// quando o CLI não tem um — aí o terminal é pulado, não morto.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub clear: Option<String>,
    /// Como pedir um modelo na linha de comando; `{model}` é substituído.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<Vec<String>>,
    /// Modelos oferecidos no formulário e no cabeçalho do card — dado, não
    /// tabela no código.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub models: Option<Vec<String>>,
    /// Como pedir um nível de esforço; `{effort}` é substituído.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub effort: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub efforts: Option<Vec<String>>,
    /// Como ligar o ultracode na linha de comando. No Claude Code sai pela MESMA
    /// flag do esforço (`--effort ultracode`), e aí o nível vai por `effort_env`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ultracode: Option<Vec<String>>,
    /// Variável de ambiente que carrega o nível quando a flag está ocupada.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub effort_env: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub attention: Option<AttentionConfig>,
    /// Variáveis de ambiente do processo deste agente, por cima do que o app já
    /// entrega (`CLAUDE_CONFIG_DIR` é o caso do dia a dia). Ambiente e não `cmd`
    /// porque `cmd` com prefixo `VAR=valor` deixa de casar com
    /// [`AgentProfile::runs_own_binary`].
    #[serde(skip_serializing_if = "Option::is_none")]
    pub env: Option<BTreeMap<String, String>>,
    /// A variável com que este CLI troca de conjunto de configuração: o nome é
    /// da CLI (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`), por isso quem declara é o
    /// perfil.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub config_env: Option<String>,
    /// Onde as configurações desta CLI ficam. Um `*` no fim, e só ali:
    /// `~/.claude*` acha `.claude`, `.claude-trabalho`. Não é glob de verdade.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub config_glob: Option<String>,
}

/// Milissegundos como o `Int` do Swift os guarda — um negativo editado à mão
/// abre o arquivo — e como `Duration` precisa: negativo vira zero.
fn millis(ms: i64) -> Duration {
    Duration::from_millis(u64::try_from(ms).unwrap_or(0))
}

/// `dropLast()` do Swift: tira o último caractere, seja ele qual for.
fn drop_last(text: &str) -> &str {
    text.char_indices()
        .next_back()
        .map_or("", |(at, _)| &text[..at])
}

/// `~` e `~/…` resolvidos contra `home`, como o `expandingTildeInPath`.
pub fn expand_tilde(path: &str, home: &Path) -> PathBuf {
    if path == "~" {
        return home.to_path_buf();
    }
    match path
        .strip_prefix('~')
        .and_then(|p| p.strip_prefix(crate::features::path_text::is_separator))
    {
        Some(rest) => home.join(rest),
        None => PathBuf::from(path),
    }
}

fn substitute(template: &[String], key: &str, value: &str) -> Vec<String> {
    template
        .iter()
        .map(|part| part.replace(key, value))
        .collect()
}

fn non_empty(list: &Option<Vec<String>>) -> Option<&Vec<String>> {
    list.as_ref().filter(|l| !l.is_empty())
}

/// O que sobe na linha de comando para esforço e ultracode, e o ambiente que vai
/// junto.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct EffortLaunch {
    pub arguments: Vec<String>,
    pub environment: BTreeMap<String, String>,
}

impl AgentProfile {
    pub fn new(display_name: &str, command: &[&str]) -> Self {
        AgentProfile {
            display_name: display_name.to_owned(),
            command: command.iter().map(|c| (*c).to_owned()).collect(),
            ..AgentProfile::default()
        }
    }

    /// Onde o CLI guarda a configuração quando a variável não está definida: o
    /// `config_glob` sem o `*` — `~/.claude*` é a família de `~/.claude`.
    pub fn default_config_path(&self, home: &Path) -> Option<PathBuf> {
        let glob = self.config_glob.as_deref()?;
        let stem = glob.strip_suffix('*')?;
        Some(expand_tilde(stem, home))
    }

    /// As configurações desta CLI que existem no disco agora. Consultado a cada
    /// abertura do formulário: criar um `~/.claude-x` e vê-lo na lista sem
    /// reiniciar o app é o comportamento esperado.
    pub fn discovered_configs(&self, home: &Path) -> Vec<PathBuf> {
        let Some(glob) = self.config_glob.as_deref() else {
            return Vec::new();
        };
        let Some(pattern) = glob.strip_suffix('*') else {
            return Vec::new();
        };
        let expanded = expand_tilde(pattern, home);
        let Some(directory) = expanded.parent() else {
            return Vec::new();
        };
        let prefix = expanded
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        let Ok(entries) = std::fs::read_dir(directory) else {
            return Vec::new();
        };
        let mut found: Vec<PathBuf> = entries
            .flatten()
            .filter(|e| e.file_name().to_string_lossy().starts_with(&prefix))
            .map(|e| e.path())
            // Só diretório: `~/.claude*` casa também com o `~/.claude.json`, que
            // é estado do CLI e não uma configuração para onde apontar.
            .filter(|p| p.is_dir())
            .collect();
        found.sort_by_key(|p| p.file_name().map(|n| n.to_os_string()));
        found
    }

    /// `env` com `~` e `$HOME` resolvidos. O ambiente vai montado direto para o
    /// processo filho: ninguém expande til no caminho, e um
    /// `CLAUDE_CONFIG_DIR=~/.claude-trabalho` literal faz o CLI criar uma pasta
    /// chamada `~` dentro do cwd do terminal.
    pub fn resolved_environment(&self, home: &Path) -> BTreeMap<String, String> {
        let home_text = home.to_string_lossy();
        self.env
            .iter()
            .flatten()
            .map(|(key, value)| {
                let resolved = crate::features::path_text::expand_tilde(
                    &value.replace("$HOME", &home_text),
                    &home_text,
                );
                (key.clone(), resolved)
            })
            .collect()
    }

    pub fn idle_interval(&self) -> Duration {
        millis(self.idle.as_ref().map_or(1500, |i| i.ms))
    }

    pub fn warmup_interval(&self) -> Duration {
        millis(self.idle.as_ref().map_or(4000, |i| i.warmup_ms))
    }

    pub fn inject_config(&self) -> InjectConfig {
        self.inject.clone().unwrap_or_default()
    }

    pub fn attention_config(&self) -> AttentionConfig {
        self.attention.clone().unwrap_or_default()
    }

    /// A pergunta por ferramenta, e não por texto solto: assim ela chega ao chat
    /// com as opções como botões, e o usuário responde de lá (ADR-068).
    pub const QUESTION_TOOL_LINE: &'static str = "Para perguntar algo ao usuário — escolha entre opções, confirmação —, prefira a ferramenta AskUserQuestion: no Egeon ela aparece no chat com as opções como botões, e ele responde dali.";

    /// O que entra no system prompt do agente, nesta ordem: protocolo de
    /// marcador, catálogo de vizinhos, papel deste terminal e as regras. `None`
    /// quando não há nada.
    ///
    /// O protocolo vem primeiro porque é regra de formato e vale para tudo; o
    /// papel é o assunto, e assunto depois de regra é o que o modelo lê melhor.
    /// **As regras vêm por último, depois do papel**, e não é arranjo: uma
    /// diretriz geral que conflita com uma restrição específica é resolvida a
    /// favor da ação quando a restrição vem antes (ADR-056).
    pub fn system_prompt_text(
        &self,
        role: Option<&str>,
        catalog: Option<&str>,
        rules: Option<&str>,
    ) -> Option<String> {
        let mut parts: Vec<String> = Vec::new();
        if let Some(marker) = self.attention_config().active_marker() {
            // Só quem fala por gancho: é pelo `PermissionRequest` que a pergunta
            // chega ao chat. Outro CLI não tem a ferramenta (ADR-068).
            let asks_by_tool = self.report_session.as_ref().is_some_and(|r| !r.is_empty());
            let mut text = marker.resolved_instruction();
            if asks_by_tool {
                text.push('\n');
                text.push_str(Self::QUESTION_TOOL_LINE);
            }
            parts.push(text);
        }
        for extra in [catalog, role, rules].into_iter().flatten() {
            if !extra.is_empty() {
                parts.push(extra.to_owned());
            }
        }
        (!parts.is_empty()).then(|| parts.join("\n\n"))
    }

    /// Argumentos de system prompt, prontos para a linha de comando. `None`
    /// quando o CLI não sabe recebê-lo no arranque — aí o texto vira mensagem.
    pub fn system_prompt_arguments(&self, prompt: &str) -> Option<Vec<String>> {
        non_empty(&self.system_prompt).map(|t| substitute(t, "{prompt}", prompt))
    }

    /// Argumentos da conversa prontos para a linha de comando, com `{sessionId}`
    /// substituído. `None` quando o perfil não declara a forma pedida.
    pub fn conversation_arguments(template: &Option<Vec<String>>, id: &str) -> Option<Vec<String>> {
        non_empty(template).map(|t| substitute(t, "{sessionId}", id))
    }

    /// O CLI sabe retomar conversa por id que escolhemos?
    pub fn keeps_conversation(&self) -> bool {
        self.resume.is_some() && self.new_session.is_some()
    }

    /// Argumentos que escolhem o modelo, ou `None` quando o perfil não sabe pedir
    /// um — ou quando o nó ficou no padrão do CLI.
    pub fn model_arguments(&self, chosen: Option<&str>) -> Option<Vec<String>> {
        let chosen = chosen.filter(|c| !c.is_empty())?;
        non_empty(&self.model).map(|t| substitute(t, "{model}", chosen))
    }

    /// O CLI aceita escolher modelo?
    pub fn offers_models(&self) -> bool {
        non_empty(&self.model).is_some()
    }

    pub fn effort_arguments(&self, chosen: Option<&str>) -> Option<Vec<String>> {
        let chosen = chosen.filter(|c| !c.is_empty())?;
        non_empty(&self.effort).map(|t| substitute(t, "{effort}", chosen))
    }

    pub fn offers_efforts(&self) -> bool {
        non_empty(&self.effort).is_some()
    }

    /// Há modelo para escolher no cabeçalho: a flag sozinha não basta — com a
    /// lista vazia (Codex e Gemini de fábrica) o menu teria só "padrão do CLI".
    /// Modelo escrito à mão no nó ainda conta: esconder seria esconder o que
    /// roda.
    pub fn offers_model_choice(
        &self,
        catalog: Option<&ModelCatalog>,
        current: Option<&str>,
    ) -> bool {
        self.offers_models()
            && (self.models.as_ref().is_some_and(|m| !m.is_empty())
                || catalog.is_some_and(|c| !c.models.is_empty())
                || current.is_some_and(|c| !c.is_empty()))
    }

    /// O que sobe na linha de comando para esforço e ultracode, e o ambiente que
    /// vai junto. Ultracode sem `effort_env` perde o nível escolhido — o CLI fica
    /// no padrão do modelo, que é melhor do que não ligar.
    pub fn effort_launch(&self, effort: Option<&str>, ultracode: bool) -> EffortLaunch {
        let flag = if ultracode {
            non_empty(&self.ultracode)
        } else {
            None
        };
        let Some(flag) = flag else {
            return EffortLaunch {
                arguments: self.effort_arguments(effort).unwrap_or_default(),
                environment: BTreeMap::new(),
            };
        };
        let mut environment = BTreeMap::new();
        if let (Some(level), Some(variable)) = (effort.filter(|e| !e.is_empty()), &self.effort_env)
        {
            environment.insert(variable.clone(), level.to_owned());
        }
        EffortLaunch {
            arguments: flag.clone(),
            environment,
        }
    }

    /// O que "padrão" significa para este CLI nesta configuração: o `model` do
    /// `settings.json` da pasta de config em uso. `None` quando não há arquivo ou
    /// ele não fixa modelo — aí só o transcript, depois do primeiro turno, sabe.
    ///
    /// A pasta é a do nó (`config`), senão a do ambiente do perfil, senão a
    /// padrão do CLI.
    pub fn default_model_name(&self, config: Option<&str>, home: &Path) -> Option<String> {
        let directory: String = config
            .map(str::to_owned)
            .or_else(|| {
                self.config_env
                    .as_ref()
                    .and_then(|v| self.resolved_environment(home).get(v).cloned())
            })
            .or_else(|| self.config_glob.as_ref().map(|g| drop_last(g).to_owned()))?;
        if directory.is_empty() {
            return None;
        }
        let path = expand_tilde(&directory, home).join("settings.json");
        let value: serde_json::Value = serde_json::from_slice(&std::fs::read(path).ok()?).ok()?;
        let model = value.get("model")?.as_str()?;
        (!model.is_empty()).then(|| model.to_owned())
    }

    /// Argumentos que instalam o gancho de relato. `None` quando o perfil não o
    /// declara — aí o app fica só com a conversa que ele mesmo criou.
    pub fn report_arguments(&self, hook_file: &str) -> Option<Vec<String>> {
        non_empty(&self.report_session).map(|t| substitute(t, "{file}", hook_file))
    }

    /// Esta linha de comando ainda é o binário que o perfil declara? Quem trocou
    /// o `cmd` do nó pode ter trocado de programa, e anexar
    /// `--append-system-prompt` a outra coisa mata o terminal no arranque.
    pub fn runs_own_binary(&self, command: &str) -> bool {
        let Some(binary) = self.command.first().filter(|b| !b.is_empty()) else {
            return false;
        };
        command == binary || command.starts_with(&format!("{binary} "))
    }
}

/// O que se trocou no seletor do cabeçalho de um agente. Modelo e esforço andam
/// juntos porque o efeito é o mesmo — o processo reinicia e a conversa fica.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModelChoice {
    /// `None` é o padrão do CLI.
    Model(Option<String>),
    /// `None` é o padrão do CLI.
    Effort(Option<String>),
    Ultracode(bool),
}

impl ModelChoice {
    /// Aplica a escolha aos campos do nó (`model`, `effort`, `ultracode`),
    /// mexendo só no que foi trocado.
    pub fn apply(
        &self,
        model: &mut Option<String>,
        effort: &mut Option<String>,
        ultracode: &mut Option<bool>,
    ) {
        match self {
            ModelChoice::Model(value) => *model = value.clone(),
            ModelChoice::Effort(value) => *effort = value.clone(),
            ModelChoice::Ultracode(on) => *ultracode = on.then_some(true),
        }
    }
}
