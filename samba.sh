#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "========================================"
echo " SegIn Web - configurar Samba/SMB Linux"
echo "========================================"
echo

if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "ERRO: execute como root ou instale/configure sudo."
    exit 1
  fi
else
  SUDO=""
fi

read -r -p "Nome do share [segin]: " SHARE_NAME
SHARE_NAME="${SHARE_NAME:-segin}"

if ! [[ "$SHARE_NAME" =~ ^[A-Za-z0-9_.\-$]+$ ]]; then
  echo "ERRO: nome de share invalido. Use letras, numeros, _, ., - ou $."
  exit 1
fi

read -r -p "Diretorio compartilhado [/srv/samba/segin]: " SHARE_PATH
SHARE_PATH="${SHARE_PATH:-/srv/samba/segin}"

case "$SHARE_PATH" in
  *";"*|*"&&"*|*"||"*|*"\`"*|*'$('*|*$'\n'*|*$'\r'*)
    echo "ERRO: caminho contem caracteres nao permitidos."
    exit 1
    ;;
esac

read -r -p "Usuario Samba [segin_smb]: " SMB_USER
SMB_USER="${SMB_USER:-segin_smb}"

if ! [[ "$SMB_USER" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]]; then
  echo "ERRO: usuario invalido."
  exit 1
fi

while true; do
  read -r -s -p "Senha Samba (minimo 6 caracteres): " SMB_PASSWORD
  echo
  if [ "${#SMB_PASSWORD}" -ge 6 ]; then
    break
  fi
  echo "A senha precisa ter pelo menos 6 caracteres."
done

echo
echo "Verificando instalacao do Samba..."
if ! command -v smbd >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update
    $SUDO apt-get install -y samba smbclient
  elif command -v dnf >/dev/null 2>&1; then
    $SUDO dnf install -y samba samba-client
  elif command -v yum >/dev/null 2>&1; then
    $SUDO yum install -y samba samba-client
  elif command -v pacman >/dev/null 2>&1; then
    $SUDO pacman -Sy --needed samba smbclient
  else
    echo "ERRO: nao consegui instalar automaticamente. Instale samba e smbclient manualmente."
    exit 1
  fi
else
  echo "Samba ja instalado."
fi

SMB_CONF="/etc/samba/smb.conf"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

echo
echo "Criando diretorio do share..."
$SUDO mkdir -p "$SHARE_PATH"

if ! id "$SMB_USER" >/dev/null 2>&1; then
  echo "Criando usuario local sem login: $SMB_USER"
  $SUDO useradd --system --no-create-home --shell /usr/sbin/nologin "$SMB_USER" 2>/dev/null || \
    $SUDO useradd --system --no-create-home --shell /bin/false "$SMB_USER"
fi

$SUDO chown -R "$SMB_USER":"$SMB_USER" "$SHARE_PATH"
$SUDO chmod 0770 "$SHARE_PATH"

echo "Definindo senha Samba..."
printf '%s\n%s\n' "$SMB_PASSWORD" "$SMB_PASSWORD" | $SUDO smbpasswd -a -s "$SMB_USER"
$SUDO smbpasswd -e "$SMB_USER" >/dev/null

echo "Atualizando $SMB_CONF..."
$SUDO cp "$SMB_CONF" "$SMB_CONF.bak.$TIMESTAMP"

TMP_CONF="$(mktemp)"
$SUDO awk -v share="[$SHARE_NAME]" '
  BEGIN { skip=0 }
  /^\[/ {
    skip=($0 == share)
  }
  skip == 0 { print }
' "$SMB_CONF" > "$TMP_CONF"

cat >> "$TMP_CONF" <<EOF

[$SHARE_NAME]
   path = $SHARE_PATH
   browseable = yes
   read only = no
   guest ok = no
   valid users = $SMB_USER
   force user = $SMB_USER
   create mask = 0660
   directory mask = 0770
   comment = Share usado pelo SegIn
EOF

$SUDO cp "$TMP_CONF" "$SMB_CONF"
rm -f "$TMP_CONF"

echo "Validando configuracao Samba..."
$SUDO testparm -s >/dev/null

echo "Reiniciando Samba..."
if command -v systemctl >/dev/null 2>&1; then
  $SUDO systemctl enable --now smbd 2>/dev/null || true
  $SUDO systemctl restart smbd 2>/dev/null || $SUDO systemctl restart samba 2>/dev/null || true
  $SUDO systemctl restart nmbd 2>/dev/null || true
else
  $SUDO service smbd restart 2>/dev/null || $SUDO service samba restart 2>/dev/null || true
fi

HOST_NAME="$(hostname -I 2>/dev/null | awk '{print $1}')"
HOST_NAME="${HOST_NAME:-localhost}"

echo
read -r -p "Atualizar .env do SegIn com esse Samba? [S/n]: " UPDATE_ENV
UPDATE_ENV="${UPDATE_ENV:-S}"
if [[ "$UPDATE_ENV" =~ ^[SsYy]$ ]]; then
  if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
      cp .env.example .env
    else
      touch .env
    fi
    chmod 600 .env 2>/dev/null || true
  fi

  SAMBA_HOST_VALUE="$HOST_NAME" \
  SAMBA_USERNAME_VALUE="$SMB_USER" \
  SAMBA_PASSWORD_VALUE="$SMB_PASSWORD" \
  node -e "const fs=require('fs'); const path='.env'; const patch={SAMBA_HOST:process.env.SAMBA_HOST_VALUE,SAMBA_USERNAME:process.env.SAMBA_USERNAME_VALUE,SAMBA_PASSWORD:process.env.SAMBA_PASSWORD_VALUE,SAMBA_WORKGROUP:''}; const lines=fs.existsSync(path)?fs.readFileSync(path,'utf8').split(/\r?\n/):[]; const seen=new Set(); const out=lines.map(line=>{const m=line.match(/^([A-Z0-9_]+)=/); if(!m||!(m[1] in patch)) return line; seen.add(m[1]); return m[1]+'='+String(patch[m[1]]).replace(/\r?\n/g,'');}); for(const [k,v] of Object.entries(patch)){ if(!seen.has(k)) out.push(k+'='+String(v).replace(/\r?\n/g,'')); } fs.writeFileSync(path,out.join('\n').replace(/\n*$/,'\n'));"
  echo ".env atualizado."
fi

echo
echo "Samba configurado."
echo "Host: $HOST_NAME"
echo "Share: $SHARE_NAME"
echo "Caminho: $SHARE_PATH"
echo "Usuario: $SMB_USER"
echo
echo "Teste manual:"
echo "smbclient //$HOST_NAME/$SHARE_NAME -U $SMB_USER"
