#!/usr/bin/env bash
# Checagem do ion-prep.sh em partições de boot falsas (sem gravar cartão).
# Uso: bash firstboot/test_ion_prep.sh
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export IONSMART_PROVISION_TOKEN=ion_tok SYNC_CLOUD_URL=https://nuvem.test TS_AUTHKEY=""
HOOK='bash /boot/firmware/ionsmart-firstboot.sh install'
fail() { echo "FALHOU: $*"; exit 1; }

mk() { mkdir -p "$tmp/$1"; touch "$tmp/$1/config.txt"; }

# 1. cloud-init com runcmd recuado: o gancho entra no topo da lista, com o mesmo recuo
mk a; printf '#cloud-config\nusers:\n  - name: tec\nruncmd:\n  - [ sh, -c, "echo oi" ]\n' > "$tmp/a/user-data"
bash "$here/ion-prep.sh" "$tmp/a" >/dev/null
grep -qxF -e "  - $HOOK" "$tmp/a/user-data" || fail "runcmd recuado"
grep -qF 'echo oi' "$tmp/a/user-data" || fail "perdeu o runcmd do Imager"
[ "$(grep -c '^runcmd:' "$tmp/a/user-data")" = 1 ] || fail "runcmd duplicado"

# 2. cloud-init sem runcmd: cria a lista
mk b; printf '#cloud-config\nusers:\n- name: tec\n' > "$tmp/b/user-data"
bash "$here/ion-prep.sh" "$tmp/b" >/dev/null
grep -qxF -e "- $HOOK" "$tmp/b/user-data" || fail "runcmd novo"

# 3. rodar duas vezes não duplica
bash "$here/ion-prep.sh" "$tmp/a" >/dev/null
[ "$(grep -c 'ionsmart-firstboot' "$tmp/a/user-data")" = 1 ] || fail "gancho duplicado"

# 4. firstrun.sh (Imager antigo): antes da limpeza
mk c; printf '#!/bin/bash\nset +e\necho cfg\nrm -f /boot/firmware/firstrun.sh\nexit 0\n' > "$tmp/c/firstrun.sh"
bash "$here/ion-prep.sh" "$tmp/c" >/dev/null
[ "$(grep -n 'ionsmart-firstboot' "$tmp/c/firstrun.sh" | cut -d: -f1)" -lt "$(grep -n '^rm -f' "$tmp/c/firstrun.sh" | cut -d: -f1)" ] || fail "firstrun"

# 5. cartão sem customização: recusa
mk d; bash "$here/ion-prep.sh" "$tmp/d" >/dev/null 2>&1 && fail "aceitou cartão sem customização"

# 6. arquivos: script de boot e .env com o token
[ -x "$tmp/a/ionsmart-firstboot.sh" ] || [ -f "$tmp/a/ionsmart-firstboot.sh" ] || fail "script de boot"
grep -qx 'IONSMART_PROVISION_TOKEN=ion_tok' "$tmp/a/ionsmart-firstboot.env" || fail ".env"
grep -q '^TS_AUTHKEY=' "$tmp/a/ionsmart-firstboot.env" && fail "TS_AUTHKEY vazio não deveria ir"
echo "ion-prep: ok"
