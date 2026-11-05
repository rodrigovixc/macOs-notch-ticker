#!/bin/sh
# Cria, uma vez por Mac, um certificado de assinatura "StockNotch Local" no Keychain de início de sessão.
# Com a assinatura ad-hoc cada build é outro app para o Keychain, que volta a pedir a senha para ler a chave
# da Binance. Assinado sempre com o mesmo certificado, o "Sempre permitir" vale para as próximas versões.
# Serve só para assinar código: não é confiável para mais nada e não muda nenhum ajuste de segurança.
set -e
NOME="StockNotch Local"
if security find-certificate -c "$NOME" >/dev/null 2>&1; then
    echo "Já existe: $NOME"
    exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NOME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/chave.pem" -out "$TMP/cert.pem" 2>/dev/null
SENHA="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/chave.pem" -in "$TMP/cert.pem" -name "$NOME" \
    -out "$TMP/id.p12" -passout "pass:$SENHA"
# -T: o codesign usa a chave sem pedir senha a cada build.
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$SENHA" -T /usr/bin/codesign
echo "Criado: $NOME"
