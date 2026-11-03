#!/usr/bin/env bash
# ============================================================
# Ion Smart Edge — instalador de um comando para Raspberry Pi 5
#
# Uso (técnico em campo, num Pi com internet):
#   curl -fsSL https://raw.githubusercontent.com/ionbr/ioncharge-rpi-installer/ion-smart-edge/install.sh | bash
#
# Etapas:
#   1. apt: git, curl, ca-certificates, openssh-client
#   2. Chave de leitura do Pi (deploy key) — um admin Ion cadastra no repo
#   3. Clona o repo privado ionbr/ion-smart-charge por SSH com essa chave
#   4. sudo infra/pi/setup-host.sh (rede, HTTPS, watchdog, firewall, hotspot)
#   5. scripts/bootstrap-edge-rpi.sh (Docker, .env, build e stack)
#   6. Pede o reboot (rede, watchdog e hotspot valem a partir dele)
#
# Nenhuma conta ou token pessoal do GitHub fica no Pi: só a chave de
# leitura dele (I.5). Não contém segredos nem código do produto.
#
# Variáveis (todas opcionais, repassadas para o bootstrap):
#   INSTALL_DIR    destino do clone (default: $HOME/ion-smart-charge)
#   BRANCH         branch do repo privado (default: ion-smart-edge)
#   HOSTNAME_NEW   hostname do Pi (default: ionsmart-<4 últimos do MAC>)
#   SYNC_CLOUD_URL URL da Smart Cloud
#   (demais: ver scripts/bootstrap-edge-rpi.sh no repo principal)
# ============================================================
set -euo pipefail

REPO_OWNER="ionbr"
REPO_NAME="ion-smart-charge"
BRANCH="${BRANCH:-ion-smart-edge}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/ion-smart-charge}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ion}"   # mesma chave/alias do bootstrap
REPO_URL_SSH="git@github-ion:${REPO_OWNER}/${REPO_NAME}.git"

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
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}${ID_LIKE:-}" in
    *debian*|*ubuntu*|*raspbian*) ;;
    *) warn "SO '${ID:-?}' não é Debian/Raspberry Pi OS — pode falhar." ;;
  esac
}

install_apt_prereqs() {
  step "Instalando pacotes base (git, curl, ca-certificates, openssh-client)"
  $SUDO apt-get update -y
  $SUDO apt-get install -y git curl ca-certificates openssh-client
}

test_repo_access() {
  GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new" \
    git ls-remote "$REPO_URL_SSH" HEAD >/dev/null 2>&1
}

# Nome do Pi como o setup-host.sh vai deixá-lo (ionsmart-<MAC>): a chave
# é gerada antes da troca de hostname e precisa de um nome único no GitHub.
pi_name() {
  if [ -n "${HOSTNAME_NEW:-}" ]; then echo "$HOSTNAME_NEW"; return; fi
  if [ "$(hostname)" != raspberrypi ]; then hostname; return; fi
  local suffix
  suffix="$(tr -d ':\n' < "/sys/class/net/${IONSMART_ETH:-eth0}/address" 2>/dev/null | tail -c 4)"
  echo "ionsmart-${suffix:-0000}"
}

