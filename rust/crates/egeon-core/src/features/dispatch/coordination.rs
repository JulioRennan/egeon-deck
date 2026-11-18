//! O estado de coordenação que o ator guarda: o Dispatcher, a mesa de
//! permissões e a decisão de aviso. Junta o que no Swift eram três singletons
//! (`Dispatcher.shared`, `PermissionDesk.shared`, `SystemNotifier`/
//! `AttentionSound`) e resolve entre eles os efeitos internos — fechar o
//! pedido de permissão, dar a resposta por recebida —, devolvendo ao ator só
//! o que sai para fora: [`Outward`].

use std::path::PathBuf;
use std::time::SystemTime;

use super::profile::TargetProfile;
use super::service::{Dispatcher, Topology};
use super::target::{Effect, Surface};
use crate::features::activity::model::Activity;
use crate::features::activity::notice::{Announcer, SystemNotice, identifier};
use crate::features::edge::model::EdgeConfig;
use crate::features::maestro::controller::MaestroEffect;
use crate::features::maestro::links;
use crate::features::permission::service::PermissionDesk;
use crate::features::workbench::model::WorkbenchConfig;

/// O que o Dispatcher lê do mundo, além da tela.
pub trait World: Surface {
    /// A bancada pelo nome — a primeira parte do endereço.
    fn workbench(&self, name: &str) -> Option<WorkbenchConfig>;
    /// A UI está na frente: a borda já diz tudo, e a notificação não sai.
    fn app_active(&self) -> bool;
    /// A central de notificações vai tocar o som dela.
    fn notifier_authorized(&self) -> bool;
}

/// As arestas que valem para as guardas e o `egeon peers`: as desenhadas mais
/// as implícitas do maestro (`AppControl.workbenchEdges` do Swift); o papel é
/// o `effectivePrompt` do nó (`AppControl.nodeRole`).
pub struct Links<'a>(pub &'a dyn World);

impl Topology for Links<'_> {
    fn edges(&self, workbench: &str) -> Vec<EdgeConfig> {
        self.0
            .workbench(workbench)
            .map(|b| links::effective(&b))
            .unwrap_or_default()
    }

    fn role(&self, address: &str) -> Option<String> {
        let (bench, node) = address.split_once('/')?;
        let bench = self.0.workbench(bench)?;
        bench
            .nodes
            .iter()
            .find(|n| n.id == node)?
            .effective_prompt()
            .map(str::to_owned)
    }
}

/// O que o ator executa.
#[derive(Debug, Clone, PartialEq)]
pub enum Outward {
    /// Bytes para o pty do terminal.
    Write { address: String, bytes: Vec<u8> },
    /// Para a central de notificações (`ports::notifier`, mesmos campos).
    Notify(SystemNotice),
    /// O som de atenção.
    Sound { name: String, volume: f64 },
    /// Tira da central o aviso deste identificador.
    Withdraw { identifier: String },
    /// O turno fechou e o transcript está em dia: o histórico do chat lê.
    TurnEnded {
        address: String,
        transcript: Option<PathBuf>,
        started_at: Option<SystemTime>,
    },
    /// O CLI relatou a conversa aberta (`AppControl.recordConversation`).
    Conversation {
        address: String,
        id: String,
        transcript: Option<String>,
    },
    /// O que o maestro mandou mudar na bancada, na ordem.
    Maestro(MaestroEffect),
}

#[derive(Default)]
pub struct Coordination {
    pub dispatcher: Dispatcher,
    pub desk: PermissionDesk,
    announcer: Announcer,
}

impl Coordination {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn register(
        &mut self,
        address: impl Into<String>,
        profile: Option<TargetProfile>,
        hooked: bool,
        now: SystemTime,
    ) {
        self.dispatcher.register(address, profile, hooked, now);
    }

    pub fn unregister(
        &mut self,
        address: &str,
        now: SystemTime,
        world: &dyn World,
    ) -> Vec<Outward> {
        let effects = self.dispatcher.unregister(address, now);
        self.absorb(effects, now, world)
    }

    /// A bancada foi renomeada: o alvo, as esperas e os pedidos seguem.
    pub fn rekey(&mut self, old: &str, new: &str) -> bool {
        if !self.dispatcher.rekey(old, new) {
            return false;
        }
        self.desk.renamed(old, new);
        true
    }

    /// Saíram bytes do pty (a tela já os recebeu).
    pub fn output(&mut self, address: &str, now: SystemTime, world: &dyn World) {
        self.dispatcher.output(address, now, world);
    }

