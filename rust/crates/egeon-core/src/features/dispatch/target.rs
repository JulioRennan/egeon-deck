//! Um alvo endereçável: o terminal que aceita prompt injetado, com a fila de
//! entrega e o estado visível (trabalhando, terminou, precisa de você). Porte
//! da classe `Target` do `Dispatcher.swift`.
//!
//! Máquina pura: entra evento e o instante, sai [`Effect`]. O pty, a tela, o
//! foco e o transcript chegam pela [`Surface`]; nada aqui dorme nem agenda —
//! o que no Swift era `asyncAfter` vira um prazo guardado que o `tick` confere.

use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use fancy_regex::Regex;

use super::failure::{ApiFailure, MAX_ATTEMPTS};
use super::marker::{HookEvent, LastMarker, Marker, MarkerConfig};
use super::profile::{AttentionConfig, InjectConfig, TargetProfile, shell_inject};
use super::stop::{PeerWait, StopOutcome, StopReport};
use crate::features::activity::model::Activity;
use crate::log;

/// O que o Dispatcher precisa ler do mundo para decidir, por endereço.
pub trait Surface {
    /// O processo do terminal está de pé.
    fn running(&self, address: &str) -> bool;
    /// Você está olhando para ESTE terminal agora: o app na frente, a janela
    /// principal e o foco do teclado dentro dele.
    fn focused(&self, address: &str) -> bool;
    /// As últimas linhas não vazias da tela, como o `/peek`.
    fn peek(&self, address: &str, lines: usize) -> Vec<String>;
    /// O marcador do último turno, lido da cauda do transcript.
    ///
    /// Sem padrão de propósito: ler até 512 KiB do disco, até 7 vezes por
    /// `Stop`, é de quem implementa decidir onde roda. Ver
    /// [`marker::last_marker_at`](super::marker::last_marker_at) e
    /// [`MARKER_TAIL_BYTES`](super::marker::MARKER_TAIL_BYTES).
    fn last_marker(&self, transcript: &Path, marker: &MarkerConfig) -> Option<LastMarker>;
}

/// O que o ator faz por conta do Dispatcher.
#[derive(Debug, Clone, PartialEq)]
pub enum Effect {
    /// Bytes para o pty do terminal.
    Write { address: String, bytes: Vec<u8> },
    /// Parada nova: a notificação do sistema (para `Asking`, `Waiting` e
    /// `Failed`, com o detalhe da permissão aberta quando houver) e, se `sound`
    /// vier, o som — quando a notificação não for tocar o dela.
    Announce {
        address: String,
        activity: Activity,
        sound: Option<String>,
        volume: f64,
    },
    /// O terminal voltou a trabalhar: tira a notificação dele.
    Withdraw { address: String },
    /// Fecha os pedidos de permissão abertos deste terminal.
    DropPermissions { address: String, why: &'static str },
    /// O turno fechou e o transcript está em dia: o histórico do chat lê.
    TurnEnded {
        address: String,
        transcript: Option<PathBuf>,
        started_at: Option<SystemTime>,
    },
}

/// O que um gancho relatou por `/activity` (ou `/conversation`, que é um
/// `prompt`).
#[derive(Debug, Clone, PartialEq)]
pub struct Hook {
    pub event: HookEvent,
    pub transcript: Option<PathBuf>,
    pub report: StopReport,
    pub failure: Option<ApiFailure>,
}

impl Hook {
    pub fn new(event: HookEvent) -> Self {
        Self {
            event,
            transcript: None,
            report: StopReport::default(),
            failure: None,
        }
    }

