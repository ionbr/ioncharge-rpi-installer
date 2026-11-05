#!/usr/bin/env bash
# ============================================================
# Ion Smart Edge — instalador de um comando para Raspberry Pi 5
#
# Uso (técnico da Ion, num Pi com internet):
#   curl -fsSL https://raw.githubusercontent.com/ionbr/ioncharge-rpi-installer/ion-smart-edge/install.sh | bash
#
# Etapas:
#   1. apt: curl, ca-certificates, python3 · Docker (get.docker.com)
#   2. Pede o token de preparação (Frota → Gerar token) e a chave do Tailscale
#   3. Baixa as imagens prontas da versão (GHCR privado; a credencial de
#      leitura vem da Smart Cloud pelo token e não fica no Pi)
#   4. Extrai o pacote do host de dentro da imagem (setup-host.sh, compose…)
#   5. sudo infra/pi/setup-host.sh (rede, HTTPS, firewall, hotspot, serial e licença)
#   6. scripts/bootstrap-edge-rpi.sh (.env e stack, sem build)
#   7. Pede o reboot
#
# L.1: o Pi não recebe código-fonte nem chave do GitHub. Um Pi instalado
# pela versão antiga (clone git) é convertido: o código e a deploy key são
# apagados; .env, senha do Mosquitto e o banco (volume Docker) ficam.
#
# Variáveis (todas opcionais):
#   IONSMART_VERSION           tag das imagens (default: ion-smart-edge; versão: 1.0.0-rc.1)
#   IONSMART_PROVISION_TOKEN   token de preparação (sem ele o instalador pergunta)
#   TS_AUTHKEY                 chave do Tailscale da Ion (sem ela pergunta; Enter pula)
#   INSTALL_DIR                default: $HOME/ion-smart-charge (o nome define o volume do banco — não troque num Pi já instalado)
#   HOSTNAME_NEW               hostname do Pi (default: ionsmart-<4 últimos do MAC>)
#   SYNC_CLOUD_URL             URL da Smart Cloud (default: https://smart.ioncharge.com.br)
# ============================================================
set -euo pipefail

VERSION="${IONSMART_VERSION:-ion-smart-edge}"
CLOUD_URL="${SYNC_CLOUD_URL:-https://smart.ioncharge.com.br}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/ion-smart-charge}"
OLD_DIR="${INSTALL_DIR}.antigo-git"
PREFIX="ghcr.io/ionbr/ion-smart-charge"
IMAGES=("$PREFIX/backend:$VERSION" "$PREFIX/frontend-edge:$VERSION")

# ---------- cores / logging ----------
if [ -t 1 ]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
  RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
else
  GREEN=''; YELLOW=''; BLUE=''; RED=''; BOLD=''; NC=''
fi
log()  { printf "${GREEN}✅ %s${NC}\n" "$*"; }
info() { printf "${BLUE}ℹ️  %s${NC}\n" "$*"; }
warn() { printf "${YELLOW}⚠️  %s${NC}\n" "$*"; }
err()  { printf "${RED}❌ %s${NC}\n" "$*" >&2; }
step() { printf "\n${BOLD}${BLUE}▶ %s${NC}\n" "$*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_sudo() {
  if [ "$EUID" -eq 0 ]; then
    err "Rode como o usuário do Pi (ex.: pi), não como root — o script pede sudo quando precisa."
    exit 1
  elif need_cmd sudo; then
    SUDO="sudo"
    sudo -v
  else
    err "Precisa de 'sudo' instalado."
    exit 1
  fi
}

detect_os() {
  if [ ! -f /etc/os-release ]; then
    err "Não consegui detectar o SO (/etc/os-release ausente)."
    exit 1
  fi
  # Em subshell: o os-release define VERSION ("13 (trixie)"), que sobrescreveria a versão do Ion Smart Edge
  local os
  # shellcheck disable=SC1091
  os="$(. /etc/os-release; printf '%s %s' "${ID:-?}" "${ID_LIKE:-}")"
  case "$os" in
    *debian*|*ubuntu*|*raspbian*) ;;
    *) warn "SO '${os%% *}' não é Debian/Raspberry Pi OS — pode falhar." ;;
  esac
}