    /// Quando chamar `tick` antes do próximo tique: a releitura do `Stop` e a
    /// nova tentativa têm hora marcada.
    pub fn next_deadline(&self) -> Option<SystemTime> {
        self.dispatcher.next_deadline()
    }

    /// O laço de 0,25s (`service::TICK`).
    pub fn tick(&mut self, now: SystemTime, world: &dyn World) -> Vec<Outward> {
        let effects = self.dispatcher.tick(now, world);
        self.absorb(effects, now, world)
    }

    /// Você digitou dentro do terminal (não a injeção).
    pub fn user_typed(
        &mut self,
        address: &str,
        now: SystemTime,
        world: &dyn World,
    ) -> Vec<Outward> {
        let effects = self.dispatcher.user_typed(address, now);
        self.absorb(effects, now, world)
    }

    /// O `Outward::Sound` falhou no driver (som que não existe): o próximo
    /// pode tocar já.
    pub fn sound_failed(&mut self) {
        self.announcer.sound_failed();
    }

    pub fn workbench_opened(&mut self, name: &str) {
        self.dispatcher.workbench_opened(name);
    }

    /// O pedido foi respondido daqui: o terminal volta ao trabalho e o laranja
    /// cai.
    pub(crate) fn answered(
        &mut self,
        address: &str,
        now: SystemTime,
        world: &dyn World,
    ) -> Vec<Outward> {
        let effects = self.dispatcher.permission_answered(address, now);
        self.absorb(effects, now, world)
    }

    pub(crate) fn hook(
        &mut self,
        address: &str,
        hook: super::target::Hook,
        now: SystemTime,
        world: &dyn World,
    ) -> Option<Vec<Outward>> {
        let effects = self.dispatcher.hook_reported(address, hook, now, world)?;
        Some(self.absorb(effects, now, world))
    }

    /// O terminal por trás de um gancho: pelo pid da conexão; `target` na
    /// query só como reserva — um `curl` seu ou um script antigo em disco.
    pub(crate) fn hook_caller(&self, origin: Option<&str>, named: Option<&str>) -> Option<String> {
        if let Some(origin) = origin.filter(|o| self.dispatcher.target(o).is_some()) {
            return Some(origin.to_owned());
        }
        let named = named.filter(|n| !n.is_empty())?;
        self.dispatcher.target(named)?;
        crate::log!("gancho[{named}]: pid não resolveu o terminal; usando target da query");
        Some(named.to_owned())
    }

    /// Os efeitos do Dispatcher resolvidos: os internos aqui, os de fora para
    /// o ator.
    pub(crate) fn absorb(
        &mut self,
        effects: Vec<Effect>,
        now: SystemTime,
        world: &dyn World,
    ) -> Vec<Outward> {
        let mut out = Vec::new();
        for effect in effects {
            match effect {
                Effect::Write { address, bytes } => out.push(Outward::Write { address, bytes }),
                Effect::DropPermissions { address, why } => self.desk.drop(&address, Some(why)),
                Effect::Withdraw { address } => out.push(Outward::Withdraw {
                    identifier: identifier(&address),
                }),
                Effect::TurnEnded {
                    address,
                    transcript,
                    started_at,
                } => out.push(Outward::TurnEnded {
                    address,
                    transcript,
                    started_at,
                }),
                Effect::Announce {
                    address,
                    activity,
                    sound,
                    volume,
                } => {
                    let detail = (activity == Activity::Asking)
                        .then(|| self.desk.last_summary(&address, now))
                        .flatten();
                    let said = self.announcer.announce(
                        &address,
                        &activity,
                        detail.as_deref(),
                        sound.as_deref(),
                        volume,
                        world.app_active(),
                        world.notifier_authorized(),
                        now,
                    );
                    if let Some((name, volume)) = said.sound {
                        out.push(Outward::Sound { name, volume });
                    }
                    if let Some(notice) = said.notice {
                        out.push(Outward::Notify(notice));
                    }
                }
            }
        }
        out
    }

    /// O `pending` e a contagem de `peers` do `GET /status` deste terminal.
    pub fn status(&self, address: &str, world: &dyn World) -> Option<(usize, usize)> {
        let target = self.dispatcher.target(address)?;
        let peers = self.dispatcher.peers(address, &Links(world)).len();
        Some((target.pending(), peers))
    }
}
