//! Porte de `ActivityTests`, `ActivitySummaryTests`, `SystemNoticeTests` e da
//! regra de `AttentionRingTests`. Cor, rótulo e o anel desenhado são da UI.

use std::time::{Duration, SystemTime};

use super::model::{Activity, ActivitySummary, RingTone};
use super::notice::{Announcer, SOUND_INTERVAL, system_notice};

#[test]
fn only_asking_and_failed_interrupt() {
    assert!(Activity::Asking.needs_attention());
    assert!(Activity::Failed("x".into()).needs_attention());
    for state in [
        Activity::Starting,
        Activity::Ready,
        Activity::Working,
        Activity::Waiting,
        Activity::Background,
        Activity::Awaiting(vec!["back".into()]),
        Activity::Retrying {
            attempt: 1,
            at: SystemTime::UNIX_EPOCH,
        },
        Activity::Dead,
    ] {
        assert!(!state.needs_attention(), "{state:?} não pode interromper");
    }
}

fn summary(f: impl FnOnce(&mut ActivitySummary)) -> ActivitySummary {
    let mut s = ActivitySummary::default();
    f(&mut s);
    s
}

#[test]
fn only_starting_is_preparing() {
    assert!(summary(|s| s.starting = 2).is_preparing());
    assert!(summary(|s| s.starting = 1).is_preparing());
}

#[test]
fn any_other_activity_is_not_preparing() {
    assert!(
        !summary(|s| {
            s.starting = 1;
            s.working = 1
        })
        .is_preparing()
    );
    assert!(
        !summary(|s| {
            s.starting = 1;
            s.attention = 1
        })
        .is_preparing()
    );
    assert!(
        !summary(|s| {
            s.starting = 1;
            s.done = 1
        })
        .is_preparing()
    );
    assert!(
        !summary(|s| {
            s.starting = 1;
            s.background = 1
        })
        .is_preparing()
    );
    assert!(!ActivitySummary::default().is_preparing());
}

#[test]
fn summary_counts_failures_inside_attention_and_background() {
    let mut s = ActivitySummary::default();
    s.count(&Activity::Failed("x".into()));
    s.count(&Activity::Retrying {
        attempt: 1,
        at: SystemTime::UNIX_EPOCH,
    });
    s.count(&Activity::Awaiting(vec![]));
    assert_eq!(
        (s.attention, s.background, s.failed, s.retrying),
        (1, 2, 2, 1)
    );
}

#[test]
fn orange_beats_green() {
    assert_eq!(RingTone::for_summary(&summary(|s| s.working = 2)), None);
    assert_eq!(
        RingTone::for_summary(&summary(|s| s.done = 1)),
        Some(RingTone::Done)
    );
    assert_eq!(
        RingTone::for_summary(&summary(|s| {
            s.attention = 1;
            s.done = 3
        })),
        Some(RingTone::Asking)
    );
}

#[test]
fn asking_carries_what_is_waiting() {
    let n = system_notice(
        "testes-bancada/dev",
        &Activity::Asking,
        Some("rm -rf build\nls"),
    )
    .unwrap();
    assert_eq!(n.workbench, "testes-bancada");
    assert_eq!(n.node, "dev");
    assert_eq!(n.title, "A bancada testes-bancada precisa de você");
    assert_eq!(n.body, "dev: rm -rf build ls");
    assert_eq!(n.identifier, "egeon.testes-bancada/dev");
}

#[test]
fn finished_without_detail() {
    let done = system_notice("deck/revisor", &Activity::Waiting, None).unwrap();
    assert_eq!(done.title, "A bancada deck já terminou o serviço");
    assert_eq!(done.body, "revisor");
    assert_eq!(
        system_notice("deck/revisor", &Activity::Waiting, Some("  "))
            .unwrap()
            .body,
        "revisor"
    );
}

#[test]
fn failed_tells_why() {
    let n = system_notice(
        "deck/dev",
        &Activity::Failed("API sobrecarregada".into()),
        None,
    )
    .unwrap();
    assert_eq!(n.title, "A bancada deck parou por um erro");
    assert_eq!(n.body, "dev: API sobrecarregada");
}

#[test]
fn states_that_come_back_alone_do_not_notify() {
    for activity in [
        Activity::Working,
        Activity::Starting,
        Activity::Ready,
        Activity::Background,
        Activity::Awaiting(vec!["dev".into()]),
        Activity::Retrying {
            attempt: 1,
            at: SystemTime::UNIX_EPOCH,
        },
        Activity::Dead,
    ] {
        assert!(system_notice("deck/revisor", &activity, None).is_none());
    }
    assert!(system_notice("sem-barra", &Activity::Asking, None).is_none());
}

