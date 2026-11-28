//! O clique numa notificação do sistema (US-202).

use super::Actor;
use super::org_commands::request;
use crate::features::workspace::routes as org_routes;
use crate::ports::notifier::NoticeClick;
use crate::protocol::app::AppEffect;
use crate::protocol::routes::FeatureRoute;

impl Actor {
    /// O `onOpen` do `SystemNotifier` (main.swift:590): a bancada do aviso
    /// vira a ativa, o chat foca o terminal e o app vem para a frente. Bancada
    /// que já não está na faixa não faz nada, como o `activateWorkbench`
    /// que devolve falso.
    pub(crate) fn notice_clicked(&mut self, click: NoticeClick) {
        let name = click.workbench;
        let (reply, effects) = org_routes::activate(
            &self.org.state,
            &request("/activate", &[("target", name.clone())]),
        );
        if reply.status != 200 {
            crate::log!("notificação: a bancada \"{name}\" já não está aberta");
            return;
        }
        self.apply_org(effects);
        let focus = request("/chat", &[("target", name), ("focus", click.node)]);
        // O mesmo caminho do `/chat?focus=`; ninguém espera a resposta.
        let (reply, _) = tokio::sync::oneshot::channel();
        self.feature_route(FeatureRoute::Chat, focus, reply);
        self.app_effect(AppEffect::Activate);
    }
}
