# ZISP no AKS

Tres releases, um namespace (`zisp`), um node pool dedicado.

| release | repo / imagem | porta | ingress | migracao | amarrado ao no? |
|---|---|---|---|---|---|
| `zisp-api` | `zisp-api` | 3030 | `api.zisp.com.br` | prisma | sim (rota da VPN, Postgres) |
| `zisp-vpn-api` | `zisp-vpn-api` | 3000 | nenhum | prisma | **sim (hostPath do ppp)** |
| `zisp-super-api` | `zisp-super-api` | 3050 | `super-api.zisp.com.br` | nao tem | sim (Redis) |

Origem dos values: `zisp-k8s/apps/*/helmrelease.yaml` (Flux) e `infra/zisp/*.yaml`.
Renomeados de `api-core`/`api-vpn`/`super-api` para o nome do repo, igual ao
`simplaca-api`. Consequencia: o Service do vpn-api passou de `api-vpn-svc`
para `zisp-vpn-api-svc`, e o `VPN_API_URL` do `zisp-api` ja aponta para o nome
novo.

## Estado de partida (02/11/2026)

A VPS `k3s-gp` em Brazil South **foi apagada**. Sobraram no resource group so
a VNet, o NSG e a chave SSH. Em toda a subscription nao existe **nenhum disco
e nenhum snapshot**. Consequencias, e sao elas que mandam no resto deste
documento:

- **O IP `191.235.200.253` foi devolvido** ao pool da Azure. Nao e
  recuperavel, e pode ja estar com outro cliente. Todo Mikrotik em campo
  aponta hoje para um endereco morto: **o ZISP esta fora do ar, nao em
  migracao.**
- **O banco do `zisp-api` NAO se perdeu.** Ele nunca esteve no PVC da VPS:
  esta no Supabase, projeto `msiwosrcaemcocsammfl` em **sa-east-1**.
  Verificado em 02/11/2026 -- Postgres 17.6, 67 tabelas, 49 migrations
  aplicadas, nenhuma falhada, ultima em 2026-09-14, com dado real
  (8 organizations, 8 customers, 5 routerboards, 7 subscriptions). O plano
  antigo de migrar para um Postgres in-cluster nunca foi executado, e isso
  acabou salvando os dados.
- **O banco do `zisp-vpn-api` se perdeu.** O projeto Supabase
  `tvzkhharhvdjqilcvkhe` nao responde em nenhuma regiao do pooler
  (`tenant/user not found`) e o host direto nao resolve. A `vpn_clients`,
  fonte da verdade do `chap-secrets`, foi junto. Nao e bloqueio: o repo tem
  `prisma/migrations` e o Job de pre-upgrade recria o schema num banco vazio.
  Sem cliente ativo, nao ha dado a recuperar, so a recadastrar.
- **O `chap-secrets` foi perdido com o disco**, e era derivado do banco acima.
  No cluster novo ele nasce num PVC, nao em hostPath.

## Pre-requisitos, em ordem

1. **Quota de vCPU em eastus2.** Primeiro da lista porque e o unico item que
   depende de terceiro e tem prazo imprevisivel. O `zisp-api` e o
   `zisp-vpn-api` tem `nodeSelector` do pool `zisp`, que nao existe sem ela.

   *(O backup em `s3://zisp-backups/postgres/` deixou de ser pre-requisito: o
   banco do `zisp-api` esta vivo no Supabase. Vale conferir de qualquer modo,
   como rede de seguranca, mas nada depende disso.)*
2. **Os dois Redis no namespace `zisp`.** Postgres saiu desta lista: esta no
   Supabase e nao precisa vir para o cluster. Sobra o `redis-bullmq` (fila
   BullMQ, `noeviction`) e o `redis-monitor` (cache de telemetria,
   `allkeys-lru`) -- as politicas sao incompativeis, por isso duas
   instancias. Juntos pedem 100m de CPU e 160Mi.

   Porte do `charts/platform` do repo `infra`, so a parte de Redis:
   `local-path` -> `managed-csi` (que, ao contrario do local-path, permite
   expansao). Nao ha mais namespace `platform`: so o ZISP usa estes Redis,
   entao moram em `zisp` e os values usam nome curto de Service.

