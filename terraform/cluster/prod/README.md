# Add-ons do cluster

Traefik, cert-manager, namespaces e o ClusterIssuer, declarados em Terraform.
Não há script nem `kubectl` no processo: `terraform apply` é o único ponto de
entrada, e `terraform plan` detecta divergência entre o cluster e o git.

| Recurso | O que é |
| --- | --- |
| `kubernetes_namespace.addons` | namespaces `traefik` e `cert-manager` |
| `kubernetes_namespace.applications` | namespaces `simplaca` e `postlet` |
| `helm_release.traefik` | Traefik na versão fixada em `traefik_chart_version` |
| `helm_release.cert_manager` | cert-manager, com CRDs |
| `helm_release.cluster_issuers` | `charts/cluster-issuers`, ClusterIssuer `letsencrypt-prod` |

## State separado, de propósito

Este diretório tem state próprio, distinto de `terraform/aks/prod`. Os
providers `kubernetes` e `helm` precisam do cluster existindo no momento do
`plan`; num state único o primeiro `plan` travaria sem o cluster. Aplique
`terraform/aks/prod` primeiro.

## Pré-requisitos

`az login` com a identidade que tem `Azure Kubernetes Service RBAC Cluster
Admin` no cluster, e o binário `kubelogin` no PATH (`az aks install-cli`). O
cluster usa `local_account_disabled = true`, então não existe credencial
estática: os providers pedem um token ao kubelogin a cada operação.

## Uso

```bash
cp terraform.tfvars.example terraform.tfvars   # preencha subscription_id e acme_email
terraform init
terraform plan -out=cluster.tfplan
terraform apply cluster.tfplan
terraform output traefik_public_ip
```

O output `traefik_public_ip` é o endereço do A record da API; ele substitui o
`kubectl get svc -n traefik` do processo anterior. O cert-manager emite o
certificado por HTTP-01 depois que o domínio resolve para esse IP e a porta 80
está acessível.

## Versões dos add-ons

Atualizar um add-on é editar `traefik_chart_version` ou
`cert_manager_chart_version` e aplicar. O `helm_release` usa `atomic` e `wait`:
se a release nova não ficar pronta, o Helm volta à anterior. Leia o changelog
do chart antes de subir uma major.

O e-mail do ACME é a variável `acme_email` e vira um value do chart. Ele não
fica versionado e não é injetado por substituição de texto em runtime — o
chart recusa renderizar sem ele, e o CI verifica essa recusa.

Nenhum segredo deve ser armazenado neste diretório. O state não é commitado.
