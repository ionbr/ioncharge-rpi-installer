# IonCharge RPi Installer — Ion Smart Edge

Instalador de um comando do **Ion Smart Edge** num Raspberry Pi 5.

> Este branch (`ion-smart-edge`) instala o Ion Smart Edge. A `main` continua instalando a versão anterior.

## Uso

No Pi (Raspberry Pi OS 64-bit, com internet pelo cabo), logado como o usuário do Pi (não root):

```bash
curl -fsSL https://raw.githubusercontent.com/ionbr/ioncharge-rpi-installer/ion-smart-edge/install.sh | bash
```

O script:
1. instala os pacotes base e o Docker;
2. pede o **token de preparação** (e a chave do Tailscale, opcional);
3. baixa as imagens prontas da versão. A credencial de leitura vem da Smart Cloud pelo token e é descartada no fim;
4. extrai de dentro da imagem o pacote do host (`setup-host.sh`, compose, configs);
5. roda `infra/pi/setup-host.sh`: hostname `ionsmart-xxxx`, serial, **licença da placa**, certificado HTTPS, watchdog, firewall, rede (DHCP + IP de serviço 192.168.250.1) e hotspot de configuração;
6. roda `scripts/bootstrap-edge-rpi.sh`: `.env` e stack (Postgres, Mosquitto, backend, painel e nginx), sem compilar nada;
7. pede para reiniciar.

O Pi **não recebe código-fonte nem chave do GitHub**. Um Pi instalado pelo instalador antigo (com clone do repositório) é convertido ao rodar este instalador: o código e a deploy key são apagados; `.env`, senha do Mosquitto e banco ficam. Depois, um admin Ion apaga a deploy key `rpi-<hostname>` no GitHub.

## O que o técnico faz

1. Liga o Pi no cabo de rede e abre o terminal.
2. Roda o `curl | bash` acima.
3. Digita o **token de preparação**, gerado por um admin Ion na Frota (Dispositivos → Gerar token de preparação). O token vale 24 h e serve para vários Pis.
4. Responde **S** para reiniciar.

## Depois do reinício

| O quê | Endereço |
|---|---|
| Painel | `https://ionsmart-xxxx.local` ou `https://<ip-do-pi>` |
| Cabo direto (notebook em `192.168.250.2/24`) | `https://192.168.250.1` |
| Hotspot de configuração | SSID `IonSmart-xxxx`; senha em `/etc/ionsmart/ap-password` |
| OCPP (configurar no carregador) | `ws://<ip-do-pi>:9000/ocpp/<NOME_DO_CARREGADOR>` |

O certificado é autoassinado: o navegador pede confirmação na primeira vez. A impressão digital aparece no fim do `setup-host.sh`.

## Atribuir o Pi a um quadro

Depois do reinício o Pi aparece em **Smart Cloud → Controladores → Preparados**. O admin liga o serial da etiqueta ao quadro em **Sites → site → Adicionar quadro** e, em até 30 s, o Pi começa a sincronizar. Ninguém digita código no Pi.

Pi preparado por instalador antigo (sem chave de atribuição): pareamento por código na aba Controlador do quadro, digitado em `https://ionsmart-xxxx.local/setup`, ou rode o instalador de novo com um token.

## Preparação automática, sem SSH (vários Pis)

Para Super Admin preparar vários Pis de uma vez:

1. Grave o cartão no Raspberry Pi Imager (Raspberry Pi OS Lite 64-bit) com a customização de **usuário e SSH**; hostname e Wi-Fi em branco.
2. Com o cartão ainda no computador:
   ```bash
   bash ion-prep.sh
   ```
   Ele pede o token de preparação (Controladores → Preparar Pi → Copiar), a URL da nuvem e a chave do Tailscale (opcional), e grava tudo na partição de boot.
3. Ejete, coloque no Pi, ligue o cabo de rede e a fonte. No primeiro boot o Pi roda o instalador sozinho, reinicia e aparece em **Controladores → Preparados** (~20 min).

Para vários cartões seguidos, exporte as variáveis uma vez e rode `bash ion-prep.sh` a cada cartão:
```bash
export IONSMART_PROVISION_TOKEN=… SYNC_CLOUD_URL=https://smart.ioncharge.com.br TS_AUTHKEY=…
```
Para lotes, a chave do Tailscale precisa ser **reutilizável** (com `tag:edge-pi`, validade curta).

O token fica em texto no cartão até o primeiro boot, quando o Pi o apaga. Use tokens de 24 h e não deixe cartões preparados largados. Log no Pi: `/var/log/ionsmart-firstboot.log`. Se falhar (sem rede, por exemplo), o Pi tenta de novo nos próximos boots, até 3 vezes.

## Variáveis (opcionais)

| Variável | Default | Descrição |
|---|---|---|
| `IONSMART_VERSION` | a do `.env` (Pi já instalado) ou `ion-smart-edge` | Versão das imagens (`1.0.0-rc.1`, …) |
| `IONSMART_PROVISION_TOKEN` | (pergunta) | Token de preparação |
| `INSTALL_DIR` | `$HOME/ion-smart-charge` | Pasta da instalação (não troque num Pi já instalado: o nome define o volume do banco) |
| `HOSTNAME_NEW` | `ionsmart-<MAC>` | Hostname do Pi |
| `SYNC_CLOUD_URL` | `https://smart.ioncharge.com.br` | URL da Smart Cloud |
| `TS_AUTHKEY` | (pergunta) | Chave do Tailscale da Ion |
| `IONSMART_AUTO_REBOOT` | `0` | `1` reinicia no fim sem perguntar |
| `EDGE_RETENTION_DAYS` | `30` | Dias de retenção local |

Segredos (`JWT_SECRET`, `POSTGRES_PASSWORD`, `MOSQUITTO_PASSWORD`…) são gerados no Pi. Lista completa em `scripts/bootstrap-edge-rpi.sh`.

## Atualizar um Pi já instalado

Pela Smart Cloud: **Atualizações** → campanha com a versão (OTA; o Pi volta sozinho se a nova não subir). Ou rode o instalador de novo com a versão desejada (pede um token de preparação). Sem `IONSMART_VERSION`, ele mantém a versão em que o Pi está:

```bash
curl -fsSL https://raw.githubusercontent.com/ionbr/ioncharge-rpi-installer/ion-smart-edge/install.sh | IONSMART_VERSION=1.0.0-rc.1 bash
```

## O que este repositório contém

`install.sh`, `ion-prep.sh` (prepara o cartão), `firstboot/` (script de primeiro boot e a checagem do `ion-prep`) e este README. Sem segredos, sem código do produto. É público para permitir o `curl | bash`.