3. **Banco do `zisp-vpn-api`.** Recomendado: schema separado no MESMO projeto
   Supabase do `zisp-api` (`?schema=vpn&connection_limit=5`) em vez de projeto
   novo. Um projeto, uma conta, um lugar para somar `connection_limit`.
4. **Segredos no Key Vault `byteflipappsprod`**, um JSON por release:
   `zisp-api-env`, `zisp-vpn-api-env`, `zisp-super-api-env`. **Os valores
   antigos foram perdidos** junto com o cluster -- eles nunca estiveram num
   secret manager, viviam num Secret do Kubernetes criado a mao de um `.env`
   local. A maior parte se regenera; dois tokens do Calendly precisam ser
   reemitidos. Lista chave por chave, com origem de cada uma, em
   [SECRETS.md](SECRETS.md).
5. **DNS** — `api.zisp.com.br` e `super-api.zisp.com.br` para o IP do Traefik
   deste cluster (`135.18.210.136`), registro A, nao CNAME: o desafio HTTP-01
   do cert-manager nao aceita CNAME.
6. **Nos repos das aplicacoes** — o `deploy.yml` do molde em
   `_workflow-template/`, as 5 Variables e o environment `production`.

### A regiao do cluster esta errada para o ZISP

Medido do no `aks-system-49592979-vmss`, TCP connect na porta 5432:

| pooler Supabase | latencia |
|---|---|
| `aws-1-sa-east-1` (banco do zisp-api) | **0,15s** |
| `aws-1-us-east-1` (banco do simplaca) | 0,04s |

Sao ~110ms a mais por ida e volta. Numa requisicao Prisma com varias queries
isso multiplica, e nao ha cache que salve a primeira.

E o mesmo padrao da VPN: o cluster esta em `eastus2`, mas os Mikrotik estao no
Brasil e o banco do ZISP tambem. So o simplaca esta bem posicionado.

Tres saidas, da mais barata para a mais cara:

1. **Mover o projeto Supabase para us-east-1.** O Supabase nao realoca projeto,
   mas o dado e pequeno (8 organizations, 8 customers): `pg_dump` + restore num
   projeto novo resolve em minutos. Corrige os 110ms do banco; nao mexe na
   latencia dos Mikrotik.
2. **Aceitar.** Para trafego de gerencia e painel interno, ~110ms e chato mas
   nao inviabiliza.
3. **Cluster em `brazilsouth`.** O certo para o ZISP, caro agora: o simplaca
   esta em producao aqui e a quota regional teria de ser pedida de novo.

Recomendado 1 agora, e 3 na agenda se o ZISP crescer.

### Quota: so a VPN precisa

O `zisp-api` e o `zisp-super-api` **nao esperam aumento de quota**. Medido em
02/11/2026, com o simplaca no ar:

| | CPU | memoria |
|---|---|---|
| no `...000000`, livre | 1235m | 6667Mi |
| no `...000001`, livre | 898m | 5891Mi |
| ZISP inteiro (3 APIs + Postgres + 2 Redis), requests | **630m** | **1088Mi** |

Cabe num no sozinho, com folga. Por isso essas duas releases vao **sem
pinning**: falam com Postgres e Redis por Service, e Service nao depende de
no. O pool `zisp` e o aumento de quota existem **so** por causa do servidor
L2TP; `zisp_node_pool_enabled` nasce `false` por isso.

O `zisp-vpn-api` e a excecao: tem `nodeSelector` e fica `Pending` enquanto o
pool nao existir. Isso e fail-safe, nao defeito -- ele nao deve subir antes da
decisao abaixo estar tomada.

## A VPN: decidido, L2TP num no do AKS

