#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

SEGIN_URL="http://localhost:${SEGIN_PORT:-3000}"
NETBOX_URL="http://localhost:${NETBOX_PORT:-18080}"
NETBOX_TOKEN="nbt_seginweb0001.0123456789abcdef0123456789abcdef01234567"

info() {
  printf '\n%s\n' "$1"
}

fail() {
  printf '\nERRO: %s\n' "$1" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

wait_for_http() {
  local name="$1"
  local url="$2"
  local max_seconds="$3"
  local header="${4:-}"
  local elapsed=0

  printf "Aguardando %s responder em %s" "$name" "$url"
  while [ "$elapsed" -lt "$max_seconds" ]; do
    if [ -n "$header" ]; then
      if curl -fsS -H "$header" "$url" >/dev/null 2>&1; then
        printf "\n%s pronto.\n" "$name"
        return 0
      fi
    else
      if curl -fsS "$url" >/dev/null 2>&1; then
        printf "\n%s pronto.\n" "$name"
        return 0
      fi
    fi

    sleep 10
    elapsed=$((elapsed + 10))
    printf "."
  done

  printf "\n"
  return 1
}

echo "========================================"
echo " SegIn Web - init Docker"
echo "========================================"

have docker || fail "Docker nao encontrado. Instale Docker Desktop ou Docker Engine e rode este script novamente."
docker compose version >/dev/null 2>&1 || fail "Docker Compose nao encontrado. Instale/atualize o Docker com suporte a 'docker compose'."

if [ ! -f ".env" ]; then
  if [ -f ".env.example" ]; then
    info "Criando .env a partir do .env.example..."
    cp .env.example .env
    chmod 600 .env 2>/dev/null || true
  else
    fail ".env.example nao encontrado."
  fi
else
  info ".env ja existe; mantendo configuracao atual."
fi

info "Construindo imagens e iniciando containers..."
docker compose up --build -d

info "Status dos containers:"
docker compose ps

if ! have curl; then
  info "curl nao encontrado; pulando espera automatica."
  echo "Acesse o SegIn quando estiver pronto: $SEGIN_URL"
  echo "NetBox: $NETBOX_URL"
  exit 0
fi

info "Primeiro boot do NetBox pode demorar varios minutos por causa das migracoes."
wait_for_http "SegIn" "$SEGIN_URL" 300 || fail "SegIn nao respondeu a tempo. Veja os logs com: docker compose logs segin"
wait_for_http "NetBox API" "$NETBOX_URL/api/dcim/devices/" 1800 "Authorization: Bearer $NETBOX_TOKEN" || {
  echo "NetBox ainda nao respondeu com o token esperado."
  echo "Veja os logs com: docker compose logs netbox"
  echo "Se for uma base antiga quebrada de teste, use: docker compose down -v"
  exit 1
}

info "Tudo pronto."
echo "SegIn:  $SEGIN_URL"
echo "NetBox: $NETBOX_URL"
echo "Login SegIn: admin / admin123"
echo "Login NetBox: admin / admin123"
