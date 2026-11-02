# Segredos das releases ZISP

## O que havia antes, e o que sobrou

Duas coisas diferentes eram chamadas de "segredo", e so uma sobreviveu.

**Credenciais de CI** — `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`AWS_REGION`, `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`, `KUBECONFIG_B64`,
`INFRA_TOKEN`. Eram **GitHub Actions Secrets** nos repos das aplicacoes, e
continuam la. **Nenhuma delas e necessaria no fluxo novo** e todas devem ser
apagadas:

| secret | por que sai |
|---|---|
| `AWS_ACCESS_KEY_ID` / `_SECRET_ACCESS_KEY` | o registry e o ACR, por OIDC. Sem chave de longa duracao. |
| `AWS_REGION` | idem |
| `VPS_HOST` / `VPS_USER` / `VPS_SSH_KEY` | nao ha VPS, nao ha tunel SSH. O API server do AKS e alcancado por OIDC + kubelogin. |
| `KUBECONFIG_B64` | um kubeconfig estatico em secret de CI era a credencial mais perigosa do fluxo antigo. Substituido por token de 15 minutos. |
| `INFRA_TOKEN` | era um PAT para dar checkout no repo de infra privado. O byteflip-infra e publico para leitura. |

Sobram so **Variables** (nao Secrets): `ACR_NAME`, `AZURE_BUILD_CLIENT_ID`,
`AZURE_DEPLOY_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.

**Env de runtime** (`<app>-env`) — nunca estava num secret manager. Era um
Secret do Kubernetes criado **a mao** de um `.env` local, por
`infra/scripts/secrets.sh`, que lia `~/secrets/<app>.env`. O Secret vivia so
no cluster, e o cluster foi apagado. `~/secrets/` nao existe nesta maquina e
nao ha `.env` de nenhuma das tres APIs.

**Conclusao: parte do env de runtime foi recuperada** de um gerenciador de
senhas em 02/11/2026; o resto se **regenera** em vez de se recuperar.

> **Todo valor recuperado nessa passagem precisa ser rotado antes de entrar no
> cofre.** Ele trafegou por uma sessao de chat, o que significa que esta em log
> de aplicacao, de rede e de provedor. Reaproveitar o valor economiza descobrir
> *onde* ele e usado -- nao economiza trocar o valor.

### Recuperado (mapeamento)

