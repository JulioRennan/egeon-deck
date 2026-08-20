#!/usr/bin/env bash
# Cria o certificado local que dá identidade ESTÁVEL ao app.
#
#   ./cert.sh
#
# Assinatura ad-hoc — o padrão sem certificado — gera identidade de código nova a
# cada build, porque a identidade ali é o hash do binário. O TCC guarda permissão
# por identidade, então todo `dev.sh` vira, para o macOS, um app nunca visto:
# Documentos, Mesa, Transferências e microfone pedidos outra vez. No microfone não é
# nem diálogo — o processo é abortado pelo sistema (ADR-027).
#
# O certificado é autoassinado e local. Serve para uma coisa só: manter a mesma
# identidade entre builds. Não é notarização, não muda distribuição, e não sai desta
# máquina — a chave privada fica no keychain de login.
#
# Depois de rodar isto, o `make.sh` acha o certificado pelo nome e assina com ele
# sem precisar de `export`. `EG_SIGN_ID` continua tendo precedência, para outro nome.
set -euo pipefail

NOME="egeon-dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

existe() { security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$NOME\""; }

if existe; then
  echo "já existe uma identidade de assinatura de código chamada \"$NOME\":"
  security find-identity -v -p codesigning | grep "\"$NOME\""
  echo
  echo "nada a fazer — o make.sh já usa ela."
  exit 0
fi

D=$(mktemp -d)
# A chave privada não pode sobreviver ao script: depois do import ela vive no
# keychain, e uma cópia solta em disco é cópia solta de identidade de assinatura.
trap 'rm -rf "$D"' EXIT

# Extensões por arquivo de config, e não por `-addext`: o `openssl` do sistema é
# LibreSSL, que não tem essa flag. `extendedKeyUsage=codeSigning` é o que faz o
# `find-identity -p codesigning` reconhecer a identidade — sem ela o certificado
# nasce inútil para este fim.
cat > "$D/cert.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = $NOME
[ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

echo "gerando o certificado…"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$D/$NOME.key" -out "$D/$NOME.crt" \
  -config "$D/cert.cnf" -extensions ext 2>/dev/null

# `security import` engasga com o `.p12` que o OpenSSL 3 escreve por padrão (AES +
# PBKDF2). As PBE antigas são feias e são as que ele lê; se a versão local não
# aceitar as flags, tenta sem elas.
openssl pkcs12 -export -inkey "$D/$NOME.key" -in "$D/$NOME.crt" \
  -out "$D/$NOME.p12" -passout pass: \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null \
  || openssl pkcs12 -export -inkey "$D/$NOME.key" -in "$D/$NOME.crt" \
       -out "$D/$NOME.p12" -passout pass:

# `-T /usr/bin/codesign` põe o codesign na lista de quem pode usar a chave. Sem
# isso, todo build para num diálogo do keychain.
echo "importando no keychain de login…"
security import "$D/$NOME.p12" -k "$KEYCHAIN" -P "" -T /usr/bin/codesign

if ! existe; then
  echo "erro: importou mas a identidade não aparece em find-identity -p codesigning." >&2
  echo "      confira o certificado no Acesso às Chaves — ele precisa ser do tipo" >&2
  echo "      'Assinatura de código'." >&2
  exit 1
fi

echo
security find-identity -v -p codesigning | grep "\"$NOME\""
echo
echo "pronto. Agora:"
echo "  ./dev.sh          # deve dizer 'assinado com: $NOME'"
echo
echo "Dois avisos, uma vez cada:"
echo "  · o primeiro codesign abre uma janela do keychain — Sempre Permitir;"
echo "  · o primeiro build ainda pede as permissões do macOS, porque a identidade"
echo "    é nova. Do segundo em diante, para."
