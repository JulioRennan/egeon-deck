//! A central de notificações (`UserNotifications`) e o `NSSound` do macOS.

use std::collections::HashMap;
use std::ptr::NonNull;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, PoisonError};

use block2::{DynBlock, RcBlock};
use egeon_core::log;
use egeon_core::ports::notifier::{Notice, NoticeClick, SoundError};
use objc2::rc::Retained;
use objc2::runtime::{AnyObject, Bool, ProtocolObject};
use objc2::{AnyThread, DefinedClass, define_class, msg_send};
use objc2_app_kit::NSSound;
use objc2_foundation::{
    NSArray, NSBundle, NSDictionary, NSError, NSObject, NSObjectProtocol, NSString,
};
use objc2_user_notifications::{
    UNAuthorizationOptions, UNAuthorizationStatus, UNMutableNotificationContent,
    UNNotificationRequest, UNNotificationResponse, UNNotificationSettings, UNNotificationSound,
    UNUserNotificationCenter, UNUserNotificationCenterDelegate,
};
use tokio::sync::mpsc;

/// Cliques pendentes de leitura pelo core.
const CLICK_CAPACITY: usize = 16;
const WORKBENCH_KEY: &str = "workbench";
const NODE_KEY: &str = "node";

struct DelegateState {
    clicks: mpsc::Sender<NoticeClick>,
}

define_class!(
    /// Recebe o clique no aviso e o entrega ao core. O Swift trazia o app para
    /// a frente aqui (`NSApp.activate`); agora quem faz isso é a UI, ao receber
    /// do core o evento do clique.
    #[unsafe(super(NSObject))]
    #[name = "EgeonNoticeDelegate"]
    #[ivars = DelegateState]
    struct Delegate;

    unsafe impl NSObjectProtocol for Delegate {}

    unsafe impl UNUserNotificationCenterDelegate for Delegate {
        #[unsafe(method(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:))]
        fn did_receive(
            &self,
            _center: &UNUserNotificationCenter,
            response: &UNNotificationResponse,
            completion: &DynBlock<dyn Fn()>,
        ) {
            let info = response.notification().request().content().userInfo();
            let text = |key: &str| {
                let value = info.objectForKey(&NSString::from_str(key))?;
                value.downcast::<NSString>().ok().map(|s| s.to_string())
            };
            if let (Some(workbench), Some(node)) = (text(WORKBENCH_KEY), text(NODE_KEY)) {
                // Cheio é a UI sem ler cliques: o mais novo não vale esperar.
                let _ = self
                    .ivars()
                    .clicks
                    .try_send(NoticeClick { workbench, node });
            }
            completion.call(());
        }
    }
);

// SAFETY: o único estado é um `mpsc::Sender`, que é `Send + Sync` e imutável
// depois do `init`; a central chama o delegate de qualquer fila.
unsafe impl Send for Delegate {}
// SAFETY: idem.
unsafe impl Sync for Delegate {}

impl Delegate {
    fn new(clicks: mpsc::Sender<NoticeClick>) -> Retained<Self> {
        let this = Self::alloc().set_ivars(DelegateState { clicks });
        // SAFETY: `init` do `NSObject`, sobre um objeto recém-alocado.
        unsafe { msg_send![super(this), init] }
    }
}

/// A central existe só dentro de um bundle `.app`: fora dele o
/// `UNUserNotificationCenter` derruba o processo.
fn center() -> Option<Retained<UNUserNotificationCenter>> {
    let extension = NSBundle::mainBundle().bundleURL().pathExtension()?;
    if extension.to_string() != "app" {
        return None;
    }
    Some(UNUserNotificationCenter::currentNotificationCenter())
}

#[derive(Default)]
pub(super) struct Center {
    authorized: Arc<AtomicBool>,
    asked: AtomicBool,
    /// O `delegate` da central é uma referência fraca: sem isto o clique
    /// deixaria de chegar assim que `start` voltasse.
    delegate: Mutex<Option<Retained<Delegate>>>,
    /// Negada, o log diria isso a cada aviso: uma vez basta.
    denial_logged: Arc<AtomicBool>,
}

impl Center {
    pub(super) fn start(&self) -> mpsc::Receiver<NoticeClick> {
        let (clicks, receiver) = mpsc::channel(CLICK_CAPACITY);
        let Some(center) = center() else {
            return receiver;
        };
        let delegate = Delegate::new(clicks);
        center.setDelegate(Some(ProtocolObject::from_ref(&*delegate)));
        *self.delegate.lock().unwrap_or_else(PoisonError::into_inner) = Some(delegate);
        self.authorize(&center);
        receiver
    }

    pub(super) fn authorized(&self) -> bool {
        self.authorized.load(Ordering::Relaxed)
    }

    fn authorize(&self, center: &UNUserNotificationCenter) {
        if self.asked.swap(true, Ordering::Relaxed) {
            return;
        }
        let authorized = Arc::clone(&self.authorized);
        let handler = RcBlock::new(move |granted: Bool, error: *mut NSError| {
            authorized.store(granted.as_bool(), Ordering::Relaxed);
            // SAFETY: o sistema passa nulo ou um `NSError` vivo durante a chamada.
            let reason = unsafe { error.as_ref() }
                .map(|e| format!(" — {}", e.localizedDescription()))
                .unwrap_or_default();
            log!(
                "notificação: {}{reason}",
                if granted.as_bool() {
                    "autorizada"
                } else {
                    "negada"
                }
            );
        });
        center.requestAuthorizationWithOptions_completionHandler(
            UNAuthorizationOptions::Alert | UNAuthorizationOptions::Sound,
            &handler,
        );
    }

