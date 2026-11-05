#!/usr/bin/env bash
# ============================================================
# Ion Smart Edge — prepara um cartão SD para a instalação automática (I.22a)
#
# 1. Grave o cartão no Raspberry Pi Imager: Raspberry Pi OS Lite (64-bit), com a
#    customização de usuário e SSH (hostname em branco, Wi-Fi em branco).
# 2. Com o cartão ainda no computador, rode:
#      bash ion-prep.sh                 # acha a partição de boot sozinho
#      bash ion-prep.sh /Volumes/bootfs # ou informe o caminho
# 3. Ejete o cartão, coloque no Pi, ligue o cabo de rede e a fonte.
#    Em ~20 min o Pi aparece em Smart Cloud → Controladores → Preparados.
#
# Variáveis (opcionais, para preparar vários cartões sem digitar de novo):
#   IONSMART_PROVISION_TOKEN  token de preparação (Controladores → Preparar Pi)
#   SYNC_CLOUD_URL            URL da Smart Cloud (default: https://smart.ioncharge.com.br)
#   TS_AUTHKEY                chave do Tailscale (reutilizável e com tag:edge-pi para lotes)
#   IONSMART_VERSION          versão das imagens (default: a do branch)
#
# O token fica em texto na partição de boot até o primeiro boot, quando o Pi o
# apaga do cartão. Use tokens de 24 h e não deixe cartões preparados largados.
# ============================================================
set -euo pipefail

RAW="https://raw.githubusercontent.com/ionbr/ioncharge-rpi-installer/ion-smart-edge"
HOOK='bash /boot/firmware/ionsmart-firstboot.sh install'

err() { printf '❌ %s\n' "$*" >&2; exit 1; }
ok() { printf '✅ %s\n' "$*"; }

find_boot() {
  for d in /Volumes/bootfs /Volumes/boot "/media/${USER:-}/bootfs" "/run/media/${USER:-}/bootfs"; do
    [ -f "$d/config.txt" ] && { echo "$d"; return; }
  done
}

BOOT="${1:-$(find_boot)}"
[ -n "$BOOT" ] && [ -f "$BOOT/config.txt" ] || err "Partição de boot do cartão não encontrada. Informe o caminho: bash ion-prep.sh /Volumes/bootfs"

ask() { # ask VAR "pergunta" [secreto] — variável já definida (mesmo vazia) não pergunta
  if [ -z "${!1+x}" ]; then
    printf '%s ' "$2"
    if [ "${3:-}" = secreto ]; then read -rs "$1" || true; echo; else read -r "$1" || true; fi
  fi
}
ask IONSMART_PROVISION_TOKEN "Token de preparação (Controladores → Preparar Pi → Copiar):" secreto
[ -n "${IONSMART_PROVISION_TOKEN:-}" ] || err "Sem token não dá para preparar o Pi."
ask SYNC_CLOUD_URL "URL da Smart Cloud [https://smart.ioncharge.com.br]:"
SYNC_CLOUD_URL="${SYNC_CLOUD_URL:-https://smart.ioncharge.com.br}"
ask TS_AUTHKEY "Chave do Tailscale (Enter para pular):" secreto

# Script de primeiro boot: o do lado deste arquivo ou o publicado no GitHub
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/firstboot/ionsmart-firstboot.sh"
if [ -f "$SRC" ]; then cp "$SRC" "$BOOT/ionsmart-firstboot.sh"
else curl -fsSL "$RAW/firstboot/ionsmart-firstboot.sh" -o "$BOOT/ionsmart-firstboot.sh" || err "Não baixei o script de primeiro boot"; fi

{
  printf 'IONSMART_PROVISION_TOKEN=%s\n' "$IONSMART_PROVISION_TOKEN"
  printf 'SYNC_CLOUD_URL=%s\n' "$SYNC_CLOUD_URL"
  if [ -n "${TS_AUTHKEY:-}" ]; then printf 'TS_AUTHKEY=%s\n' "$TS_AUTHKEY"; fi
  if [ -n "${IONSMART_VERSION:-}" ]; then printf 'IONSMART_VERSION=%s\n' "$IONSMART_VERSION"; fi
} > "$BOOT/ionsmart-firstboot.env"

# Engata no primeiro boot que o Imager já preparou
if [ -f "$BOOT/user-data" ]; then
  # cloud-init (Raspberry Pi OS Trixie): item no runcmd, criando a lista se não houver
  if ! grep -q 'ionsmart-firstboot' "$BOOT/user-data"; then
    awk -v hook="$HOOK" '
      { print }
      /^runcmd:[[:space:]]*$/ && !done { getline nxt; ind = "- "; if (match(nxt, /^[[:space:]]*- /)) ind = substr(nxt, 1, RLENGTH);
        print ind hook; print nxt; done = 1 }
      END { if (!done) { print "runcmd:"; print "- " hook } }
    ' "$BOOT/user-data" > "$BOOT/user-data.ion" && mv "$BOOT/user-data.ion" "$BOOT/user-data"
  fi
  grep -q '^users:\|^  - name:\|^- name:' "$BOOT/user-data" || printf '⚠️  user-data sem usuário: use a customização do Imager (usuário + SSH)\n'
  ok "primeiro boot via cloud-init"
elif [ -f "$BOOT/firstrun.sh" ]; then
  # Imager antigo (Bookworm): antes da limpeza final do firstrun.sh
  if ! grep -q 'ionsmart-firstboot' "$BOOT/firstrun.sh"; then
    awk -v hook="$HOOK" '/^rm -f \/boot.*firstrun\.sh/ && !done { print hook; done = 1 } { print }' \
      "$BOOT/firstrun.sh" > "$BOOT/firstrun.ion" && mv "$BOOT/firstrun.ion" "$BOOT/firstrun.sh"
    grep -q 'ionsmart-firstboot' "$BOOT/firstrun.sh" || err "Não achei onde engatar no firstrun.sh"
  fi
  ok "primeiro boot via firstrun.sh"
else
  err "O cartão não tem a customização do Imager (user-data ou firstrun.sh). Grave de novo com usuário e SSH."
fi

ok "cartão preparado em $BOOT"
echo "   Ejete o cartão, coloque no Pi e ligue no cabo de rede."
echo "   Acompanhe em Smart Cloud → Controladores → Preparados (~20 min)."
echo "   Log no Pi: /var/log/ionsmart-firstboot.log"