# Chave de leitura do Pi. O bootstrap reconhece a mesma chave e o mesmo
# alias 'github-ion' e não pede de novo.
setup_deploy_key() {
  step "Chave de acesso do Pi ao código (somente leitura)"
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  [ -f "$SSH_KEY_PATH" ] || ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "ioncharge-rpi-$(pi_name)" -q
  chmod 600 "$SSH_KEY_PATH"

  touch "$HOME/.ssh/known_hosts" && chmod 600 "$HOME/.ssh/known_hosts"
  ssh-keygen -F github.com -f "$HOME/.ssh/known_hosts" >/dev/null 2>&1 \
    || ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null

  local config="$HOME/.ssh/config"
  touch "$config" && chmod 600 "$config"
  if ! grep -q '^Host github-ion$' "$config"; then
    printf '\n# IonCharge — chave de leitura do repo (install.sh)\nHost github-ion\n  HostName github.com\n  User git\n  IdentityFile %s\n  IdentitiesOnly yes\n' \
      "$SSH_KEY_PATH" >> "$config"
  fi

  if test_repo_access; then
    log "Chave já cadastrada"
    return
  fi

  echo
  printf "${BOLD}${YELLOW}══════════════════════════════════════════════════════════${NC}\n"
  printf "${BOLD}${YELLOW}  📋 AÇÃO NECESSÁRIA — um admin Ion cadastra esta chave${NC}\n"
  printf "${BOLD}${YELLOW}══════════════════════════════════════════════════════════${NC}\n"
  echo
  printf "  1. Abra: ${BOLD}https://github.com/${REPO_OWNER}/${REPO_NAME}/settings/keys/new${NC}\n"
  printf "  2. Title: ${BOLD}rpi-$(pi_name)${NC}\n"
  printf "  3. Key (linha única):\n\n${GREEN}"
  cat "${SSH_KEY_PATH}.pub"
  printf "${NC}\n  4. ${BOLD}Não marque${NC} 'Allow write access' e clique em ${BOLD}Add key${NC}\n\n"

  printf "${BLUE}Aguardando o cadastro (até 10 min — Ctrl+C para abortar)${NC}"
  local elapsed=0
  until test_repo_access; do
    sleep 5; elapsed=$((elapsed+5)); printf "."
    if [ "$elapsed" -ge 600 ]; then
      printf "\n"; err "Chave não cadastrada em 10 min. Rode o instalador de novo."; exit 1
    fi
  done
  printf "\n"; log "Chave autorizada"
}

clone_main_repo() {
  if [ -d "$INSTALL_DIR/.git" ]; then
    info "Repo já clonado em $INSTALL_DIR (o bootstrap atualiza)"
    return
  fi
  if [ -e "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null || true)" ]; then
    err "$INSTALL_DIR existe e não está vazio. Remova ou aponte INSTALL_DIR para outro caminho."
    exit 1
  fi
  step "Clonando ${REPO_OWNER}/${REPO_NAME} (branch $BRANCH) → $INSTALL_DIR"
  git clone --branch "$BRANCH" "$REPO_URL_SSH" "$INSTALL_DIR"
}

# I.2: rede, HTTPS (certificado), watchdog, firewall e hotspot. Sem isto o
# nginx não sobe e o painel fica inacessível.
setup_host() {
  local script="$INSTALL_DIR/infra/pi/setup-host.sh"
  if [ ! -f "$script" ]; then
    err "$script não encontrado — o branch '$BRANCH' não é o do Ion Smart Edge?"
    exit 1
  fi
  step "Preparando o sistema do Pi (setup-host.sh)"
  if [ -n "${HOSTNAME_NEW:-}" ]; then
    $SUDO bash "$script" --hostname "$HOSTNAME_NEW"
  else
    $SUDO bash "$script"
  fi
}

run_bootstrap() {
  local bootstrap="$INSTALL_DIR/scripts/bootstrap-edge-rpi.sh"
  if [ ! -f "$bootstrap" ]; then
    err "Script $bootstrap não encontrado. Estrutura do repo pode ter mudado."
    exit 1
  fi
  step "Instalando a plataforma (bootstrap-edge-rpi.sh)"
  BRANCH="$BRANCH" INSTALL_DIR="$INSTALL_DIR" SSH_KEY_PATH="$SSH_KEY_PATH" bash "$bootstrap"
}

ask_reboot() {
  echo
  printf "${BOLD}${YELLOW}══════════════════════════════════════════════════════════${NC}\n"
  printf "${BOLD}${YELLOW}  🔁 REINÍCIO NECESSÁRIO${NC}\n"
  printf "${BOLD}${YELLOW}══════════════════════════════════════════════════════════${NC}\n"
  echo "  Rede, hotspot de configuração e watchdog passam a valer depois do reinício."
  echo "  Depois dele, o painel fica em https://$(hostname).local"
  echo
  # stdin é o pipe do curl: a pergunta vai para o terminal.
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
  install_apt_prereqs
  setup_deploy_key
  clone_main_repo
  setup_host
  run_bootstrap
  remove_old_gh_token
  ask_reboot
}

main "$@"
