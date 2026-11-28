//! Datas do chat: instante como `SystemTime` e ISO-8601 UTC com milissegundos
//! no disco, que é como o `ChatHistory` do Swift grava — a fração de segundo
//! entra porque dois agentes respondendo no mesmo segundo se ordenam por ela.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Deserializer, Serializer};

pub use crate::features::dispatch::marker::parse_iso8601 as parse_iso;

/// `2026-08-25T17:00:00.250Z`, truncando abaixo do milissegundo como o
/// `ISO8601DateFormatter` do Swift.
pub fn format_iso(at: SystemTime) -> String {
    let (secs, millis) = match at.duration_since(UNIX_EPOCH) {
        Ok(d) => (d.as_secs() as i64, d.subsec_millis()),
        Err(e) => {
            let d = e.duration();
            let whole = d.as_secs() as i64;
            let sub = d.subsec_millis();
            if sub == 0 {
                (-whole, 0)
            } else {
                (-whole - 1, 1000 - sub)
            }
        }
    };
    let (year, month, day) = civil_from_days(secs.div_euclid(86_400));
    let rest = secs.rem_euclid(86_400);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}.{millis:03}Z",
        rest / 3600,
        rest % 3600 / 60,
        rest % 60
    )
}

/// Dias desde 1970-01-01 → (ano, mês, dia), gregoriano proléptico (Hinnant).
fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    (year, month, day)
}

/// `yyyyMMdd-HHmmss` num fuso fixo (`offset_secs` a leste de UTC): é o relógio
/// do nome do arquivo arquivado. O fuso entra como parâmetro porque o Swift usa
/// o do sistema e o core não lê relógio nem fuso por conta própria.
pub fn format_clock(at: SystemTime, offset_secs: i64) -> String {
    let secs = signed_secs(at) + offset_secs;
    let (year, month, day) = civil_from_days(secs.div_euclid(86_400));
    let rest = secs.rem_euclid(86_400);
    format!(
        "{year:04}{month:02}{day:02}-{:02}{:02}{:02}",
        rest / 3600,
        rest % 3600 / 60,
        rest % 60
    )
}

/// O fuso de uma data: segundos a leste de UTC que o sistema tinha NAQUELE
/// instante (`commons::clock::local_offset_secs`). Função e não número porque o
/// `DateFormatter` do Swift aplica o fuso de cada data — com horário de verão, o
/// arquivo criado meses atrás pode ter outro deslocamento que o de agora.
pub type Offset = fn(SystemTime) -> i64;

/// UTC, para os testes e para quem não quer fuso.
pub fn utc(_: SystemTime) -> i64 {
    0
}

/// O inverso de [`format_clock`], com o fuso da própria data: o relógio local
/// não diz o instante sozinho, então o deslocamento é achado em duas passadas
/// (o de depois de aplicar o primeiro vale na fronteira do verão).
pub fn parse_clock(raw: &str, offset: Offset) -> Option<SystemTime> {
    let naive = parse_clock_at(raw, 0)?;
    let first = offset(naive);
    let guess = parse_clock_at(raw, first)?;
    parse_clock_at(raw, offset(guess))
}

fn parse_clock_at(raw: &str, offset_secs: i64) -> Option<SystemTime> {
    let b = raw.as_bytes();
    if b.len() != 15 || b[8] != b'-' {
        return None;
    }
    let num = |from: usize, len: usize| -> Option<i64> {
        let s = raw.get(from..from + len)?;
        s.bytes()
            .all(|c| c.is_ascii_digit())
            .then(|| s.parse().ok())?
    };
    let (year, month, day) = (num(0, 4)?, num(4, 2)?, num(6, 2)?);
    let (hour, minute, second) = (num(9, 2)?, num(11, 2)?, num(13, 2)?);
    if !(1..=12).contains(&month)
        || !(1..=31).contains(&day)
        || hour > 23
        || minute > 59
        || second > 60
    {
        return None;
    }
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    from_signed_secs(days * 86_400 + hour * 3600 + minute * 60 + second - offset_secs)
}

pub fn signed_secs(at: SystemTime) -> i64 {
    match at.duration_since(UNIX_EPOCH) {
        Ok(d) => d.as_secs() as i64,
        Err(e) => -(e.duration().as_secs() as i64),
    }
}

fn from_signed_secs(secs: i64) -> Option<SystemTime> {
    if secs >= 0 {
        UNIX_EPOCH.checked_add(Duration::from_secs(secs as u64))
    } else {
        UNIX_EPOCH.checked_sub(Duration::from_secs(secs.unsigned_abs()))
    }
}

/// Segundos (com fração) desde 1970, para a chave do eco local e para somar
/// intervalos nos testes.
pub fn unix_f64(at: SystemTime) -> f64 {
    match at.duration_since(UNIX_EPOCH) {
        Ok(d) => d.as_secs_f64(),
        Err(e) => -e.duration().as_secs_f64(),
    }
}

/// O `description` Swift de um `Double` (`1787678363.0`, sem notação
/// científica): é o que entra na chave do eco local e no id de turno sem `uuid`.
pub fn swift_double(value: f64) -> String {
    let text = format!("{value}");
    if text.contains('.') {
        text
    } else {
        format!("{text}.0")
    }
}

/// `serde(with = "iso")` para `SystemTime`.
pub mod iso {
    use super::*;

    pub fn serialize<S: Serializer>(at: &SystemTime, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&format_iso(*at))
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<SystemTime, D::Error> {
        let raw = String::deserialize(d)?;
        parse_iso(&raw).ok_or_else(|| serde::de::Error::custom(format!("data inválida: {raw}")))
    }
}

/// `serde(with = "iso_opt")` para `Option<SystemTime>`.
pub mod iso_opt {
    use super::*;

    pub fn serialize<S: Serializer>(at: &Option<SystemTime>, s: S) -> Result<S::Ok, S::Error> {
        match at {
            Some(at) => s.serialize_str(&format_iso(*at)),
            None => s.serialize_none(),
        }
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Option<SystemTime>, D::Error> {
        match Option::<String>::deserialize(d)? {
            None => Ok(None),
            Some(raw) => parse_iso(&raw)
                .map(Some)
                .ok_or_else(|| serde::de::Error::custom(format!("data inválida: {raw}"))),
        }
    }
}
