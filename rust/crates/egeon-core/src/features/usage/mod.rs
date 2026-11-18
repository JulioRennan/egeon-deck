//! Consumo e custo (ADR-085): tokens por tarifa, preço congelado no momento em
//! que o gasto entra, registro por bancada em `usage.json`.

pub mod ledger;
pub mod model;
pub mod panel;
pub mod prices;
pub mod routes;
pub mod store;
pub mod text;
pub mod trace;

pub use ledger::{Cursor, UsageLedger};
pub use model::{
    ModelPrice, Spend, TariffCost, TokenUsage, UsageByPrice, UsageEntry, add_entry, merge_usage,
    settled, total_usage,
};
pub use prices::{Origin, PriceTable};

#[cfg(test)]
mod tests;
