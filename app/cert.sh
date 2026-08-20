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

# Senha aleatória, e NÃO vazia. Com `.p12` sem senha o `security import` do macOS
# morre em "MAC verification failed during PKCS12 import (wrong password?)":
# Apple e OpenSSL discordam do que "sem senha" significa no cálculo do MAC do
# PKCS#12 — um usa a string vazia, o outro a ausência de senha. A senha existe por
# três linhas e morre com o processo; quem guarda a chave depois é o keychain.
SENHA=$(openssl rand -hex 16)

# `security import` também engasga com o que o OpenSSL 3 escreve por padrão (AES +
# PBKDF2). As PBE antigas são feias e são as que ele lê.
empacotar() {
  openssl pkcs12 -export -inkey "$D/$NOME.key" -in "$D/$NOME.crt" \
    -out "$D/$NOME.p12" -passout "pass:$SENHA" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 "$@" 2>/dev/null
}

# `-T /usr/bin/codesign` põe o codesign na lista de quem pode usar a chave. Sem
# isso, todo build para num diálogo do keychain.
importar() {
  security import "$D/$NOME.p12" -k "$KEYCHAIN" -P "$SENHA" -T /usr/bin/codesign
}

echo "importando no keychain de login…"
if ! { empacotar && importar; }; then
  # Provedor legado: em algumas combinações de versão as PBE antigas não estão no
  # provedor padrão, e o `.p12` sai com algoritmo que o Keychain não lê.
  echo "primeira tentativa falhou — refazendo o .p12 pelo provedor legado…"
  empacotar -legacy && importar
fi

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
