#!/usr/bin/env bash
# ============================================================
# Ion Smart Edge — preparação automática no primeiro boot (I.22a)
#
# Copiado para a partição de boot do cartão pelo ion-prep.sh, junto com
# ionsmart-firstboot.env (token de preparação, URL da nuvem, chave do
# Tailscale). Dois modos:
#
#   install  — chamado uma vez pelo primeiro boot do Raspberry Pi OS
#              (cloud-init runcmd ou firstrun.sh do Imager), como root.
#              Tira o .env da partição de boot (FAT, legível por qualquer
#              um que pegar o cartão), guarda em /etc/ionsmart (600) e
#              registra o serviço ionsmart-firstboot.
#   run      — o serviço: espera a nuvem responder, roda o instalador como
#              o usuário do Pi, apaga o token e reinicia. Se falhar, tenta
#              de novo no próximo boot (até 3 vezes).
#
# Log: /var/log/ionsmart-firstboot.log
# ============================================================
set -uo pipefail

ENV_DST=/etc/ionsmart/firstboot.env
SELF_DST=/usr/local/sbin/ionsmart-firstboot
UNIT=/etc/systemd/system/ionsmart-firstboot.service
ATTEMPTS_FILE=/var/lib/ionsmart/firstboot-attempts
LOG=/var/log/ionsmart-firstboot.log
MAX_ATTEMPTS=3

log() { printf '%s [firstboot] %s\n' "$(date '+%F %T')" "$*"; }

install_mode() {
  local here; here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  install -d -m 755 /etc/ionsmart /var/lib/ionsmart
  install -m 700 "${BASH_SOURCE[0]}" "$SELF_DST"
  if [ -f "$here/ionsmart-firstboot.env" ]; then
    (umask 077; cp "$here/ionsmart-firstboot.env" "$ENV_DST")
    # Na FAT não há permissão: o token sai do cartão já no primeiro boot
    shred -u "$here/ionsmart-firstboot.env" 2>/dev/null || rm -f "$here/ionsmart-firstboot.env"
  fi
  cat > "$UNIT" <<EOF
[Unit]
Description=Ion Smart Edge — preparação automática (primeiro boot)
After=network-online.target
Wants=network-online.target
ConditionPathExists=$ENV_DST

[Service]
Type=oneshot
ExecStart=$SELF_DST run
TimeoutStartSec=infinity

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable ionsmart-firstboot.service
  # No cloud-init o sistema já está subindo: entra na fila deste boot. No firstrun.sh roda no próximo.
  systemctl start --no-block ionsmart-firstboot.service 2>/dev/null || true
  log "serviço registrado"
}

finish() { # finish <motivo> — não tenta mais
  shred -u "$ENV_DST" 2>/dev/null || rm -f "$ENV_DST"
  systemctl disable ionsmart-firstboot.service >/dev/null 2>&1 || true
  log "$1"
}

run_mode() {
  exec >> "$LOG" 2>&1
  [ -s "$ENV_DST" ] || { finish "sem $ENV_DST — nada a fazer"; return 0; }

  local n; n=$(( $(cat "$ATTEMPTS_FILE" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$ATTEMPTS_FILE"
  if [ "$n" -gt "$MAX_ATTEMPTS" ]; then
    finish "desistiu após $MAX_ATTEMPTS tentativas — prepare pelo SSH (guia, etapa 4)"
    return 1
  fi
  log "tentativa $n de $MAX_ATTEMPTS"

  set -a; . "$ENV_DST"; set +a
  local cloud="${SYNC_CLOUD_URL:-https://smart.ioncharge.com.br}"
  local installer="${IONSMART_INSTALLER_URL:-https://raw.githubusercontent.com/ionbr/ioncharge-rpi-installer/ion-smart-edge/install.sh}"

  # Rede: cabo com DHCP pode levar um tempo; até 15 min
  local t=0
  until curl -fsS -m 10 -o /dev/null "$cloud/health"; do
    t=$((t + 15)); [ "$t" -ge 900 ] && { log "nuvem $cloud não respondeu em 15 min — tenta no próximo boot"; return 1; }
    sleep 15
  done
  log "nuvem respondeu: $cloud"

  # O instalador roda como o usuário criado no Imager (não root)
  local user; user="$(getent passwd 1000 | cut -d: -f1)"
  [ -n "$user" ] || { log "sem usuário 1000 — use a customização do Imager (usuário e SSH)"; return 1; }
  log "instalando como $user"

  export SYNC_CLOUD_URL="$cloud" IONSMART_AUTO_REBOOT=0
  # O token vai pelo ambiente (--preserve-env), nunca pela linha de comando
  if curl -fsSL -m 60 "$installer" | sudo -u "$user" -H \
      --preserve-env=IONSMART_PROVISION_TOKEN,SYNC_CLOUD_URL,TS_AUTHKEY,IONSMART_VERSION,IONSMART_AUTO_REBOOT \
      bash; then
    finish "preparação concluída — reiniciando"
    systemctl reboot
  else
    log "instalador falhou (veja acima) — tenta de novo no próximo boot"
    return 1
  fi
}

case "${1:-}" in
  install) install_mode ;;
  run) run_mode ;;
  *) echo "uso: $0 install|run" >&2; exit 2 ;;
esac
