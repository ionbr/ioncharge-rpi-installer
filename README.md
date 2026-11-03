# IonCharge RPi Installer — Ion Smart Edge

Instalador de um comando do **Ion Smart Edge** num Raspberry Pi 5.

> Este branch (`ion-smart-edge`) instala o Ion Smart Edge. A `main` continua instalando a versão anterior.

## Uso

No Pi (Raspberry Pi OS 64-bit, com internet pelo cabo), logado como o usuário do Pi (não root):

```bash
curl -fsSL https://raw.githubusercontent.com/ionbr/ioncharge-rpi-installer/ion-smart-edge/install.sh | bash
```

O script:
1. instala os pacotes base;
2. gera a **chave de leitura do Pi** e espera um admin Ion cadastrá-la no repositório;
3. clona o [ionbr/ion-smart-charge](https://github.com/ionbr/ion-smart-charge) (branch `ion-smart-edge`);
4. roda `infra/pi/setup-host.sh`: hostname `ionsmart-xxxx`, certificado HTTPS, watchdog, firewall, rede (DHCP + IP de serviço 192.168.250.1) e hotspot de configuração;
5. roda `scripts/bootstrap-edge-rpi.sh`: Docker, `.env`, build das imagens e stack (Postgres, Mosquitto, backend, painel e nginx);
6. pede para reiniciar.

Tempo: ~15–25 min na primeira vez (o build das imagens no Pi é o gargalo).

Nenhuma conta ou token pessoal do GitHub fica no Pi. Pis instalados pelo instalador antigo têm o login do `gh` removido.

## O que o técnico faz

1. Liga o Pi no cabo de rede e abre o terminal.
2. Roda o `curl | bash` acima.
3. **Pede a um admin Ion para cadastrar a chave** mostrada na tela em `https://github.com/ionbr/ion-smart-charge/settings/keys/new` (título `rpi-<hostname>`, **sem** "Allow write access"). O script continua sozinho quando a chave é cadastrada.
4. Espera o build e responde **S** para reiniciar.

## Depois do reinício

| O quê | Endereço |
|---|---|
| Painel | `https://ionsmart-xxxx.local` ou `https://<ip-do-pi>` |
| Cabo direto (notebook em `192.168.250.2/24`) | `https://192.168.250.1` |
| Hotspot de configuração | SSID `IonSmart-xxxx`; senha em `/etc/ionsmart/ap-password` |
| OCPP (configurar no carregador) | `ws://<ip-do-pi>:9000/ocpp/<NOME_DO_CARREGADOR>` |

O certificado é autoassinado: o navegador pede confirmação na primeira vez. A impressão digital aparece no fim do `setup-host.sh`.

## Pareamento com a Smart Cloud

1. Peça ao admin Ion um **código de pareamento** (formato `ABCD-1234`, validade de 24 h), gerado na Frota da Smart Cloud.
2. Abra `https://ionsmart-xxxx.local/setup`.
3. Digite o código. O Pi recebe a chave de sincronização (guardada cifrada no banco local) e começa a sincronizar.

## Variáveis (opcionais)

| Variável | Default | Descrição |
|---|---|---|
| `INSTALL_DIR` | `$HOME/ion-smart-charge` | Destino do clone |
| `BRANCH` | `ion-smart-edge` | Branch do repo privado |
| `HOSTNAME_NEW` | `ionsmart-<MAC>` | Hostname do Pi |
| `SYNC_CLOUD_URL` | `https://smart.ioncharge.com.br` | URL da Smart Cloud |
| `EDGE_RETENTION_DAYS` | `30` | Dias de retenção local |

Segredos (`JWT_SECRET`, `POSTGRES_PASSWORD`, `MOSQUITTO_PASSWORD`…) são gerados no Pi. Lista completa em `scripts/bootstrap-edge-rpi.sh`.

## Atualizar um Pi já instalado

Até existir a atualização OTA, rode o bootstrap de novo (ele puxa o branch, recalcula a versão e remove containers antigos):

```bash
bash ~/ion-smart-charge/scripts/bootstrap-edge-rpi.sh
```

## O que este repositório contém

Só o `install.sh` e este README. Sem segredos, sem código do produto. É público para permitir o `curl | bash`.
