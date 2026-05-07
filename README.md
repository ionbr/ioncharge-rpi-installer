# IonCharge RPi Installer

Wrapper público de instalação do **IonCharge Edge** em Raspberry Pi.

## Uso

No Pi (recém-instalado, com internet):

```bash
curl -fsSL https://raw.githubusercontent.com/ionbr/ioncharge-rpi-installer/main/install.sh | bash
```

O script instala dependências, autentica no GitHub via device-code flow, clona o repo privado [ionbr/ion-smart-charge](https://github.com/ionbr/ion-smart-charge) e executa o `scripts/bootstrap-edge-rpi.sh` de lá — que instala Docker, gera deploy key SSH dedicada, builda a imagem edge (Postgres + Redis + backend + frontend) e sobe a stack.

Tempo total: ~15–25 min na primeira vez (build das imagens ARM é o gargalo).

## O que o técnico faz no Pi

1. **Liga o Pi** e abre o terminal (com internet)
2. **Roda o `curl | bash`** acima
3. **Autentica no GitHub** (uma vez): copia o código de 8 caracteres mostrado, abre `https://github.com/login/device` no celular, cola o código, clica Autorizar
4. **Cadastra a deploy key**: copia a chave `ssh-ed25519 ...` mostrada, abre `https://github.com/ionbr/ion-smart-charge/settings/keys/new`, cola, dá nome (`rpi-<hostname>`), **não marca** "Allow write access", clica Add key
5. **Espera o build** (~15-25 min)
6. Saída final mostra:
   - URLs do Pi (Dashboard `:3001`, API `:3000`, OCPP `:9000`)
   - **Próximo passo: pareamento via UI**

## Pareamento com a cloud (depois do boot)

A partir do PR #102 do produto, o pareamento é feito **na UI local do Pi**, não em arquivos `.env`:

1. Solicita ao admin Íon um **claim code** (formato `ABCD-1234`, validade 24h)
   - Admin gera no dashboard cloud em `Fleet → [edge] → Pareamento → Gerar código`
   - Pode ler do **QR code** se preferir
2. No celular ou notebook na mesma rede do Pi, abre `http://<ip-do-pi>:3001/setup`
3. Digita os 8 caracteres na tela de pareamento
4. Pi valida com a cloud, recebe API key escopada (cifrada AES-256-GCM no DB local) e começa a sincronizar

Após pareado, atualizações de config (chargers, balancing, vehicles) descem da cloud automaticamente a cada 5 min. Sessões e eventos sobem em fila.

## Variáveis (opcionais)

Repassadas para o `bootstrap-edge-rpi.sh`. Ver lista completa em [bootstrap-edge-rpi.sh](https://github.com/ionbr/ion-smart-charge/blob/main/scripts/bootstrap-edge-rpi.sh).

| Variável | Default | Descrição |
|---|---|---|
| `INSTALL_DIR` | `$HOME/ion-smart-charge` | Destino do clone |
| `BRANCH` | `main` | Branch do repo privado |
| `JWT_SECRET` | gerado | Segredo JWT (32+ chars) |
| `SESSION_SECRET` | gerado | Segredo de sessão do frontend |
| `POSTGRES_PASSWORD` | gerado | Senha do Postgres local |
| `SYNC_CLOUD_URL` | `https://app.ioncharge.com.br` | URL da cloud central |
| `EDGE_RETENTION_DAYS` | `30` | Dias de retenção de dados locais |

Variáveis de pareamento (`EDGE_SITE_ID`, `EDGE_DEVICE_ID`, `SYNC_EDGE_API_KEY`) **não existem mais** — a config persiste cifrada em `EdgeConfig` no DB local após o pareamento via UI.

## Atualizações futuras

Após a primeira instalação, atualizações de novos PRs mergeados em `main` são feitas direto no Pi (sem rodar este installer de novo):

```bash
cd ~/ion-smart-charge
git pull && docker compose -f docker-compose.edge.yml up -d --build
```

A deploy key SSH gerada no setup inicial faz o `git pull` funcionar sem token.

## O que este repositório contém

Apenas o `install.sh` wrapper. Sem segredos, sem código do produto, sem credenciais. O instalador é público para permitir o `curl | bash` direto.

O código real do IonCharge Edge fica em [ionbr/ion-smart-charge](https://github.com/ionbr/ion-smart-charge) (privado).
