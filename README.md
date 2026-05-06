# IonCharge RPi Installer

Wrapper público de instalação do **IonCharge Edge** em Raspberry Pi.

## Uso

No Pi (recém-instalado, com internet):

```bash
curl -fsSL https://raw.githubusercontent.com/ionbr/ioncharge-rpi-installer/main/install.sh | bash
```

O script instala dependências, autentica no GitHub via device-code flow, clona o repo privado [ionbr/ion-smart-charge](https://github.com/ionbr/ion-smart-charge) e executa o `scripts/bootstrap-edge-rpi.sh` de lá — que instala Docker, gera deploy key SSH dedicada, builda a imagem edge (SQLite + cache em memória) e sobe o container.

Tempo total: ~10–20 min na primeira vez (build da imagem ARM é o gargalo).

## O que o técnico precisa fazer

1. Ligar o Pi e abrir terminal (com internet)
2. Rodar o `curl | bash` acima
3. Quando aparecer **"Autenticando no GitHub"**: copiar o código de 8 caracteres mostrado e abrir a URL `https://github.com/login/device` no celular ou outro computador, colar o código, clicar Autorizar
4. Quando aparecer **"AÇÃO NECESSÁRIA — Cadastrar Deploy Key"**: copiar a chave pública mostrada (linha começando com `ssh-ed25519 ...`), abrir https://github.com/ionbr/ion-smart-charge/settings/keys/new, colar a chave, dar um nome (`rpi-<hostname>`), **não marcar** "Allow write access", clicar Add key
5. Esperar o build terminar — saída final mostra IP local + URLs

## Variáveis (opcionais)

Repassadas para o `bootstrap-edge-rpi.sh`. Ver lista completa no [bootstrap-edge-rpi.sh](https://github.com/ionbr/ion-smart-charge/blob/main/scripts/bootstrap-edge-rpi.sh).

| Variável | Default | Descrição |
|---|---|---|
| `INSTALL_DIR` | `$HOME/ion-smart-charge` | Destino do clone |
| `BRANCH` | `main` | Branch do repo privado |
| `EDGE_SITE_ID` | _(vazio)_ | ID do site (para sync com cloud) |
| `EDGE_DEVICE_ID` | `rpi-<hostname>` | ID do dispositivo |
| `SYNC_CLOUD_URL` | _(vazio)_ | URL da cloud central (vazio = standalone) |
| `SYNC_EDGE_API_KEY` | _(vazio)_ | API key de sync |
| `EDGE_RETENTION_DAYS` | `30` | Dias de retenção de dados locais |

Exemplo com cloud:
```bash
curl -fsSL https://raw.githubusercontent.com/ionbr/ioncharge-rpi-installer/main/install.sh \
  | EDGE_SITE_ID=site_xxx \
    SYNC_CLOUD_URL=https://api.ioncharge.com.br \
    SYNC_EDGE_API_KEY=xxx \
    bash
```

## Atualizações futuras

Depois da primeira instalação, atualizações de novos PRs mergeados em `main` são feitas direto no Pi (sem rodar este installer de novo):

```bash
cd ~/ion-smart-charge
git pull && docker compose -f docker-compose.edge.yml up -d --build
```

A deploy key SSH gerada no setup inicial faz o `git pull` funcionar sem token.

## O que este repositório contém

Apenas o `install.sh` wrapper. Sem segredos, sem código do produto, sem credenciais. O instalador é público para permitir o `curl | bash` direto.

O código real do IonCharge Edge fica em [ionbr/ion-smart-charge](https://github.com/ionbr/ion-smart-charge) (privado).
