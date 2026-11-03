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

## Pareamento com a Smart Cloud

1. Peça ao admin Ion um **código de pareamento** (formato `ABCD-1234`, validade de 24 h), gerado na Frota da Smart Cloud.
2. Abra `https://ionsmart-xxxx.local/setup`.
3. Digite o código. O Pi recebe a chave de sincronização (guardada cifrada no banco local) e começa a sincronizar.

## Variáveis (opcionais)

| Variável | Default | Descrição |
|---|---|---|
| `IONSMART_VERSION` | `ion-smart-edge` | Versão das imagens (`1.0.0-rc.1`, …) |
| `IONSMART_PROVISION_TOKEN` | (pergunta) | Token de preparação |
| `INSTALL_DIR` | `$HOME/ion-smart-charge` | Pasta da instalação (não troque num Pi já instalado: o nome define o volume do banco) |
| `HOSTNAME_NEW` | `ionsmart-<MAC>` | Hostname do Pi |
| `SYNC_CLOUD_URL` | `https://smart.ioncharge.com.br` | URL da Smart Cloud |
| `EDGE_RETENTION_DAYS` | `30` | Dias de retenção local |

Segredos (`JWT_SECRET`, `POSTGRES_PASSWORD`, `MOSQUITTO_PASSWORD`…) são gerados no Pi. Lista completa em `scripts/bootstrap-edge-rpi.sh`.

## Atualizar um Pi já instalado

Até existir a atualização OTA (V.7), rode o instalador de novo com a versão desejada (pede um token de preparação):

```bash
curl -fsSL https://raw.githubusercontent.com/ionbr/ioncharge-rpi-installer/ion-smart-edge/install.sh | IONSMART_VERSION=1.0.0-rc.1 bash
```

## O que este repositório contém

Só o `install.sh` e este README. Sem segredos, sem código do produto. É público para permitir o `curl | bash`.
