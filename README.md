# Infraestrutura pessoal: AKS, Simplaca e Postlet

Este repositório contém apenas a infraestrutura dos projetos pessoais. O código
e os Dockerfiles das aplicações continuam nos seus próprios repositórios.

| Caminho | Responsabilidade |
| --- | --- |
| `terraform/aks/prod/` | AKS, rede, node pool, ACR e identidades OIDC |
| `terraform/cluster/prod/` | Namespaces, Traefik, cert-manager e emissor TLS |
| `charts/app/` | Chart Helm comum para API e worker |
| `charts/cluster-issuers/` | ClusterIssuer do cert-manager |
| `apps/<produto>/<componente>/values-prod.yaml` | Configuração de cada release |

Tudo é declarativo. Não há script de shell nem `kubectl` manual no processo:
dois `terraform apply` montam a Azure e o cluster, e o CI da aplicação executa
`helm upgrade`. O Deployment mantém os pods; HPA ajusta as réplicas quando
ativado.

## Estado atual

- O AKS `personal-prod` está criado em East US 2, com dois nós
  `Standard_D2as_v7`. O ACR e as identidades GitHub também ficam em East US 2,
  no mesmo resource group `personal-aks-eastus2-prod`.
- Dois caminhos escrevem nas releases. **Imagem** vem do repo da aplicação:
  o CI publica no ACR e chama o workflow reutilizável desta infra.
  **Configuração** vem daqui: `apply-config.yml` dispara em push na `main` e
  reaplica os values sobre a imagem que já está rodando.
- Simplaca tem values reais de porta, comando, domínio e migração. A imagem
  é fornecida pelo CI como repositório ACR e SHA do commit.
- Postlet está **bloqueado para deploy** até confirmar seu código, porta,
  comando do worker, health check, segredos e migrações. Seus arquivos values
  são rascunhos e o chart recusa renderizá-los.
- O workflow da infra recebe os Secrets do Simplaca durante a execução e usa
  o script da aplicação para atualizar `simplaca-api-env` antes do Helm;
  consulte `apps/simplaca/api/README.md`.

## Sequência de implantação

1. Configurar `terraform/aks/prod/terraform.tfvars` com assinatura Azure,
   nome único de ACR e Object ID do administrador do AKS.
2. Executar `terraform init -reconfigure` e `terraform plan` nessa pasta.
3. Revisar custo e quota antes de `apply`; depois, guardar uma cópia segura de
   `terraform.tfstate`. Não commitar o state.
4. Obter credenciais do AKS com o output
   `kubeconfig_command`.
5. Aplicar `terraform/cluster/prod` (state próprio). Requer `kubelogin` no
   PATH e `acme_email` no tfvars. Instala os add-ons em versões fixas e cria
   namespaces e ClusterIssuer. O output `traefik_public_ip` dá o IP do DNS.
6. Configurar variáveis e segredos do GitHub Actions conforme o `DEPLOY.md`
   do Simplaca. O workflow da aplicação publica a imagem no ACR e chama o
   workflow desta infra; a infra sincroniza o Secret e executa o Helm.
7. Apontar `api.simplaca.com.br` no Route 53 para o `traefik_public_ip` e
   verificar TLS, `/health` e um fluxo real da aplicação.

## Alterar objeto Kubernetes pela infra

HPA, `resources`, probes, `replicas`, Ingress, Service e ConfigMap são objetos
do Kubernetes: quem os atualiza é o Helm, não o Terraform. Edite
`apps/simplaca/api/values-prod.yaml` ou o chart, commite na `main`, e
`deploy.yml` aplica no cluster.

A tag da imagem não está versionada aqui. Nesse caminho o workflow lê
`image.repository` e `image.tag` do release vivo com `helm get values` e os
reaplica sem alteração, e desliga a migração: a imagem não muda, logo o schema
esperado por ela não muda.

Se o release ainda não existir, o workflow falha com instrução para publicar a
imagem pelo `simplaca-backend` primeiro. Os dois caminhos podem rodar ao mesmo
tempo e grupos de concorrência do GitHub não atravessam repositório; a proteção
é o lock do Helm, que faz a segunda operação falhar com *another operation in
progress* em vez de corromper o release.

Use `helm history simplaca-api -n simplaca` para ver a origem de cada revisão:
a descrição diz `image=<sha>` ou `config=<sha>`.

Release, namespace e values estão fixos no workflow porque há uma aplicação.
Com uma segunda, parametrize por input ou matrix.

Objetos Kubernetes vão por Helm. Node pool, rede, ACR, Key Vault e identidades
são recursos Azure e só o Terraform alcança.

## Segredos

Cada release tem **um** segredo no Key Vault, com um objeto JSON dentro. O
External Secrets Operator lê o vault por workload identity e materializa o
Secret do Kubernetes, expandindo o JSON em uma chave por campo. Acrescentar uma
variável de ambiente é editar esse JSON — não toca git nem CI, e não há segredo
de aplicação no GitHub.

`PORT` é exceção e **não** deve estar no JSON: o chart o injeta a partir de
`containerPort`, para a porta não ficar declarada em dois lugares.

O workflow usa `helm upgrade --install --atomic --wait`: se os recursos não
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

Os states Terraform permanecem locais (`terraform/aks/prod/` e
`terraform/cluster/prod/`) e não devem ser commitados. São separados porque os
providers `kubernetes` e `helm` precisam do cluster existindo no `plan`. O
workflow de validação executa somente `terraform init -backend=false` e
`terraform validate` nos dois, sem acessar state nem aplicar mudanças.

## Limites de responsabilidade

Este repositório não cria banco nem migra dados de produção. O Simplaca usa
`DATABASE_URL` externo. Publique os workflows, configure as identidades e
segredos do CI e verifique backup, monitoramento e DNS antes da abertura de
tráfego. Os valores de CPU/memória do chart são iniciais e devem ser
ajustados com métricas reais.
