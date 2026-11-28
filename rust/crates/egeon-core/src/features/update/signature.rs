//! A prova de que o zip saiu da máquina que faz as releases.
//!
//! Sem assinatura da Apple, nada mais diz de onde o zip veio, e o atualizador
//! executa o que baixa: uma conta do GitHub invadida viraria código rodando em
//! toda máquina. A chave privada fica no Keychain de quem publica
//! (`tools/release-key.swift`), nunca no repositório nem no GitHub.

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};

/// A chave pública Ed25519 das releases, em base64.
pub const PUBLIC_KEY: &str = "VnRyK5/qnhQEzUb0yD0lEN+If86U8P8cu43jynviXaU=";

/// `signature_b64` é o texto do `.sig`, com ou sem a quebra de linha do fim.
pub fn is_valid(zip: &[u8], signature_b64: &str, public_key_b64: &str) -> bool {
    let check = || -> Option<bool> {
        let key: [u8; 32] = STANDARD.decode(public_key_b64).ok()?.try_into().ok()?;
        let key = VerifyingKey::from_bytes(&key).ok()?;
        let raw: [u8; 64] = STANDARD
            .decode(signature_b64.trim())
            .ok()?
            .try_into()
            .ok()?;
        Some(key.verify(zip, &Signature::from_bytes(&raw)).is_ok())
    };
    check().unwrap_or(false)
}
