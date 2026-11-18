//! A hora local do sistema (decisão 34): o core a lê direto, sem interface no
//! driver. A trilha e o chat gravam a hora local, como o `DateFormatter` do
//! Swift, que aplica o fuso DE CADA data — com horário de verão, o arquivo
//! criado meses atrás pode ter outro deslocamento que o de agora.

use std::time::SystemTime;

use jiff::Timestamp;
use jiff::tz::TimeZone;

/// O deslocamento de UTC, em segundos a leste, que o fuso do sistema tinha em
/// `at`. Zero se a data não cabe no calendário ou o sistema não diz o fuso
/// (`TimeZone::system` cai em UTC).
pub fn local_offset_secs(at: SystemTime) -> i64 {
    offset_in(&TimeZone::system(), at)
}

/// O deslocamento de `zone` em `at`. Separado para o teste usar um fuso com
/// horário de verão sem mexer no ambiente do processo.
pub fn offset_in(zone: &TimeZone, at: SystemTime) -> i64 {
    Timestamp::try_from(at).map_or(0, |instant| i64::from(zone.to_offset(instant).seconds()))
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, UNIX_EPOCH};

    use super::*;

    fn at(secs: u64) -> SystemTime {
        UNIX_EPOCH + Duration::from_secs(secs)
    }

    #[test]
    fn o_deslocamento_acompanha_o_horario_de_verao_de_cada_data() {
        let Ok(zone) = TimeZone::get("America/New_York") else {
            // Sem banco de fusos no sistema não há como conferir o verão.
            return;
        };
        // 2026-01-15 12:00 UTC: inverno, -5 h. 2026-07-15 12:00 UTC: verão, -4 h.
        assert_eq!(offset_in(&zone, at(1_768_478_400)), -5 * 3600);
        assert_eq!(offset_in(&zone, at(1_784_116_800)), -4 * 3600);
    }

    #[test]
    fn utc_e_zero_e_o_fuso_do_sistema_devolve_algo_plausivel() {
        assert_eq!(offset_in(&TimeZone::UTC, at(1_787_678_363)), 0);
        // Qualquer fuso do planeta fica entre -12 h e +14 h.
        let offset = local_offset_secs(SystemTime::now());
        assert!((-12 * 3600..=14 * 3600).contains(&offset), "{offset}");
    }

    #[test]
    fn data_fora_do_calendario_vira_zero() {
        // Antes do ano -9999: o `Timestamp` não representa.
        let far = UNIX_EPOCH - Duration::from_secs(400_000_000_000);
        assert_eq!(offset_in(&TimeZone::UTC, far), 0);
    }
}