Parte dos CPEs nao tem WireGuard, entao tem de ser L2TP. **E possivel**, e o
que decidia a viabilidade foi verificado no no em 02/11/2026, nao presumido:

| | valor no no `aks-system-49592979-vmss` | implicacao |
|---|---|---|
| kernel | `6.8.0-1071-azure` | — |
| `linux-modules-extra-6.8.0-1071-azure` | **instalado** | o risco principal nao se concretizou |
| `l2tp_core`, `l2tp_netlink`, `l2tp_ppp` | presentes (`.ko.zst`) | `modprobe l2tp_ppp` resolve as dependencias |
| `ppp_generic` | **builtin** | `/dev/ppp` (108,0) ja existe no no |
| `pppol2tp` | **nao existe**, nem como alias | **fora da lista** -- o role do Ansible o listava e falharia aqui |
| `net.ipv4.ip_forward` | **1** | nada a fazer, o kube-proxy ja liga |
| `net.ipv4.conf.{all,default}.rp_filter` | **1** | **precisa virar 0**, senao o trafego do tunel e descartado sem log |

Comando usado (plano de controle da Azure, sem criar nada no cluster):

    az vmss run-command invoke -g MC_personal-aks-eastus2-prod_personal-prod_eastus2 \
      -n aks-system-49592979-vmss --instance-id 0 --command-id RunShellScript \
      --scripts 'modinfo -n l2tp_ppp; sysctl -n net.ipv4.conf.all.rp_filter'

### Como o zisp-api alcanca os Mikrotik

Nao e "mesmo host, mesma rede" -- o pod tem network namespace proprio. E
roteamento:

    pod zisp-api (10.80.x.x, netns proprio)
      | rota default -> veth
      v
    host netns do no          <- aqui vivem ppp0..pppN
      | tabela de rotas: 10.19.25.50 dev ppp3   (criada pelo pppd)
      v
    Mikrotik 10.19.25.50

O no e o roteador. E por isso que o `zisp-api` tem `nodeSelector` do pool
`zisp`: de outro no nao existe rota para a faixa e o pacote morre no default
gateway.

### A regra que nao existia antes

O caminho de **volta**. Pod -> MK nao e NAT'd, entao o Mikrotik ve origem
`10.80.x.x` (com Azure CNI o IP do pod e um IP real da VNet). O MK nao tem
rota para `10.80.0.0/16`, responde pelo default gateway dele -- a internet do
cliente -- e o pacote se perde. Conexao que abre e nunca responde.

    iptables -t nat -A POSTROUTING -d 10.19.24.0/22 -o ppp+ \
      -j SNAT --to-source 10.19.25.1

Com isso o MK ve tudo vindo do gateway do tunel, responde pelo tunel sem saber
que existe Kubernetes, e **nenhum CPE precisa de rota estatica**. Bonus: a
origem fica estavel, utilizavel em regra de firewall no RouterOS. A regra esta
em `images/vpn-server/entrypoint.sh`.

### Decisoes do chart, e por que

`charts/vpn-server`, separado do `charts/app`. O `charts/app` e "aplicacao
HTTP stateless" e nao deve ganhar `hostNetwork`, `privileged` nem montagem de
`/lib/modules` -- sao exatamente os privilegios que um pod de aplicacao nunca
pede.

- **StatefulSet, nao DaemonSet.** DaemonSet seria o reflexo para "um por no do
  pool", mas DaemonSet com PVC quebra quando o pool tiver dois nos: Azure Disk
  e RWO e o segundo pod fica preso em ContainerCreating. `replicas: 1` diz o
  que a arquitetura exige: UM terminador de tunel, UM disco.
- **`hostNetwork: true`** para as interfaces ppp nascerem no netns do no, que e
  o que permite o no rotear o trafego dos outros pods.
- **`dnsPolicy: ClusterFirstWithHostNet`** -- sem isso, com hostNetwork o pod
  usa o resolver do no e para de resolver Service do cluster.