install_prereqs() {
  step "Instalando pacotes base e Docker"
  $SUDO apt-get update -y
  $SUDO apt-get install -y curl ca-certificates python3
  if ! need_cmd docker; then curl -fsSL https://get.docker.com | $SUDO sh; fi
  $SUDO systemctl enable --now docker >/dev/null 2>&1 || true
  # o grupo docker fica com o bootstrap: ele sabe usar sudo enquanto o grupo não vale
}

ask() { # ask VAR "pergunta" — lê do terminal sem eco (stdin é o pipe do curl)
  if [ -z "${!1:-}" ] && [ -r /dev/tty ]; then
    printf "\n  %s " "$2" > /dev/tty
    read -rs "$1" < /dev/tty || true
    printf "\n" > /dev/tty
  fi
}

ask_tokens() {
  ask IONSMART_PROVISION_TOKEN "Token de preparação da Ion (Smart Cloud → Administração → Preparação de Pi):"
  if [ -z "${IONSMART_PROVISION_TOKEN:-}" ]; then
    err "Sem o token de preparação não dá para baixar a versão nem licenciar a placa."
    exit 1
  fi
  ask TS_AUTHKEY "Chave do Tailscale da Ion para o suporte remoto (Enter para pular):"
}

# Credencial de leitura do GHCR, entregue pela nuvem a cada uso e descartada
pull_images() {
  step "Baixando a versão $VERSION"
  local tok resp cfg
  tok="$(mktemp)"; resp="$(mktemp)"; cfg="$(mktemp -d)"
  chmod 600 "$tok"; printf 'x-api-key: %s\n' "$IONSMART_PROVISION_TOKEN" > "$tok"
  local code
  code="$(curl -sS -o "$resp" -w '%{http_code}' -X POST -H @"$tok" "$CLOUD_URL/api/edge/registry-credentials" || echo 000)"
  rm -f "$tok"
  if [ "$code" != 200 ]; then
    err "A nuvem recusou o token (HTTP $code): $(head -c 300 "$resp")"; rm -f "$resp"; exit 1
  fi
  python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1]))["data"]; print(d["username"]); print(d["password"])' "$resp" \
    | { read -r user; read -r pass; printf '%s' "$pass" | $SUDO env DOCKER_CONFIG="$cfg" docker login ghcr.io -u "$user" --password-stdin >/dev/null; }
  rm -f "$resp"
  local img ok=1
  for img in "${IMAGES[@]}"; do $SUDO env DOCKER_CONFIG="$cfg" docker pull -q "$img" >/dev/null || ok=0; done
  $SUDO env DOCKER_CONFIG="$cfg" docker logout ghcr.io >/dev/null 2>&1 || true
  $SUDO rm -rf "$cfg"
  [ "$ok" = 1 ] || { err "Falha ao baixar ${IMAGES[*]}"; exit 1; }
  log "Imagens baixadas"
}

# Pi da instalação antiga: tira o código e a chave do GitHub, guarda o que é do Pi
retire_git_install() {
  [ -d "$INSTALL_DIR/.git" ] || return 0
  step "Removendo o código-fonte e a chave do GitHub deste Pi (L.1)"
  [ -e "$OLD_DIR" ] && { err "$OLD_DIR já existe — uma conversão anterior não terminou. Confira e apague antes."; exit 1; }
  mv "$INSTALL_DIR" "$OLD_DIR"
  mkdir -p "$INSTALL_DIR/infra/mosquitto"
  cp -p "$OLD_DIR/.env" "$INSTALL_DIR/.env" 2>/dev/null || true
  cp -p "$OLD_DIR/infra/mosquitto/passwd" "$INSTALL_DIR/infra/mosquitto/passwd" 2>/dev/null || true
  # A deploy key e o alias SSH do GitHub
  rm -f "$HOME/.ssh/id_ion" "$HOME/.ssh/id_ion.pub"
  if [ -f "$HOME/.ssh/config" ]; then
    python3 -I - "$HOME/.ssh/config" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"\n?# IonCharge[^\n]*\nHost github-ion\n(?:[ \t]+[^\n]*\n?)*", "\n", s)
open(p, "w").write(s)
PY
  fi
  warn "Um admin Ion deve apagar a deploy key 'rpi-$(hostname)' em github.com/ionbr/ion-smart-charge/settings/keys"
}

extract_host_package() {
  step "Extraindo o pacote do host da versão $VERSION"
  mkdir -p "$INSTALL_DIR"
  local cid
  cid="$($SUDO docker create "${IMAGES[0]}")"
  $SUDO docker cp "$cid:/app/host/." "$INSTALL_DIR/"
  $SUDO docker rm "$cid" >/dev/null
  mkdir -p "$INSTALL_DIR/web"  # o compose cita ./web no build (só usado em dev); sem compilar, basta existir
  $SUDO chown -R "$USER:" "$INSTALL_DIR"
}

