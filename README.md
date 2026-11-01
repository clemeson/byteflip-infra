# Infraestrutura pessoal: AKS, Simplaca e Postlet

Este repositório contém apenas a infraestrutura dos projetos pessoais. O código
e os Dockerfiles das aplicações continuam nos seus próprios repositórios.

| Caminho | Responsabilidade |
| --- | --- |
| `terraform/aks/prod/` | AKS, rede, node pool, ACR e identidades OIDC |
| `charts/app/` | Chart Helm comum para API e worker |
| `apps/<produto>/<componente>/values-prod.yaml` | Configuração de cada release |
| `cluster/` | Namespaces, Traefik, cert-manager e emissor TLS |
| `scripts/` | Aplicação idempotente dos add-ons e deploy por SHA |

O Terraform cria a infraestrutura Azure. Helm instala os recursos Kubernetes.
O Deployment mantém os pods; HPA ajusta a quantidade de réplicas quando ativado.

## Estado atual

- O AKS **ainda não foi criado**. O `az aks list` da assinatura selecionada
  estava vazio na preparação deste repositório.
- O CI do Simplaca publica no ACR e chama o workflow Helm deste repositório
  para implantar a imagem por SHA no AKS.
- Simplaca tem values reais de porta, comando, domínio e migração. A imagem
  é fornecida pelo CI como repositório ACR e SHA do commit.
- Postlet está **bloqueado para deploy** até confirmar seu código, porta,
  comando do worker, health check, segredos e migrações. Seus arquivos values
  são rascunhos e o chart recusa renderizá-los.
- Não há segredos neste repositório. O workflow cria ou atualiza o Secret
  `simplaca-api-env` no namespace `simplaca` antes do Helm; consulte
  `apps/simplaca/api/README.md`.

## Sequência de implantação

1. Configurar `terraform/aks/prod/terraform.tfvars` com assinatura Azure,
   nome único de ACR e Object ID do administrador do AKS.
2. Executar `terraform init -reconfigure` e `terraform plan` nessa pasta.
3. Revisar custo e quota antes de `apply`; depois, guardar uma cópia segura de
   `terraform.tfstate`. Não commitar o state.
4. Obter credenciais do AKS com o output
   `kubeconfig_command`.
5. Executar `scripts/apply-cluster.sh` em um runner com acesso ao cluster.
   Ele instala os add-ons com versões fixas e cria namespaces e ClusterIssuer.
6. Configurar variáveis e segredos do GitHub Actions conforme o `DEPLOY.md`
   do Simplaca. O workflow publica a imagem no ACR e chama o workflow Helm,
   que sincroniza o Secret antes do deploy.
7. Apontar `api.simplaca.com.br` no Route 53 para o IP público do serviço
   Traefik e verificar TLS, `/health` e um fluxo real da aplicação.

Comando de deploy depois que imagem e Secret estiverem prontos:

```bash
./scripts/deploy-app.sh simplaca api <acr>.azurecr.io/simplaca-api <sha-completo>
```

O script usa `helm upgrade --install --atomic --wait`: se os recursos não
ficarem prontos, Helm tenta voltar à revisão anterior. Para um problema que
apareça depois de ficar Ready, usar `helm history simplaca-api -n simplaca`
e `helm rollback simplaca-api <revisão> -n simplaca --wait`. Migrações do banco
não são revertidas por Helm; manter compatibilidade com a versão anterior.

## Custo e capacidade antes do primeiro apply

O AKS Free não cobra o plano de controle, mas nós, discos, ACR, IP público,
Load Balancer e tráfego continuam cobrados. O padrão declarado é **dois nós de
4 vCPU** (`Standard_D4als_v7`, 8 GiB por nó) e autoscaler até três nós. Os limites do
autoscaler controlam o máximo, não garantem quota/capacidade para criar nós.

Na API pública de preços da Azure consultada em 2026-11-01, o nó Linux
`Standard_D4als_v7` em Brazil South custava **US$ 0,258/h por nó**. Dois nós
custariam cerca de **US$ 371,52 por 30 dias** ou **US$ 743,04 por 60 dias**,
antes de discos, ACR, Load Balancer, IP, tráfego e eventual terceiro nó. Esta
configuração deve ser comparada ao crédito informado de R$ 1.000, que vence
em 18/11/2026. Fonte da estimativa dos nós:
https://prices.azure.com/api/retail/prices.

Na assinatura inspecionada, o limite de vCPU da família Dalsv7 em Brazil South
era 4, e a quota total regional era 4 vCPU, com 2 já em uso pela VM
`simplaca-postlet`. Para criar dois nós de 4 vCPU sem apagar a VM existente,
as quotas precisam chegar a pelo menos 8 vCPU na família Dalsv7 e 10 vCPU
totais; reserve mais para o terceiro nó e upgrades. Não destrua a VM antes de confirmar se há dados
ou serviços nela. Também confirme que a SKU está disponível no momento do
provisionamento; `terraform plan` não garante capacidade regional.

A assinatura consultada está classificada como `FreeTrial_2014-09-01`. A
[documentação de quotas da Azure](https://learn.microsoft.com/en-us/azure/quotas/quickstart-increase-quota-portal)
informa que somente assinaturas pagas podem solicitar aumento. Se decidir
converter a assinatura para pagamento conforme uso, confirme no portal as
condições de cobrança e o saldo do crédito antes de pedir quota e repetir
`terraform apply`. O state local já contém os recursos criados no primeiro
`apply`; não exclua esse arquivo.

## Limites de responsabilidade

Este repositório não cria banco nem migra dados de produção. O Simplaca usa
`DATABASE_URL` externo. Publique os workflows, configure as identidades e
segredos do CI e verifique backup, monitoramento e DNS antes da abertura de
tráfego. Os valores de CPU/memória do chart são iniciais e devem ser
ajustados com métricas reais.