#[test]
fn long_detail_is_clipped() {
    let body = system_notice("a/b", &Activity::Asking, Some(&"x".repeat(500)))
        .unwrap()
        .body;
    assert!(body.ends_with('…'));
    assert!(body.chars().count() < 220);
}

fn t(ms: u64) -> SystemTime {
    SystemTime::UNIX_EPOCH + Duration::from_millis(ms)
}

#[test]
fn in_front_only_the_question_sounds_and_nothing_is_posted() {
    let mut a = Announcer::new();
    let asked = a.announce(
        "deck/b",
        &Activity::Asking,
        None,
        Some("Tink"),
        0.3,
        true,
        true,
        t(0),
    );
    assert_eq!(asked.notice, None);
    assert_eq!(asked.sound, Some(("Tink".to_owned(), 0.3)));
    let done = a.announce(
        "deck/b",
        &Activity::Waiting,
        None,
        Some("Tink"),
        0.3,
        true,
        true,
        t(5_000),
    );
    assert_eq!((done.notice, done.sound), (None, None));
}

#[test]
fn away_the_notification_sounds_instead() {
    let mut a = Announcer::new();
    let away = a.announce(
        "deck/b",
        &Activity::Asking,
        Some("ls"),
        Some("Tink"),
        0.3,
        false,
        true,
        t(0),
    );
    assert_eq!(away.sound, None, "a central toca o dela");
    assert_eq!(away.notice.map(|n| n.body), Some("b: ls".to_owned()));
    // Sem autorização a central não toca: o som de atenção toca.
    let denied = a.announce(
        "deck/b",
        &Activity::Asking,
        None,
        Some("Tink"),
        0.3,
        false,
        false,
        t(0),
    );
    assert!(denied.sound.is_some());
    assert!(denied.notice.is_some());
}

#[test]
fn sounds_keep_a_minimum_interval_and_respect_silence() {
    let mut a = Announcer::new();
    let ask = |a: &mut Announcer, ms, sound, volume| {
        a.announce(
            "deck/b",
            &Activity::Asking,
            None,
            sound,
            volume,
            true,
            false,
            t(ms),
        )
        .sound
    };
    assert!(ask(&mut a, 0, Some("Tink"), 0.3).is_some());
    assert!(ask(&mut a, 1_000, Some("Tink"), 0.3).is_none());
    let after = u64::try_from(SOUND_INTERVAL.as_millis()).unwrap();
    assert!(ask(&mut a, after, Some("Tink"), 0.3).is_some());
    assert!(ask(&mut a, 10_000, None, 0.3).is_none());
    assert!(ask(&mut a, 20_000, Some(""), 0.3).is_none());
    assert!(ask(&mut a, 30_000, Some("Tink"), 0.0).is_none());
}

#[test]
fn failed_sounds_and_retrying_is_never_announced() {
    let mut a = Announcer::new();
    let failed = a.announce(
        "deck/b",
        &Activity::Failed("x".into()),
        None,
        Some("Tink"),
        0.3,
        true,
        false,
        t(0),
    );
    assert!(failed.sound.is_some());
    let retrying = Activity::Retrying {
        attempt: 1,
        at: SystemTime::UNIX_EPOCH,
    };
    let out = a.announce(
        "deck/b",
        &retrying,
        None,
        Some("Tink"),
        0.3,
        false,
        false,
        t(10_000),
    );
    assert_eq!((out.notice, out.sound), (None, None));
}

#[test]
fn a_sound_left_to_the_center_does_not_open_the_window() {
    let mut a = Announcer::new();
    let away = a.announce(
        "deck/b",
        &Activity::Asking,
        None,
        Some("Tink"),
        0.3,
        false,
        true,
        t(0),
    );
    assert_eq!(away.sound, None);
    let front = a.announce(
        "deck/b",
        &Activity::Asking,
        None,
        Some("Tink"),
        0.3,
        true,
        true,
        t(100),
    );
    assert!(front.sound.is_some(), "nenhum som tocou antes");
}

#[test]
fn unknown_sound_does_not_silence_the_next() {
    let mut a = Announcer::new();
    assert!(
        a.announce(
            "deck/b",
            &Activity::Asking,
            None,
            Some("NaoExiste"),
            0.3,
            true,
            false,
            t(0)
        )
        .sound
        .is_some()
    );
    a.sound_failed();
    assert!(
        a.announce(
            "deck/b",
            &Activity::Asking,
            None,
            Some("Tink"),
            0.3,
            true,
            false,
            t(100)
        )
        .sound
        .is_some()
    );
}
