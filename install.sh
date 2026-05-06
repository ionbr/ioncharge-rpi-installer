#!/usr/bin/env bash
# ============================================================
# IonCharge Edge — One-liner installer para Raspberry Pi
#
# Uso (técnico em campo, num Pi com internet):
#   curl -fsSL https://raw.githubusercontent.com/ionbr/ioncharge-rpi-installer/main/install.sh | bash
#
# Etapas:
#   1. apt: git, curl, ca-certificates, openssh-client
#   2. Instala gh CLI (repo oficial GitHub)
#   3. gh auth login (device-code flow) — 1× por Pi
#   4. Clona o repo privado ionbr/ion-smart-charge
#   5. Delega para scripts/bootstrap-edge-rpi.sh, que instala Docker,
#      gera deploy key SSH dedicada, builda a imagem edge e sobe.
#
# Não contém segredos. Não tem código do produto. É só um wrapper.
#
# Variáveis (todas opcionais, repassadas para o bootstrap):
#   INSTALL_DIR        destino do clone (default: $HOME/ion-smart-charge)
#   BRANCH             branch do repo privado (default: main)
#   EDGE_SITE_ID       id do site (default: vazio = standalone)
#   EDGE_DEVICE_ID     id do dispositivo (default: rpi-<hostname>)
#   SYNC_CLOUD_URL     URL da cloud para sync
#   SYNC_EDGE_API_KEY  API key de sync
#   (demais: ver scripts/bootstrap-edge-rpi.sh no repo principal)
# ============================================================
set -euo pipefail

REPO="ionbr/ion-smart-charge"
BRANCH="${BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/ion-smart-charge}"

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
    SUDO=""
  elif need_cmd sudo; then
    SUDO="sudo"
    sudo -v
  else
    err "Precisa de privilégios root (instale 'sudo' ou rode como root)."
    exit 1
  fi
}

detect_os() {
  if [ ! -f /etc/os-release ]; then
    err "Não consegui detectar o SO (/etc/os-release ausente)."
    exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}${ID_LIKE:-}" in
    *debian*|*ubuntu*|*raspbian*) ;;
    *) warn "SO '${ID:-?}' não é Debian/Ubuntu/Raspbian — pode falhar." ;;
  esac
}

install_apt_prereqs() {
  step "Instalando pacotes base (git, curl, ca-certificates, openssh-client)"
  $SUDO apt-get update -y
  $SUDO apt-get install -y git curl ca-certificates openssh-client gnupg
}

install_gh() {
  if need_cmd gh; then
    info "gh CLI já instalado: $(gh --version | head -1)"
    return
  fi
  step "Instalando gh CLI (GitHub CLI)"
  local keyring=/usr/share/keyrings/githubcli-archive-keyring.gpg
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | $SUDO tee "$keyring" >/dev/null
  $SUDO chmod go+r "$keyring"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=$keyring] https://cli.github.com/packages stable main" \
    | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  $SUDO apt-get update -y
  $SUDO apt-get install -y gh
  log "gh CLI instalado: $(gh --version | head -1)"
}

ensure_gh_auth() {
  if gh auth status >/dev/null 2>&1; then
    info "gh já autenticado como: $(gh api user --jq .login)"
    return
  fi
  step "Autenticando no GitHub"
  echo
  echo "  ${BOLD}Vai aparecer um código de 8 caracteres + uma URL${NC}"
  echo "  ${BOLD}Abra a URL no celular ou outro computador, cole o código e autorize.${NC}"
  echo
  gh auth login --hostname github.com --git-protocol https --web
}

clone_main_repo() {
  if [ -d "$INSTALL_DIR/.git" ]; then
    info "Repo já clonado em $INSTALL_DIR"
    return
  fi
  if [ -e "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null || true)" ]; then
    err "$INSTALL_DIR existe e não está vazio. Remova ou aponte INSTALL_DIR para outro caminho."
    exit 1
  fi
  step "Clonando $REPO (branch $BRANCH) → $INSTALL_DIR"
  gh repo clone "$REPO" "$INSTALL_DIR" -- --branch "$BRANCH"
}

run_bootstrap() {
  local bootstrap="$INSTALL_DIR/scripts/bootstrap-edge-rpi.sh"
  if [ ! -f "$bootstrap" ]; then
    err "Script $bootstrap não encontrado. Estrutura do repo pode ter mudado."
    exit 1
  fi
  step "Delegando para bootstrap-edge-rpi.sh"
  exec bash "$bootstrap"
}

main() {
  printf "${BOLD}${BLUE}IonCharge Edge — Installer Raspberry Pi${NC}\n"
  ensure_sudo
  detect_os
  install_apt_prereqs
  install_gh
  ensure_gh_auth
  clone_main_repo
  run_bootstrap
}

main "$@"