# rede, HTTPS (certificado), watchdog, firewall, hotspot, serial e licença
setup_host() {
  export TS_AUTHKEY="${TS_AUTHKEY:-}" IONSMART_PROVISION_TOKEN IONSMART_CLOUD_URL="$CLOUD_URL"
  step "Preparando o sistema do Pi (setup-host.sh)"
  # --preserve-env: as chaves chegam ao script sem aparecer na lista de processos
  local args=()
  [ -n "${HOSTNAME_NEW:-}" ] && args=(--hostname "$HOSTNAME_NEW")
  $SUDO --preserve-env=TS_AUTHKEY,IONSMART_PROVISION_TOKEN,IONSMART_CLOUD_URL bash "$INSTALL_DIR/infra/pi/setup-host.sh" "${args[@]}"
}

run_bootstrap() {
  # As imagens oficiais exigem licença: sem ela a stack nova não controlaria os
  # carregadores. Para antes de trocar a stack — a que está rodando continua.
  if ! $SUDO test -s /etc/ionsmart/license/license.json; then
    err "A placa ficou sem licença (veja o aviso do setup-host.sh acima). Nada foi trocado na stack em execução."
    err "Corrija (token válido, nuvem com EDGE_LICENSE_PRIVATE_KEY) e rode o instalador de novo."
    exit 1
  fi
  # setup-host.sh pode ter movido o Docker para o NVMe: as imagens ficaram para trás
  $SUDO docker image inspect "${IMAGES[@]}" >/dev/null 2>&1 || pull_images
  step "Subindo a plataforma (bootstrap-edge-rpi.sh)"
  IONSMART_IMAGE_TAG="$VERSION" INSTALL_DIR="$INSTALL_DIR" SYNC_CLOUD_URL="$CLOUD_URL" bash "$INSTALL_DIR/scripts/bootstrap-edge-rpi.sh"
  # Imagens compiladas no Pi pela instalação antiga e o cache do build guardam o
  # código-fonte: só ficam as imagens em uso pela stack que acabou de subir
  $SUDO docker builder prune -af >/dev/null 2>&1 || true
  $SUDO docker image prune -af >/dev/null 2>&1 || true
  if [ -d "$OLD_DIR" ]; then
    rm -rf "$OLD_DIR"
    log "Código antigo apagado"
  fi
}

ask_reboot() {
  echo
  printf "${BOLD}${YELLOW}══════════════════════════════════════════════════════════${NC}\n"
  printf "${BOLD}${YELLOW}  🔁 REINÍCIO NECESSÁRIO${NC}\n"
  printf "${BOLD}${YELLOW}══════════════════════════════════════════════════════════${NC}\n"
  echo "  Rede, hotspot de configuração e watchdog passam a valer depois do reinício."
  echo "  Depois dele, o painel fica em https://$(hostname).local"
  echo
  if [ -r /dev/tty ]; then
    local answer=""
    printf "  Reiniciar agora? [S/n] " > /dev/tty
    read -r answer < /dev/tty || true
    case "${answer:-S}" in
      [nN]*) warn "Reinicie quando puder: sudo reboot" ;;
      *) log "Reiniciando…"; $SUDO reboot ;;
    esac
  else
    warn "Reinicie o Pi para concluir: sudo reboot"
  fi
}

# Pis instalados pela versão antiga guardaram o token pessoal do técnico.
remove_old_gh_token() {
  if need_cmd gh && gh auth status >/dev/null 2>&1; then
    step "Removendo o login do GitHub deixado pelo instalador antigo"
    gh auth logout --hostname github.com </dev/null >/dev/null 2>&1 || warn "Rode 'gh auth logout' manualmente"
  fi
}

main() {
  printf "${BOLD}${BLUE}Ion Smart Edge — Instalador Raspberry Pi${NC}\n"
  ensure_sudo
  detect_os
  install_prereqs
  ask_tokens
  pull_images
  retire_git_install
  extract_host_package
  setup_host
  run_bootstrap
  unset IONSMART_PROVISION_TOKEN TS_AUTHKEY
  remove_old_gh_token
  ask_reboot
}

main "$@"
