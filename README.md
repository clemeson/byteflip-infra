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

- O AKS `personal-prod` está criado em East US 2, com dois nós
  `Standard_D2as_v7`. O ACR e as identidades GitHub continuam em Brazil South.
- O CI do Simplaca publica no ACR e chama o workflow Helm deste repositório
  para implantar a imagem por SHA no AKS.
- Simplaca tem values reais de porta, comando, domínio e migração. A imagem
  é fornecida pelo CI como repositório ACR e SHA do commit.
- Postlet está **bloqueado para deploy** até confirmar seu código, porta,
  comando do worker, health check, segredos e migrações. Seus arquivos values
  são rascunhos e o chart recusa renderizá-los.
- O workflow cria ou atualiza o Secret `simplaca-api-env` no namespace
  `simplaca` antes do Helm; consulte
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
   Informe `ACME_EMAIL` no ambiente. O script instala os add-ons com versões
   fixas e cria namespaces e ClusterIssuer.
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

## Custo e capacidade

O pool atual usa dois nós `Standard_D2as_v7` em East US 2, com 2 vCPU e 8 GiB
por nó. Eles consomem toda a quota regional de 4 vCPU da assinatura. Um nó
extra para escala ou upgrade precisa de quota adicional; planeje atualizações
sem nó temporário enquanto a quota não aumentar. Nós, discos, ACR, IP público,
Load Balancer e tráfego são cobrados mesmo com o plano de controle AKS Free.
Confira custos e crédito disponível no portal Azure antes de aumentar recursos.

O state Terraform permanece local em `terraform/aks/prod/terraform.tfstate` e
não deve ser commitado. O workflow de validação executa somente `terraform
init -backend=false` e `terraform validate`, sem acessar o state nem aplicar
mudanças na Azure.

## Limites de responsabilidade

Este repositório não cria banco nem migra dados de produção. O Simplaca usa
`DATABASE_URL` externo. Publique os workflows, configure as identidades e
segredos do CI e verifique backup, monitoramento e DNS antes da abertura de
tráfego. Os valores de CPU/memória do chart são iniciais e devem ser
ajustados com métricas reais.
