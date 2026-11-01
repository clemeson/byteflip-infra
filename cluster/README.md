# Componentes compartilhados do cluster

`scripts/apply-cluster.sh` instala Traefik e cert-manager com versões fixas,
cria os namespaces e aplica o ClusterIssuer. A execução exige `kubectl`
configurado no contexto `personal-prod`, Helm e acesso ao AKS. O script recusa
outro contexto para evitar alterações em cluster errado.

Traefik recebe um Azure Load Balancer público. Após a instalação, consulte o
IP com `kubectl get svc -n traefik` e crie o A record da API no Route 53.
O cert-manager usa HTTP-01 para emitir o certificado depois que o domínio
resolve para o Traefik e a porta 80 está acessível.

As configurações de DNS, segredos e políticas de rede serão acrescentadas
quando os respectivos requisitos de produção estiverem definidos. Nenhum
segredo deve ser armazenado neste diretório.