    /// A query de `/activity`: `transcript`, os campos do [`StopReport`] e os
    /// da [`ApiFailure`]. O `event` já foi validado pela rota.
    pub fn from_query(event: HookEvent, query: &HashMap<String, String>) -> Self {
        Self {
            event,
            transcript: query
                .get("transcript")
                .filter(|t| !t.is_empty())
                .map(PathBuf::from),
            report: StopReport::from_query(query),
            failure: ApiFailure::from_query(query),
        }
    }
}

/// Saída de uma operação: os efeitos e quem encerrou sem responder, que o
/// Dispatcher espalha aos outros alvos.
#[derive(Debug, Default)]
pub(super) struct Out {
    pub effects: Vec<Effect>,
    pub settled: Vec<String>,
}

#[derive(Debug, Clone)]
pub(super) struct Queued {
    pub prompt: String,
    pub mode: Option<String>,
    pub chain: Vec<String>,
    /// O aviso que vai antes de um comando com `/`: não conta como mensagem do
    /// remetente — comando e aviso são um envio só.
    pub notice: bool,
    pub images: Vec<String>,
}

#[derive(Debug, Clone)]
struct Unconfirmed {
    prompt: String,
    mode: Option<String>,
    images: Vec<String>,
    sent_at: SystemTime,
    attempts: u32,
}

#[derive(Debug, Clone)]
struct PendingSettle {
    due: SystemTime,
    transcript: Option<PathBuf>,
    report: StopReport,
    token: String,
    attempt: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Outcome {
    Asked,
    Finished,
    Background,
    Unknown,
}

struct Verdict {
    outcome: Outcome,
    via: &'static str,
}

const UNKNOWN: Verdict = Verdict {
    outcome: Outcome::Unknown,
    via: "silêncio",
};

/// Quanto esperar o `SessionStart` antes de dar o boot por acabado.
const BOOT_CEILING: Duration = Duration::from_secs(45);
const STOP_RETRIES: u32 = 6;
const STOP_RETRY_DELAY: Duration = Duration::from_millis(250);
/// A cada quanto espiar a tela enquanto o agente trabalha.
const LIVE_PEEK_INTERVAL: Duration = Duration::from_millis(400);
/// Pty quieto que indica que a TUI terminou de renderizar.
const QUIET_BEFORE_SUBMIT: Duration = Duration::from_millis(300);
/// Teto absoluto para o Enter sair de qualquer jeito.
const SUBMIT_DEADLINE: Duration = Duration::from_millis(2500);
/// Silêncio depois da entrega que diz que ninguém estava lendo.
const CONFIRM_AFTER: Duration = Duration::from_millis(1500);
const DELIVERY_ATTEMPTS: u32 = 3;
const SCREEN_LINES: usize = 24;

fn since(now: SystemTime, then: SystemTime) -> Duration {
    now.duration_since(then).unwrap_or(Duration::ZERO)
}

fn secs(t: SystemTime) -> f64 {
    t.duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn plural(n: u32, word: &str) -> String {
    if n > 1 {
        format!("{word}s")
    } else {
        word.to_owned()
    }
}

fn paste(text: &str) -> Vec<u8> {
    format!("\u{1b}[200~{text}\u{1b}[201~").into_bytes()
}

pub struct Target {
    /// `bancada/id`. Muda quando a bancada é renomeada.
    pub(super) address: String,
    profile: Option<TargetProfile>,
    pub(super) queue: VecDeque<Queued>,
    /// Por onde passou a mensagem que este terminal está atendendo. Limita
    /// ciclo contando REVISITA, não comprimento; zera quando você digita.
    pub(super) chain: Vec<String>,
    last_output: SystemTime,
    started_at: SystemTime,
    /// A TUI escreveu algo? Antes disso não existe leitor de stdin.
    saw_output: bool,
    unconfirmed: Option<Unconfirmed>,
    /// Texto colado, Enter ainda não enviado.
    pending_submit: Option<(InjectConfig, SystemTime)>,
    /// Com imagem, uma colagem por imagem e a do texto por último.
    pending_pastes: VecDeque<String>,

    burst_start: Option<SystemTime>,
    last_burst: Duration,
    acknowledged: bool,
    last_read: Option<(SystemTime, Vec<String>)>,
    /// Assinatura do marcador visível quando a rajada abriu: separa o
    /// marcador do turno passado do que o agente acabou de escrever.
    marker_at_burst_start: Option<String>,
    last_live_peek: SystemTime,
    /// Última parada anunciada. Guarda o SOM: um toque por turno.
    announced: Option<String>,
    /// Aviso não resolvido. Guarda o ESTADO; só cai com entrada nova.
    attention_held: bool,

    /// Falhas de API seguidas neste trabalho (ADR-072).
    failures: u32,
    /// Quando sai a tentativa agendada; `None` é sem tentativa.
    retry_at: Option<SystemTime>,
    last_failure: Option<ApiFailure>,
    /// O prompt em curso é a tentativa do app: o `prompt` dele não zera a
    /// contagem.
    retry_in_flight: bool,
    /// Lançado com os nossos ganchos — sabido no arranque (ADR-024).
    speaks_hooks: bool,
    /// Acionou um vizinho neste turno: o fim dele não te chama.
    pub(super) handed_off: bool,
    /// Veio `prompt` e o `stop` dele ainda não veio.
    turn_in_flight: bool,
    session_up: bool,
    turn_started_at: Option<SystemTime>,
    /// Você já viu que este terminal terminou. Só vale para o "terminou".
    done_seen: bool,
    /// Latch do `[[ED:wait]]` (ADR-063).
    in_background: bool,
    pub(super) awaiting_peers: PeerWait,
    /// Quem pediu algo a este terminal e ainda não teve a volta (ADR-058).
    pub(super) owed_replies: PeerWait,
    awaiting_latched: bool,
    settles: Vec<PendingSettle>,

    activity: Activity,
    attention: AttentionConfig,
    marker: Option<MarkerConfig>,
    question_patterns: Vec<Regex>,
}

impl Target {
    pub(super) fn new(
        address: String,
        profile: Option<TargetProfile>,
        hooked: bool,
        now: SystemTime,
    ) -> Self {
        let attention = profile
            .as_ref()
            .map(|p| p.attention.clone())
            .unwrap_or_default();
        // Só terminal com IA fala o protocolo: um shell não tem quem obedeça.
        let marker = profile
            .as_ref()
            .and_then(|_| attention.active_marker().cloned());
        let question_patterns = attention
            .patterns
            .iter()
            // `(?i)` no texto, e não `case_insensitive` no builder: no
            // fancy-regex o flag do builder não chega ao lookaround, e o
            // `.caseInsensitive` do Swift valia para o padrão inteiro.
            .filter_map(|pattern| match Regex::new(&format!("(?i){pattern}")) {
                Ok(re) => Some(re),
                Err(_) => {
                    log!("agents.json: padrão de atenção inválido, ignorado — {pattern}");
                    None
                }
            })
            .collect();
        Self {
            address,
            profile,
            queue: VecDeque::new(),
            chain: Vec::new(),
            last_output: SystemTime::UNIX_EPOCH,
            started_at: now,
            saw_output: false,
            unconfirmed: None,
            pending_submit: None,
            pending_pastes: VecDeque::new(),
            burst_start: None,
            last_burst: Duration::ZERO,
            acknowledged: false,
            last_read: None,
            marker_at_burst_start: None,
            last_live_peek: SystemTime::UNIX_EPOCH,
            announced: None,
            attention_held: false,
            failures: 0,
            retry_at: None,
            last_failure: None,
            retry_in_flight: false,
            speaks_hooks: hooked,
            handed_off: false,
            turn_in_flight: false,
            session_up: false,
            turn_started_at: None,
            done_seen: false,
            in_background: false,
            awaiting_peers: PeerWait::default(),
            owed_replies: PeerWait::default(),
            awaiting_latched: false,
            settles: Vec::new(),
            activity: Activity::Starting,
            attention,
            marker,
            question_patterns,
        }
    }

    pub fn address(&self) -> &str {
        &self.address
    }

    pub fn activity(&self) -> &Activity {
        &self.activity
    }

    pub fn pending(&self) -> usize {
        self.queue.len()
    }

    pub fn profile(&self) -> Option<&TargetProfile> {
        self.profile.as_ref()
    }

    pub fn display_name(&self) -> &str {
        self.profile.as_ref().map_or("shell", |p| &p.display_name)
    }

    /// Quando o `prompt` deste turno chegou.
    pub fn turn_started_at(&self) -> Option<SystemTime> {
        self.turn_started_at
    }

    /// As cadeias das mensagens esperando leitura, sem os avisos de comando.
    pub(super) fn queued_chains(&self) -> impl Iterator<Item = &[String]> {
        self.queue
            .iter()
            .filter(|q| !q.notice)
            .map(|q| q.chain.as_slice())
    }

    fn idle_window(&self) -> Duration {
        self.profile
            .as_ref()
            .map_or(Duration::from_secs(1), |p| p.idle)
    }

    fn warmup_window(&self) -> Duration {
        self.profile.as_ref().map_or(Duration::ZERO, |p| p.warmup)
    }

    /// Pronta para receber = já escreveu algo, passou do aquecimento e está em
    /// silêncio pelo tempo do perfil (ADR-008). Silêncio sozinho mente: uma
    /// pausa no boot da TUI parece ociosidade.
    pub fn is_idle(&self, now: SystemTime) -> bool {
        self.saw_output
            && since(now, self.started_at) >= self.warmup_window()
            && since(now, self.last_output) >= self.idle_window()
    }

    /// Saíram bytes do pty. A tela já tem de estar atualizada com eles.
    pub(super) fn output(&mut self, now: SystemTime, surface: &dyn Surface) {
        if self.burst_start.is_none() {
            self.burst_start = Some(now);
            // Uma espiada por rajada: guardar qual marcador JÁ estava na tela é
            // o que depois permite reconhecer um marcador novo.
            let lines = surface.peek(&self.address, SCREEN_LINES);
            self.marker_at_burst_start = self.marker_signature(&lines);
        }
        self.last_output = now;
        self.saw_output = true;
        // Byte novo é assunto novo: o que você já tinha visto não vale mais.
        self.acknowledged = false;
        self.done_seen = false;
    }

    pub(super) fn enqueue(
        &mut self,
        prompt: String,
        mode: Option<String>,
        chain: Vec<String>,
        notice: bool,
        images: Vec<String>,
    ) {
        self.queue.push_back(Queued {
            prompt,
            mode,
            chain,
            notice,
            images,
        });
        log!(
            "dispatch[{}]: enfileirado ({} na fila)",
            self.address,
            self.queue.len()
        );
    }

    /// Só terminal com IA chama o usuário: um `npm run dev` fica quieto entre
    /// um rebuild e outro.
    fn watches_attention(&self) -> bool {
        self.profile.is_some()
    }

    /// O prazo guardado mais próximo — a nova tentativa ou a releitura do
    /// `Stop` —, para o ator acordar nele em vez de esperar o tique: o
    /// `asyncAfter(0.25)` do Swift não espera 0,5s.
    pub(super) fn next_deadline(&self) -> Option<SystemTime> {
        self.settles
            .iter()
            .map(|s| s.due)
            .chain(self.retry_at)
            .min()
    }

    /// Os prazos guardados: a tentativa depois de erro de API e a releitura do
    /// transcript no `Stop`.
    pub(super) fn fire_due(&mut self, now: SystemTime, surface: &dyn Surface, out: &mut Out) {
        if self.retry_at.is_some_and(|at| now >= at) {
            let failure = self
                .last_failure
                .clone()
                .unwrap_or_else(|| ApiFailure::new("unknown"));
            self.retry(&failure);
        }
        let (due, later): (Vec<_>, Vec<_>) = std::mem::take(&mut self.settles)
            .into_iter()
            .partition(|s| now >= s.due);
        self.settles = later;
        for settle in due {
            self.settle_stop(now, settle, surface, out);
        }
    }

    /// Recalcula o estado. Chamado pelo `tick`, depois do `drain`.
    pub(super) fn update_activity(
        &mut self,
        now: SystemTime,
        surface: &dyn Surface,
        out: &mut Out,
    ) {
        if !surface.running(&self.address) {
            // `running` ainda é falso enquanto o fork não completa: chamar de
            // morto aqui marcaria todo terminal recém-criado com ✕.
            let next = if since(now, self.started_at) < Duration::from_secs(1) {
                Activity::Starting
            } else {
                Activity::Dead
            };
            self.transition(next, out);
            return;
        }

        let quiet = since(now, self.last_output);
        // Quem fala por gancho diz quando o turno começa e acaba; byte no pty é
        // só a TUI se redesenhando. Byte decide só para quem não tem gancho.
        let working = if self.speaks_hooks {
            self.turn_in_flight
        } else {
            quiet < self.idle_window()
        };

        if !working && let Some(start) = self.burst_start {
            // Rajada que começou no aquecimento é o boot da TUI, não trabalho.
            let warmed_up_at = self.started_at + self.warmup_window();
            if start < warmed_up_at {
                self.last_burst = Duration::ZERO;
                // A conversa retomada redesenha o fim do turno anterior: dar por
                // anunciado o que já estava ali impede o arranque de tocar.
                let lines = surface.peek(&self.address, SCREEN_LINES);
                self.announced = self.marker_signature(&lines);
            } else {
                self.last_burst = since(self.last_output, start);
            }
            self.burst_start = None;
        }

        if !self.saw_output || since(now, self.started_at) < self.warmup_window() {
            self.transition(Activity::Starting, out);
            return;
        }

        // Com gancho, quem diz que subiu é o `SessionStart`; o teto é para CLI
        // que não relate.
        if self.speaks_hooks
            && !self.session_up
            && !self.turn_in_flight
            && since(now, self.started_at) < BOOT_CEILING
        {
            self.transition(Activity::Starting, out);
            return;
        }

        // Tentativa agendada: o estado é ela até a hora chegar (ADR-072).
        if self.retry_at.is_some() {
            return;
        }

        // Fila por drenar, entrega sem confirmação ou Enter por sair: está
        // esperando a gente, não você.
        if !self.queue.is_empty() || self.unconfirmed.is_some() || self.pending_submit.is_some() {
            self.transition(Activity::Working, out);
            return;
        }

        // Antes do foco: a ampulheta é o estado do agente, não aviso a dar por
        // visto.
        if self.awaiting_latched && !self.awaiting_peers.is_empty() && !working {
            if self.activity == Activity::Asking {
                return;
            }
            self.transition(Activity::Awaiting(self.awaiting_peers.names()), out);
            return;
        }
        if self.in_background && !working {
            if self.activity == Activity::Asking {
                return;
            }
            self.transition(Activity::Background, out);
            return;
        }

        if !self.watches_attention() {
            let next = if working {
                Activity::Working
            } else {
                Activity::Ready
            };
            self.transition(next, out);
            return;
        }

        // O silêncio de quem está olhando é você lendo; marcar como visto aqui
        // evita o aviso atrasado ao clicar em outro lugar.
        if surface.focused(&self.address) {
            self.acknowledged = true;
        }
        if self.acknowledged {
            self.attention_held = false;
            let next = if working {
                Activity::Working
            } else {
                Activity::Ready
            };
            self.transition(next, out);
            return;
        }

        if working {
            self.live_check(now, surface, out);
            return;
        }

        // Com gancho, quem anuncia é o `Stop`: ler marcador aqui seria reler o
        // do turno PASSADO, e o recap do CLI escreve marcador sem gancho.
        if self.speaks_hooks {
            self.hold(Activity::Ready, out);
            return;
        }

        let lines = self.screen(surface);
        let verdict = self.verdict(&lines);
        let signature = self.marker_signature(&lines);
        match verdict.outcome {
            Outcome::Asked => {
                let stop = signature.unwrap_or_else(|| self.stop_token());
                self.attend(Activity::Asking, verdict.via, stop, out);
            }
            Outcome::Finished => {
                let stop = signature.unwrap_or_else(|| self.stop_token());
                self.attend(Activity::Waiting, verdict.via, stop, out);
            }
            Outcome::Background => self.hold(Activity::Background, out),
            Outcome::Unknown => {
                // Sem marcador nem padrão, a rajada precisa ter sido trabalho.
                if self.last_burst < self.attention.min_work() {
                    self.hold(Activity::Ready, out);
                    return;
                }
                let stop = self.stop_token();
                self.attend(Activity::Waiting, verdict.via, stop, out);
            }
        }
    }

    /// Você abriu a bancada deste terminal. Só apaga o "terminou".
    pub(super) fn mark_done_seen(&mut self) {
        self.done_seen = true;
        if self.activity != Activity::Waiting {
            return;
        }
        self.attention_held = false;
        self.activity = Activity::Ready;
    }

    /// Entrada nova: o agente ganhou o que fazer, o aviso anterior caiu.
    fn input_arrived(&mut self) {
        self.attention_held = false;
        self.handed_off = false;
        self.in_background = false;
        self.awaiting_latched = false;
    }

    /// Você digitou aqui: resolve o aviso e encerra a cadeia.
    pub(super) fn user_typed(&mut self, out: &mut Out) {
        // Tecla com o diálogo de permissão aberto é a resposta dada no terminal
        // (ADR-068).
        out.effects.push(Effect::DropPermissions {
            address: self.address.clone(),
            why: "respondido no terminal",
        });
        self.cancel_retry(true);
        self.input_arrived();
        self.chain.clear();
        self.awaiting_peers.clear();
    }

    /// O pedido de permissão foi respondido pelo chat (ADR-068).
    pub(super) fn permission_answered(&mut self, out: &mut Out) {
        self.attention_held = false;
        self.acknowledged = true;
        if self.turn_in_flight {
            self.transition(Activity::Working, out);
        }
    }

    /// Um vizinho acionado mandou de volta; a resposta abre turno novo.
    pub(super) fn peer_answered(&mut self, address: &str) {
        if !self.awaiting_peers.resolved(address) {
            return;
        }
        if self.awaiting_peers.is_empty() {
            self.awaiting_latched = false;
        }
    }

    /// Um vizinho acionado encerrou sem mandar de volta. Sem mais ninguém a
    /// esperar, a parada vira "terminou".
    pub(super) fn peer_settled(&mut self, address: &str, now: SystemTime, out: &mut Out) {
        if !self.awaiting_peers.resolved(address)
            || !self.awaiting_peers.is_empty()
            || !self.awaiting_latched
        {
            return;
        }
        self.awaiting_latched = false;
        self.handed_off = false;
        let via = format!("{address} encerrou sem responder");
        let stop = hook_token("vizinho", now);
        self.attend(Activity::Waiting, &via, stop, out);
    }

    /// O CLI relatou por gancho o que acabou de acontecer aqui.
    pub(super) fn hook_reported(
        &mut self,
        hook: Hook,
        now: SystemTime,
        surface: &dyn Surface,
        out: &mut Out,
    ) {
        let Hook {
            event,
            transcript,
            report,
            failure,
        } = hook;
        log!("gancho[{}]: {}", self.address, event.as_str());
        self.speaks_hooks = true;
        if matches!(
            event,
            HookEvent::Stop | HookEvent::Prompt | HookEvent::Failure
        ) {
            out.effects.push(Effect::DropPermissions {
                address: self.address.clone(),
                why: "o turno seguiu",
            });
        }
        match event {
            HookEvent::Failure => {
                self.turn_in_flight = false;
                self.failed(
                    failure.unwrap_or_else(|| ApiFailure::new("unknown")),
                    now,
                    out,
                );
            }
            HookEvent::Stop => {
                self.turn_in_flight = false;
                self.failures = 0;
                let settle = PendingSettle {
                    due: now,
                    transcript,
                    report,
                    token: hook_token(event.as_str(), now),
                    attempt: 0,
                };
                self.settle_stop(now, settle, surface, out);
            }
            HookEvent::Start => self.session_up = true,
            HookEvent::Prompt => {
                self.session_up = true;
                self.turn_in_flight = true;
                self.turn_started_at = Some(now);
                self.in_background = false;
                if self.retry_in_flight {
                    self.retry_in_flight = false;
                } else {
                    self.cancel_retry(true);
                }
                // O CLI recebeu o prompt: é a confirmação da entrega (ADR-072).
                self.unconfirmed = None;
            }
            HookEvent::Ask => {
                // `Notification` é o pedido de permissão e o "você sumiu há
                // 60s"; o que separa os dois é o turno, não o relógio. Só recusa
                // quando todas as leituras dizem que acabou.
                let live = self.turn_in_flight
                    || self.in_background
                    || self.awaiting_latched
                    || self.activity == Activity::Working
                    || self.activity == Activity::Starting;
                if !live {
                    return;
                }
                self.in_background = false;
                self.awaiting_latched = false;
                let stop = hook_token(event.as_str(), now);
                self.attend(Activity::Asking, "gancho Notification", stop, out);
            }
        }
    }

    /// Erro passageiro ou limite de uso: agenda a tentativa, sem som. Sem
    /// volta, ou tentativas esgotadas: para e chama, em vermelho.
    fn failed(&mut self, failure: ApiFailure, now: SystemTime, out: &mut Out) {
        self.failures += 1;
        self.cancel_retry(false);
        let detail = failure
            .detail
            .as_deref()
            .map(|d| format!(" — {}", d.chars().take(160).collect::<String>()))
            .unwrap_or_default();
        log!(
            "falha[{}]: {}{detail} ({}ª)",
            self.address,
            failure.error,
            self.failures
        );
        let Some(delay) = failure.delay(self.failures) else {
            let tried = self.failures - 1;
            self.failures = 0;
            let why = if tried > 0 {
                format!(
                    "{} (depois de {tried} {})",
                    failure.label(),
                    plural(tried, "tentativa")
                )
            } else {
                failure.label().to_owned()
            };
            let via = format!("gancho StopFailure ({})", failure.error);
            let stop = hook_token("failure", now);
            self.attend(Activity::Failed(why), &via, stop, out);
            return;
        };
        let at = now + delay;
        // Segura o estado: o pty calado não pode virar "pronto" por cima.
        self.attention_held = true;
        self.transition(
            Activity::Retrying {
                attempt: self.failures,
                at,
            },
            out,
        );
        log!(
            "falha[{}]: tentando de novo em {}s ({}/{MAX_ATTEMPTS})",
            self.address,
            delay.as_secs(),
            self.failures
        );
        self.last_failure = Some(failure);
        self.retry_at = Some(at);
    }

    fn retry(&mut self, failure: &ApiFailure) {
        self.retry_at = None;
        self.retry_in_flight = true;
        self.attention_held = false;
        let chain = self.chain.clone();
        self.enqueue(failure.retry_prompt(), None, chain, false, Vec::new());
        self.last_failure = None;
    }

    /// Tentar agora (`now_flag`) ou desistir da tentativa agendada. `false`
    /// quando não há tentativa agendada.
    pub(super) fn retry_control(&mut self, now_flag: bool, out: &mut Out) -> bool {
        if self.retry_at.take().is_none() {
            return false;
        }
        if now_flag {
            let failure = self
                .last_failure
                .clone()
                .unwrap_or_else(|| ApiFailure::new("unknown"));
            self.retry(&failure);
        } else {
            self.failures = 0;
            self.attention_held = false;
            self.transition(Activity::Waiting, out);
            log!("falha[{}]: tentativa cancelada por você", self.address);
        }
        true
    }

    fn cancel_retry(&mut self, reset_count: bool) {
        self.retry_at = None;
        if reset_count {
            self.failures = 0;
        }
    }

    /// O gancho diz QUANDO o turno acabou; o marcador diz QUAL parada é. Ele
    /// vem do transcript, que chega atrasado: linha mais velha que o `prompt`
    /// deste turno é do turno passado, e aí espera-se um pouco e relê.
    /// Esgotadas as releituras, a tela é a reserva.
    fn settle_stop(
        &mut self,
        now: SystemTime,
        settle: PendingSettle,
        surface: &dyn Surface,
        out: &mut Out,
    ) {
        let PendingSettle {
            transcript,
            report,
            token,
            attempt,
            ..
        } = settle;
        let read = transcript
            .as_deref()
            .and_then(|t| self.marker.as_ref().and_then(|m| surface.last_marker(t, m)));
        let stale = read.as_ref().is_none_or(|r| {
            self.turn_started_at
                .is_some_and(|started| r.at.unwrap_or(SystemTime::UNIX_EPOCH) < started)
        });
        // Linha deste turno SEM marcador também é cedo demais: o texto que o
        // agente grava antes de uma ferramenta pode estar no fim do arquivo.
        let unsettled = stale
            || (report.last_message.is_none() && read.as_ref().and_then(|r| r.marker).is_none());
        if unsettled && transcript.is_some() && attempt < STOP_RETRIES {
            self.settles.push(PendingSettle {
                due: now + STOP_RETRY_DELAY,
                transcript,
                report,
                token,
                attempt: attempt + 1,
            });
            return;
        }

        let name = |m: Option<Marker>| m.map_or("sem marcador", Marker::as_str);
        let closing: Option<Marker>;
        let mut via: String;
        if let Some(last) = &report.last_message {
            closing = self.marker.as_ref().and_then(|m| m.latest(last));
            via = format!("gancho Stop, {} no payload", name(closing));
        } else if let Some(read) = read.as_ref().filter(|_| !stale) {
            closing = read.marker;
            via = format!("gancho Stop, {} no transcript", name(closing));
            if attempt > 0 {
                via += &format!(" ({attempt} {})", plural(attempt, "releitura"));
            }
        } else {
            let lines = self.screen(surface);
            let verdict = self.verdict(&lines);
            closing = match verdict.outcome {
                Outcome::Asked => Some(Marker::Ask),
                Outcome::Background => Some(Marker::Wait),
                Outcome::Finished => Some(Marker::Ok),
                Outcome::Unknown => None,
            };
            via = format!("gancho Stop, {} na tela", verdict.via);
        }
        if let Some(background) = report.background {
            via += &format!(", {background} de fundo");
        }
        if report.watchers > 0 {
            via += &format!(
                ", {} {} de página",
                report.watchers,
                plural(report.watchers, "vigia")
            );
        }
        if !report.tasks.is_empty() {
            via += &format!(" ({})", report.tasks.join("; "));
        }
        let outcome =
            StopOutcome::decide(closing, report.background, !self.awaiting_peers.is_empty());
        // Depois de assentar: as releituras garantem que a resposta inteira já
        // está no transcript quando o histórico a lê.
        out.effects.push(Effect::TurnEnded {
            address: self.address.clone(),
            transcript,
            started_at: self.turn_started_at,
        });
        self.in_background = outcome == StopOutcome::Background;
        self.awaiting_latched = outcome == StopOutcome::Awaiting;
        // O `Stop` é a parada nova: a permissão pedida no meio do turno já foi
        // respondida, senão o turno não teria fechado.
        self.attention_held = false;
        match outcome {
            StopOutcome::Awaiting => {
                self.transition(Activity::Awaiting(self.awaiting_peers.names()), out);
                log!(
                    "atenção[{}]: aguardando {} — por {via}",
                    self.address,
                    self.awaiting_peers.peers().join(", ")
                );
            }
            StopOutcome::Background => {
                self.transition(Activity::Background, out);
                log!("atenção[{}]: em segundo plano — por {via}", self.address);
            }
            StopOutcome::Asked => self.attend(Activity::Asking, &via, token, out),
            StopOutcome::Finished => self.attend(Activity::Waiting, &via, token, out),
        }
    }

    /// Identifica uma parada sem marcador pelo instante do último byte.
    fn stop_token(&self) -> String {
        format!("parada@{:.2}", secs(self.last_output))
    }

    /// Fim de turno reconhecido ANTES de o pty se calar, por um marcador
    /// DIFERENTE do que estava na tela quando a rajada abriu. Com gancho, só
    /// faz mal: a colagem empurra o marcador velho e a assinatura muda sozinha
    /// (ADR-024).
    fn live_check(&mut self, now: SystemTime, surface: &dyn Surface, out: &mut Out) {
        if self.speaks_hooks || self.marker.is_none() {
            self.hold(Activity::Working, out);
            return;
        }
        if since(now, self.last_live_peek) < LIVE_PEEK_INTERVAL {
            return;
        }
        self.last_live_peek = now;

        let lines = surface.peek(&self.address, SCREEN_LINES);
        let signature = self.marker_signature(&lines);
        let Some(signature) = signature.filter(|s| Some(s) != self.marker_at_burst_start.as_ref())
        else {
            self.hold(Activity::Working, out);
            return;
        };
        match self.verdict(&lines).outcome {
            Outcome::Asked => self.attend(Activity::Asking, "marcador ao vivo", signature, out),
            Outcome::Finished => self.attend(Activity::Waiting, "marcador ao vivo", signature, out),
            Outcome::Background => self.hold(Activity::Background, out),
            Outcome::Unknown => self.hold(Activity::Working, out),
        }
    }

    /// Muda de estado, a menos que haja aviso pendente.
    fn hold(&mut self, next: Activity, out: &mut Out) {
        if self.attention_held {
            return;
        }
        self.transition(next, out);
    }

    /// Entra em atenção e anuncia — uma vez por PARADA, não por transição.
    fn attend(&mut self, next: Activity, via: &str, stop: String, out: &mut Out) {
        // Terminou sem fila por drenar: quem esperava por este terminal não
        // espera mais (ADR-067). Antes do `handed_off`, que só cala o aviso.
        if next == Activity::Waiting && self.queue.is_empty() && self.unconfirmed.is_none() {
            out.settled.push(self.address.clone());
        }
        // Fim de turno de quem acionou um vizinho não te chama. Pergunta é o
        // contrário: permissão não se delega (ADR-024).
        if next == Activity::Waiting && (self.handed_off || self.done_seen) {
            self.hold(Activity::Ready, out);
            return;
        }
        self.activity = next.clone();
        let is_new_stop = !self.attention_held && self.announced.as_deref() != Some(&stop);
        self.attention_held = true;
        if !is_new_stop {
            return;
        }
        self.announced = Some(stop);

        // A rajada que produziu a resposta termina aqui: sem isso a regra de
        // saída sustentada mede a própria resposta.
        let burst = self
            .burst_start
            .map_or(self.last_burst, |start| since(self.last_output, start));
        self.last_burst = burst;
        self.burst_start = None;

        let said = match &next {
            Activity::Asking => "precisa de você".to_owned(),
            Activity::Failed(why) => format!("falhou ({why})"),
            _ => "terminou".to_owned(),
        };
        let sound = if next.needs_attention() {
            self.attention.sound.clone()
        } else {
            None
        };
        out.effects.push(Effect::Announce {
            address: self.address.clone(),
            activity: next,
            sound,
            volume: self.attention.volume,
        });
        log!(
            "atenção[{}]: {said} — por {via}, rajada de {:.1}s",
            self.address,
            burst.as_secs_f64()
        );
    }

    fn transition(&mut self, next: Activity, out: &mut Out) {
        if next == Activity::Dead && self.activity != Activity::Dead {
            out.settled.push(self.address.clone());
        }
        if next == Activity::Working && self.activity != Activity::Working {
            out.effects.push(Effect::Withdraw {
                address: self.address.clone(),
            });
        }
        self.activity = next;
    }

    /// Em silêncio a tela não muda: a leitura fica presa ao instante do último
    /// byte.
    fn screen(&mut self, surface: &dyn Surface) -> Vec<String> {
        if let Some((of, lines)) = &self.last_read
            && *of == self.last_output
        {
            return lines.clone();
        }
        let lines = surface.peek(&self.address, SCREEN_LINES);
        self.last_read = Some((self.last_output, lines.clone()));
        lines
    }

    /// O último marcador visível mais as três linhas acima: o texto da
    /// resposta é o que diz se é o mesmo de antes ou um novo.
    fn marker_signature(&self, lines: &[String]) -> Option<String> {
        let marker = self.marker.as_ref()?;
        let last = lines
            .iter()
            .rposition(|line| marker.all().iter().any(|m| line.contains(m)))?;
        Some(lines[last.saturating_sub(3)..=last].join("\n"))
    }

    fn verdict(&self, lines: &[String]) -> Verdict {
        if self.marker.is_none() && self.question_patterns.is_empty() {
            return UNKNOWN;
        }
        let text = lines.join("\n");
        if let Some(marker) = &self.marker {
            match marker.latest(&text) {
                Some(Marker::Ask) => {
                    return Verdict {
                        outcome: Outcome::Asked,
                        via: "marcador",
                    };
                }
                Some(Marker::Ok) => {
                    return Verdict {
                        outcome: Outcome::Finished,
                        via: "marcador",
                    };
                }
                Some(Marker::Wait) => {
                    return Verdict {
                        outcome: Outcome::Background,
                        via: "marcador",
                    };
                }
                None => {}
            }
        }
        if self
            .question_patterns
            .iter()
            .any(|re| re.is_match(&text).unwrap_or(false))
        {
            return Verdict {
                outcome: Outcome::Asked,
                via: "padrão",
            };
        }
        UNKNOWN
    }

    /// Só solta quando a bancada está quieta, senão o prompt entra no meio de
    /// uma edição e embaralha o agente.
    pub(super) fn drain(&mut self, now: SystemTime, out: &mut Out) {
        // Antes de tudo: um texto colado sem Enter ainda não é uma entrega.
        self.flush_submit(now, out);
        self.confirm_delivery(now, out);
        // Uma entrega por vez.
        if self.unconfirmed.is_some() || self.queue.is_empty() || !self.is_idle(now) {
            return;
        }
        let Some(item) = self.queue.pop_front() else {
            return;
        };
        self.input_arrived();
        // Pedido seu, não de agente: a espera por vizinho de antes não cala
        // mais o fim deste turno.
        if item.chain.is_empty() {
            self.awaiting_peers.clear();
        }
        // A cadeia da mensagem entregue passa a ser a deste terminal.
        self.chain = item.chain;
        self.inject(&item.prompt, item.mode.as_deref(), &item.images, now, out);
        self.unconfirmed = Some(Unconfirmed {
            prompt: item.prompt,
            mode: item.mode,
            images: item.images,
            sent_at: now,
            attempts: 1,
        });
        log!(
            "dispatch[{}]: entregue ({} restando)",
            self.address,
            self.queue.len()
        );
    }

    /// Se a TUI recebeu a entrada, ela redesenha: saem bytes no pty. Silêncio
    /// total depois de uma entrega é que ninguém estava lendo.
    fn confirm_delivery(&mut self, now: SystemTime, out: &mut Out) {
        let Some(mut pending) = self.unconfirmed.clone() else {
            return;
        };
        // Enter por sair: reenviar colaria a mensagem duas vezes.
        if self.pending_submit.is_some() || since(now, pending.sent_at) < CONFIRM_AFTER {
            return;
        }
        if self.last_output > pending.sent_at {
            self.unconfirmed = None;
            return;
        }
        if pending.attempts >= DELIVERY_ATTEMPTS {
            log!(
                "dispatch[{}]: prompt perdido — nenhuma reação após {} tentativas",
                self.address,
                pending.attempts
            );
            self.unconfirmed = None;
            return;
        }
        pending.attempts += 1;
        pending.sent_at = now;
        self.inject(
            &pending.prompt,
            pending.mode.as_deref(),
            &pending.images,
            now,
            out,
        );
        log!(
            "dispatch[{}]: sem reação, reenviando (tentativa {})",
            self.address,
            pending.attempts
        );
        self.unconfirmed = Some(pending);
    }

    fn write(&self, bytes: Vec<u8>, out: &mut Out) {
        out.effects.push(Effect::Write {
            address: self.address.clone(),
            bytes,
        });
    }

    fn inject(
        &mut self,
        prompt: &str,
        mode: Option<&str>,
        images: &[String],
        now: SystemTime,
        out: &mut Out,
    ) {
        let mut config = self
            .profile
            .as_ref()
            .map_or_else(shell_inject, |p| p.inject.clone());
        if let Some(mode) = mode {
            mode.clone_into(&mut config.mode);
        }
        let mut pieces: VecDeque<String> = images.iter().cloned().collect();
        if !prompt.is_empty() {
            pieces.push_back(prompt.to_owned());
        }
        if config.mode == "bracketed-paste" {
            // Sem bracketed paste, cada \n vira um submit e a mensagem chega
            // picada (ADR-007).
            let first = pieces.pop_front().unwrap_or_else(|| prompt.to_owned());
            self.write(paste(&first), out);
            self.pending_pastes = pieces;
        } else {
            // Sem paste não há anexo: o caminho vai no texto, e o agente abre.
            let line = Vec::from(pieces).join(" ");
            self.write(line.into_bytes(), out);
        }
        // O Enter espera a TUI ficar quieta: um `\r` no meio do redesenho é
        // descartado e o prompt fica parado na caixa.
        self.pending_submit = Some((config, now));
    }

    /// Solta o Enter (ou a próxima colagem) quando a TUI parar de redesenhar.
    fn flush_submit(&mut self, now: SystemTime, out: &mut Out) {
        let Some((config, pasted_at)) = self.pending_submit.clone() else {
            return;
        };
        let since_paste = since(now, pasted_at);
        let since_output = since(now, self.last_output);
        if since_paste < config.submit_delay() {
            return;
        }
        // Teto para não ficar refém de uma TUI que nunca se cala.
        if since_output < QUIET_BEFORE_SUBMIT && since_paste < SUBMIT_DEADLINE {
            return;
        }
        if let Some(next) = self.pending_pastes.pop_front() {
            self.write(paste(&next), out);
            self.pending_submit = Some((config, now));
            return;
        }
        self.write(config.submit.into_bytes(), out);
        self.pending_submit = None;
        log!(
            "dispatch[{}]: enter enviado {:.0}ms após o texto",
            self.address,
            since_paste.as_secs_f64() * 1000.0
        );
    }
}

/// Identifica uma parada relatada por gancho; o instante entra porque dois
/// turnos seguidos produzem o mesmo evento.
fn hook_token(event: &str, now: SystemTime) -> String {
    format!("gancho:{event}@{:.2}", secs(now))
}