- **`privileged: true`**, nao uma lista de capabilities: pppd quer `/dev/ppp`,
  modprobe quer SYS_MODULE, iptables e sysctl querem NET_ADMIN, e o conjunto
  so funciona com o `/dev` do host visivel.
- **`externalTrafficPolicy: Local`** -- obrigatorio, nao otimizacao: no default
  (`Cluster`) o kube-proxy faz SNAT e o pppd veria o IP do NO em vez do IP de
  cada Mikrotik, todos os peers com a mesma origem.
- **IP publico estatico no Terraform** (`azurerm_public_ip.vpn`), nao criado
  pelo Service: um IP do Service morre com ele e recriar sortearia outro
  endereco -- visitar cada CPE outra vez. Como o IP vive no RG do cluster e
  nao no `MC_*`, precisa da anotacao
  `azure-load-balancer-resource-group` **e** de Network Contributor para a
  identidade do control plane; faltando qualquer uma o Service fica
  `<pending>` sem erro util.
- **`chap-secrets` em PVC, nao hostPath.** No AKS o `/etc` do no nao sobrevive
  a reimagem; a base de usuarios seria perdida e os tuneis so voltariam quando
  a conciliacao reescrevesse do banco, que roda de 6 em 6 horas. O
  `zisp-vpn-api` monta o MESMO PVC (`data-vpn-server-0`): RWO permite varios
  pods no mesmo no, e os dois tem o nodeSelector do pool.
- **`/var/run/ppp` em hostPath, e aqui esta certo.** E o `connections.json` dos
  hooks, em `/run`, que e tmpfs: o conteudo DEVE desaparecer no boot.

### O que foi testado, e como

| | prova |
|---|---|
| imagem compila | `docker build` |
| binarios presentes | xl2tpd, pppd, iptables, modprobe, ss, python3 |
| hooks ip-up/ip-down | conectar 2, reconectar sem ip-down (IP atualizado, sem duplicata), desconectar 1 |
| guard de modulo | roda sem o modulo -> falha com a causa e o comando de diagnostico |
| xl2tpd parseia o config | `Using l2tp kernel support`, versao 1.3.18 |
| socket UDP 1701 | aberto; e o mesmo check da probe de readiness |
| 4 regras de iptables | aplicadas em netns isolado, e idempotentes na reaplicacao |
| chart | `helm lint` + `kubectl apply --dry-run=server` contra o cluster real |

**Nao testado:** um tunel de verdade fechando. Isso exige o node pool criado e
um Mikrotik (ou um cliente L2TP) do outro lado.

### A divida que fica

Sem IPsec o trafego **nao e cifrado**, so autenticado por MSCHAPv2 (`noccp`,
`refuse-pap`, `refuse-chap`). Era assim na VPS, com a diferenca de que agora
atravessa de `eastus2` ate o Brasil -- ~120ms a mais e em claro pela internet
publica. L2TP/IPsec resolveria a cifra, mas **ESP (protocolo 50) nao passa pelo
Load Balancer da Azure**, que carrega so TCP e UDP: seria preciso NAT-T (ESP
dentro de UDP 4500) mais UDP 500, e suporte a NAT-T em cada CPE.

Ordem recomendada: subir como esta, confirmar tunel, e entao avaliar NAT-T
para os CPEs que suportam.

### Ordem de subida

1. quota de vCPU aprovada (agora **obrigatoria**: o pool `zisp` deixou de ser
   opcional, porque a VPN e o `zisp-api` dependem dele);
2. `zisp_node_pool_enabled = true` + `terraform apply` em `terraform/aks/prod`
   (cria tambem o `azurerm_public_ip.vpn`);
3. `terraform apply` em `terraform/cluster/prod` (namespace + ExternalSecrets);
4. workflow **Deploy VPN server** -- publica a imagem e cria o PVC, que o
   `zisp-vpn-api` precisa existir antes;
5. os tres `deploy.yml` das aplicacoes;
6. configurar os Mikrotik com o IP de `terraform output vpn_public_ip`.