| valor no gerenciador | chave |
|---|---|
| `zisp-api` / url session pooler | `DATABASE_URL` do `zisp-api` |
| `VPN_HOOK_TOKEN` | `VPN_HOOK_TOKEN` do `zisp-vpn-api`, e o par dele no `zisp-api` |
| `TOKEN INJEST LEADS SUPER ZISP` | `LEADS_INGEST_TOKEN` do `zisp-super-api` |
| `AWS` (par de chaves) | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` de runtime |

### Ainda faltando

Nao estavam no gerenciador e precisam ser criados ou reemitidos:

| chave | release | como obter |
|---|---|---|
| `JWT_SECRET` | `zisp-vpn-api` | `openssl rand -hex 32` |
| `VPN_PSK` | `zisp-vpn-api` | `openssl rand -hex 16` |
| `JWT_ACCESS_SECRET` | `zisp-super-api` | `openssl rand -hex 32` |
| `JWT_REFRESH_SECRET` | `zisp-super-api` | `openssl rand -hex 32` |
| `ZISP_API_INTERNAL_TOKEN` | `zisp-super-api` + `zisp-api` | `openssl rand -hex 32`, igual nos dois |
| `CALENDLY_API_TOKEN` | `zisp-super-api` | reemitir no Calendly |
| `CALENDLY_WEBHOOK_TOKEN` | `zisp-super-api` | reemitir no Calendly |
| `ANTHROPIC_WORKSPACE_ID` | `zisp-super-api` | console da Anthropic |
| `DATABASE_URL` | `zisp-vpn-api` | banco novo -- ver README, schema separado |

### Credenciais que apareceram e NAO vao para o cofre

Nada disto pertence a uma aplicacao deste cluster. Ficam no gerenciador de
senhas, e as marcadas precisam de rotacao pelo motivo acima:

| | rotar? |
|---|---|
| senha root das VPS Hostinger (duas) e Hetzner | **sim** |
| codigos de recuperacao do Magalu (16) | **sim**, invalidar e gerar novos |
| PAT fine-grained do GitHub (`github_pat_...`) | **sim**, e nao e mais necessario -- o `INFRA_TOKEN` saiu do fluxo |
| PAT classico do GitHub (`ghp_...`) | **sim**; PAT classico e amplo demais, prefira fine-grained por repo |
| senha do integrator simplaca, admin do vpn-api, admin dos dois blogs | **sim** |
| token Iugu | **sim** (legado do simplaca, pre-Mercado Pago) |
| Mercado Pago: access token + assinatura do webhook | **sim** -- ja estava pendente desde 01/11, e passou por aqui outra vez |
| senhas Supabase do simplaca e do zisp | **sim** |

## Para onde vao agora

Um segredo no Key Vault `byteflipappsprod` por release, com um objeto JSON
dentro. O ESO expande cada chave do JSON numa chave do Secret do Kubernetes
(`dataFrom.extract`), e o Reloader reinicia o pod quando o valor muda.
Acrescentar uma variavel passa a ser uma edicao no cofre, sem tocar git nem CI.

**Nao-segredo nao entra aqui.** `PORT`, `NODE_ENV`, faixas de IP, nomes de
tabela, URLs internas e flags de comportamento ficam no `configMap` do
values-prod.yaml, versionados e revisaveis em PR. O cofre guarda o que
vazaria se fosse lido.

    az keyvault secret set --vault-name byteflipappsprod \
      --name zisp-vpn-api-env --file /caminho/zisp-vpn-api.json

## zisp-vpn-api

| chave | origem | observacao |
|---|---|---|
| `DATABASE_URL` | gerar | `?connection_limit=10`; o Job de migracao le SO do Secret |
| `JWT_SECRET` | **regerar** | invalida tokens existentes; sem impacto, nao ha cliente ativo |
| `VPN_HOOK_TOKEN` | **regerar** | tem de bater com o que o `zisp-api` espera no hook |
| `VPN_PSK` | **regerar** | o codigo tem fallback `'20112011'` *no fonte* (`vpn-clients.service.ts:17`) -- trocar e obrigatorio, nao opcional |

Fora do cofre, no `configMap`: `VPN_IP_RANGE_START/END`,
`VPN_SERVER_PRIVATE_IP`, `VPN_SERVER`, `ZISP_API_INTERNAL_URL`,
`CHAP_SECRETS_PATH`, `CONNECTIONS_STATE_PATH`, `CONCILIATION_CRON`.

Opcionais de observabilidade, hoje sem destino no cluster:
`LOKI_URL`, `PUSHGATEWAY_URL`, `OTEL_EXPORTER_OTLP_ENDPOINT`,
`OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`.

## zisp-super-api

| chave | origem | observacao |
|---|---|---|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | **rotar na AWS** | runtime, nao CI: DynamoDB, SES. Ver a nota sobre chave estatica abaixo |
| `JWT_ACCESS_SECRET` / `JWT_REFRESH_SECRET` | **regerar** | invalida sessoes do painel super |
| `LEADS_INGEST_TOKEN` | **regerar** | |
| `ZISP_API_INTERNAL_TOKEN` | **regerar** | tem de bater com o `zisp-api` |
| `CALENDLY_API_TOKEN` | **reemitir no Calendly** | dependencia de terceiro |
| `CALENDLY_WEBHOOK_TOKEN` | **reemitir no Calendly** | dependencia de terceiro |
| `ANTHROPIC_WORKSPACE_ID` | consultar no console | nao e segredo em si, mas anda junto da chave |

Fora do cofre, no `configMap`: `PORT`, `NODE_ENV`, `CORS_ORIGINS`,
`DYNAMODB_*_TABLE`, `AWS_REGION`, `SES_FROM_EMAIL`, `REDIS_URL`,
`WHATSAPP_SESSION_ID`, `JWT_*_EXPIRES_IN`, `LEADS_*`, `BDR_*`,
`BROADCAST_SEND_INTERVAL_MS`, `CALENDLY_EVENT_TYPE_URI`.

> **Sobre a chave estatica da AWS.** Guardar `AWS_ACCESS_KEY_ID` no Key Vault
> funciona e e o caminho simples, mas e credencial de longa duracao -- o
> oposto do que o resto desta arquitetura faz. O certo seria federacao
> AKS -> AWS (IAM Roles Anywhere, ou OIDC do cluster como provider no IAM),
> trocando o token do ServiceAccount por credencial temporaria, do mesmo jeito
> que o ESO faz com o Entra. Nao vale fazer agora; vale nao esquecer.

## zisp-api

**Nao extraido**: o repo `zisp-api` nao esta nesta maquina. Rode no repo dele
para montar a lista do mesmo jeito que foi feito para os outros dois:

    grep -rhoE "process\.env\.[A-Z0-9_]+" src | sort -u
    grep -rhoE "config(Service)?\.get(Or[A-Za-z]+)?(<[^>]+>)?\(['\"][A-Za-z0-9_.]+" src | sort -u

Do que ja se sabe pelo values antigo, no cofre vao ao menos `DATABASE_URL`
(com `?connection_limit=10`), as credenciais AWS de runtime (o bucket
`zisp-backups` e S3), e os tokens que casam com `VPN_HOOK_TOKEN` e
`ZISP_API_INTERNAL_TOKEN` dos outros dois.

## Como conferir antes de subir

O ESO so cria o Secret se o segredo existir no cofre, e o pod so sobe se o
Secret existir. Falha cedo, mas a mensagem nao e obvia -- confira primeiro:

    az keyvault secret list --vault-name byteflipappsprod --query '[].name' -o tsv
    # e, por release, que o JSON parseia e quais chaves tem:
    az keyvault secret show --vault-name byteflipappsprod --name zisp-vpn-api-env \
      --query value -o tsv | jq -r 'keys[]'