    pub(super) fn post(&self, notice: Notice) {
        let Some(center) = center() else {
            return;
        };
        if self.authorized() {
            add(&center, &notice);
            return;
        }
        // Negada no arranque e liberada depois nos Ajustes: reconsulta.
        let authorized = Arc::clone(&self.authorized);
        let denial_logged = Arc::clone(&self.denial_logged);
        let handler = RcBlock::new(move |settings: NonNull<UNNotificationSettings>| {
            // SAFETY: o sistema passa as configurações vivas durante a chamada.
            let status = unsafe { settings.as_ref() }.authorizationStatus();
            if status != UNAuthorizationStatus::Authorized {
                if !denial_logged.swap(true, Ordering::Relaxed) {
                    log!("notificação: sem autorização (status {})", status.0);
                }
                return;
            }
            authorized.store(true, Ordering::Relaxed);
            if let Some(center) = self::center() {
                add(&center, &notice);
            }
        });
        center.getNotificationSettingsWithCompletionHandler(&handler);
    }

    pub(super) fn withdraw(&self, identifier: &str) {
        let Some(center) = center() else {
            return;
        };
        let identifiers = NSArray::from_retained_slice(&[NSString::from_str(identifier)]);
        center.removeDeliveredNotificationsWithIdentifiers(&identifiers);
    }
}

fn add(center: &UNUserNotificationCenter, notice: &Notice) {
    let content = UNMutableNotificationContent::new();
    content.setTitle(&NSString::from_str(&notice.title));
    content.setBody(&NSString::from_str(&notice.body));
    let (workbench_key, node_key) = (
        NSString::from_str(WORKBENCH_KEY),
        NSString::from_str(NODE_KEY),
    );
    let keys = [&*workbench_key, &*node_key];
    let values: [Retained<AnyObject>; 2] = [
        NSString::from_str(&notice.workbench).into(),
        NSString::from_str(&notice.node).into(),
    ];
    let info = NSDictionary::from_retained_objects(&keys, &values);
    // SAFETY: os genéricos do `NSDictionary` só existem no tipo, não no objeto;
    // a API pede as chaves como `AnyObject` e elas são `NSString`. O `userInfo`
    // exige tipos de plist, e chaves e valores são só `NSString`.
    unsafe {
        let info = Retained::cast_unchecked::<NSDictionary<AnyObject>>(info);
        content.setUserInfo(&info);
    }
    content.setSound(Some(&UNNotificationSound::defaultSound()));
    let request = UNNotificationRequest::requestWithIdentifier_content_trigger(
        &NSString::from_str(&notice.identifier),
        &content,
        None,
    );
    let (workbench, node, body) = (
        notice.workbench.clone(),
        notice.node.clone(),
        notice.body.clone(),
    );
    let handler = RcBlock::new(move |error: *mut NSError| {
        // SAFETY: nulo ou um `NSError` vivo durante a chamada.
        match unsafe { error.as_ref() } {
            Some(e) => log!(
                "notificação[{workbench}/{node}]: falhou — {}",
                e.localizedDescription()
            ),
            None => log!("notificação[{workbench}/{node}]: {body}"),
        }
    });
    center.addNotificationRequest_withCompletionHandler(&request, Some(&handler));
}

/// Um `NSSound` por nome: recriar a cada aviso relê o arquivo do disco à toa.
#[derive(Default)]
pub(super) struct Sounds {
    cache: Mutex<HashMap<String, Cached>>,
}

struct Cached(Retained<NSSound>);

// SAFETY: o `NSSound` fica sempre atrás do `Mutex` de `Sounds`: nenhuma thread
// o usa enquanto outra o usa, e ele não tem afinidade com a thread principal.
unsafe impl Send for Cached {}

impl Sounds {
    /// `name` é um som do sistema (`/System/Library/Sounds`) ou do usuário
    /// (`~/Library/Sounds`).
    pub(super) fn play(&self, name: &str, volume: f64) -> Result<(), SoundError> {
        if name.is_empty() || volume <= 0.0 {
            return Ok(());
        }
        let mut cache = self.cache.lock().unwrap_or_else(PoisonError::into_inner);
        if !cache.contains_key(name) {
            let sound = NSSound::soundNamed(&NSString::from_str(name))
                .ok_or_else(|| SoundError::Unknown(name.to_string()))?;
            cache.insert(name.to_string(), Cached(sound));
        }
        let Some(Cached(sound)) = cache.get(name) else {
            return Ok(());
        };
        sound.setVolume(volume.clamp(0.0, 1.0) as f32);
        // `play` num som que já toca devolve falso e o segundo sumiria:
        // reiniciar do zero é o comportamento esperado. Sem run loop o
        // `isPlaying` nunca volta a falso, então o `stop` vai sempre; é ele que
        // faz o `play` seguinte, de uma thread de fundo, devolver verdadeiro.
        sound.stop();
        if !sound.play() {
            log!("atenção: o som \"{name}\" não tocou");
        }
        Ok(())
    }
}
