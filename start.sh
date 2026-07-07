#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_URL="http://localhost:3000"

echo "========================================"
echo " SegIn Web - primeira execucao"
echo "========================================"
echo

if ! command -v node >/dev/null 2>&1; then
  echo "ERRO: Node.js nao encontrado. Instale Node.js 20 LTS ou superior antes de continuar."
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "ERRO: npm nao encontrado. Instale o npm antes de continuar."
  exit 1
fi

NODE_MAJOR="$(node -p "Number(process.versions.node.split('.')[0])")"
if [ "$NODE_MAJOR" -lt 20 ] || [ "$NODE_MAJOR" -ge 26 ]; then
  echo "AVISO: Node atual: $(node -v). Recomendado: Node 20 LTS ate Node 25."
  echo "O sqlite3 pode falhar em versoes muito novas. Se falhar, use Node 20 LTS."
  echo
fi

if [ ! -f ".env" ]; then
  echo "Criando .env..."
  SESSION_SECRET="$(node -p "require('crypto').randomBytes(32).toString('hex')")"
  cat > .env <<EOF
NODE_ENV=development
PORT=3000
SESSION_SECRET=$SESSION_SECRET
SEGIN_DB_URL=sqlite:./data/segin.sqlite3

NETBOX_URL=
NETBOX_TOKEN=
NETBOX_TOKEN_SCHEME=auto

SAMBA_HOST=
SAMBA_USERNAME=
SAMBA_PASSWORD=
SAMBA_WORKGROUP=
EOF
  chmod 600 .env 2>/dev/null || true
  echo ".env criado com permissao restrita."
else
  echo ".env ja existe; mantendo configuracao atual."
fi

echo
echo "Instalando dependencias..."
npm install

echo
echo "Inicializando banco..."
npm run init-db

echo
echo "Criacao do usuario administrador"
read -r -p "Usuario admin [admin]: " ADMIN_USER
ADMIN_USER="${ADMIN_USER:-admin}"

read -r -p "Email admin [admin@local]: " ADMIN_EMAIL
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@local}"

while true; do
  read -r -s -p "Senha admin (minimo 6 caracteres): " ADMIN_PASSWORD
  echo
  if [ "${#ADMIN_PASSWORD}" -ge 6 ]; then
    break
  fi
  echo "A senha precisa ter pelo menos 6 caracteres."
done

SEGIN_ADMIN_PASSWORD="$ADMIN_PASSWORD" node src/cli.js create-admin --username "$ADMIN_USER" --email "$ADMIN_EMAIL"

echo
echo "Tudo pronto."
echo "Acesse: $APP_URL"
echo "Login: $ADMIN_USER"
echo
echo "Iniciando servidor..."
npm start
