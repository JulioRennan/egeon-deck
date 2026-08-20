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
#
# São TRÊS passos, e o terceiro é o que costuma faltar: gerar, importar e **marcar
# como confiável para assinatura de código**. Sem confiança o certificado está no
# keychain e o `find-identity -v -p codesigning` não o mostra — `-v` lista só
# identidade válida, e autoassinado sem confiança não é válido.
#
#   ./cert.sh --refazer     apaga a identidade que existir e cria outra
#
# O padrão NÃO apaga nada: identidade que já está no keychain só ganha a confiança
# que falta. Refazer troca a identidade de código, e trocar identidade custa uma
# rodada de permissões do macOS — então é escolha explícita.
set -euo pipefail

NOME="egeon-dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
REFAZER=0
case "${1:-}" in
  --refazer) REFAZER=1 ;;
  "")        ;;
  *)         echo "uso: ./cert.sh [--refazer]" >&2; exit 1 ;;
esac

# Duas perguntas diferentes, e a diferença é o assunto deste script: `-v` filtra
# por validade, sem `-v` lista o que existe. Identidade que existe e não é válida é
# exatamente o estado "importei e o codesign não acha".
identidade_valida() { security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$NOME\""; }
identidade_existe() { security find-identity    -p codesigning 2>/dev/null | grep -q "\"$NOME\""; }

D=$(mktemp -d)
# A chave privada não pode sobreviver ao script: depois do import ela vive no
# keychain, e uma cópia solta em disco é cópia solta de identidade de assinatura.
trap 'rm -rf "$D"' EXIT

confiar() {
  echo "marcando \"$NOME\" como confiável para assinatura de código…"
  echo "  (o macOS vai pedir sua senha — é a mesma janela do Acesso às Chaves)"
  # `-p codeSign` restringe a confiança a assinatura de código: este certificado
  # não tem por que valer para TLS nem para nada mais. Sem `-d`, fica no domínio do
  # usuário e não precisa de sudo.
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$1"
}

if [ "$REFAZER" = 1 ] && identidade_existe; then
  # Uma por chamada, e mais de uma pode existir: uma tentativa que importou sem
  # confiar, repetida, deixa homônimos — e aí `codesign --sign "$NOME"` falha por
  # ambiguidade em vez de assinar. O teto é para não virar laço infinito se o
  # delete não pegar.
  for _ in 1 2 3 4 5; do
    identidade_existe || break
    echo "apagando a identidade \"$NOME\" que estava no keychain…"
    security delete-identity -c "$NOME" "$KEYCHAIN" >/dev/null || break
  done
  if identidade_existe; then
    echo "erro: não consegui apagar \"$NOME\" — apague no Acesso às Chaves e rode de novo." >&2
    exit 1
  fi
fi

if identidade_valida; then
  echo "já existe uma identidade de assinatura de código chamada \"$NOME\", válida:"
  security find-identity -v -p codesigning | grep "\"$NOME\""
  echo
  echo "nada a fazer — o make.sh já usa ela."
  exit 0
fi

if identidade_existe; then
  # Estado da execução anterior: importou e paramos antes de confiar. Gerar outro
  # aqui daria dois certificados com o mesmo nome, e `codesign --sign "$NOME"`
  # passaria a falhar por ambiguidade.
  echo "a identidade \"$NOME\" já está no keychain, mas sem confiança para"
  echo "assinatura de código — é só isso que falta."
  security find-certificate -c "$NOME" -p > "$D/$NOME.crt"
  confiar "$D/$NOME.crt"
else
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

  # Senha aleatória, e NÃO vazia. Com `.p12` sem senha o `security import` morre em
  # "MAC verification failed during PKCS12 import (wrong password?)": Apple e
  # OpenSSL discordam do que "sem senha" significa no cálculo do MAC do PKCS#12 —
  # um usa a string vazia, o outro a ausência de senha. A senha existe por três
  # linhas e morre com o processo; quem guarda a chave depois é o keychain.
  SENHA=$(openssl rand -hex 16)

  # `security import` também engasga com o que o OpenSSL 3 escreve por padrão (AES
  # + PBKDF2). As PBE antigas são feias e são as que ele lê.
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

  confiar "$D/$NOME.crt"
fi

if ! identidade_valida; then
  echo >&2
  echo "erro: a identidade \"$NOME\" ainda não aparece como válida." >&2
  if identidade_existe; then
    echo "      Ela ESTÁ no keychain — o que falta é a confiança. Faça à mão:" >&2
    echo "      Acesso às Chaves › login › Meus certificados › $NOME ›" >&2
    echo "      Confiar › 'Ao usar este certificado: Sempre Confiar'" >&2
    echo "      (ou pelo menos 'Assinatura de código: Sempre Confiar')." >&2
  else
    echo "      O import não deixou nada no keychain. Confira o Acesso às Chaves." >&2
  fi
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
