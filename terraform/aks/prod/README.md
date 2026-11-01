# AKS de produção

O state fica localmente em `terraform.tfstate` nesta pasta. Esse arquivo e
`terraform.tfvars` ficam fora do Git. Guarde uma cópia segura do state depois
de cada `apply`, pois ele é necessário para administrar os recursos criados.

```bash
cp terraform.tfvars.example terraform.tfvars
# Edite terraform.tfvars com os valores da sua conta.
# aks_admin_principal_id: Object ID do usuário ou grupo Entra que administrará o AKS.
terraform init -reconfigure
terraform plan -out=aks.tfplan
terraform apply aks.tfplan
terraform output kubeconfig_command
```

O AKS tem `prevent_destroy`; removê-lo exige uma alteração explícita e
revisão do código. O ACR não tem mais: mudar a região de um registry força
recriação, e `prevent_destroy` impediria até o `plan`.

Todos os recursos ficam em `personal-aks-eastus2-prod`, na região East US 2:
cluster, rede, identidade do plano de controle, ACR e as identidades OIDC do
GitHub. Uma região só evita pull de imagem entre regiões e egresso cobrado
entre o ACR e os nós. O pool de sistema usa dois
nós `Standard_D2as_v7` (2 vCPU e 8 GiB cada), sem autoscaling. Eles consomem
os 4 vCPU de quota regional disponíveis na assinatura. A criação do cluster
em East US 2 com esse pool foi aceita pela API do AKS. Um terceiro nó ou um
upgrade com nó temporário requer aumento de quota. Planeje upgrades sem nó
temporário ou aumente a quota antes de atualizar os nós.

A identidade do plano de controle é criada antes do AKS e recebe
`Network Contributor` na VNet. A propagação da permissão no Azure pode levar
tempo; se o primeiro `apply` falhar por autorização de rede, execute o mesmo
`terraform apply` novamente após a propagação.

O cluster usa Microsoft Entra ID e Azure RBAC, com contas locais desabilitadas.
O Terraform cria identidades GitHub OIDC separadas para build e deploy do
Simplaca. Copie os outputs `github_build_client_id`, `github_deploy_client_id`
e `azure_tenant_id` para as variables do GitHub Actions da aplicação.
Para acesso humano, execute `az aks get-credentials` e use `kubelogin`
com a sessão `az login`. A role de admin é concedida ao
`aks_admin_principal_id`; escolha um usuário ou grupo que você controle.
