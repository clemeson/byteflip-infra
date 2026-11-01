# Simplaca API

O chart usa a imagem publicada no ACR com tag igual ao SHA completo do commit.
O repositório e a tag são fornecidos pelo deploy, e não são fixados aqui.

O workflow reutilizável `deploy-simplaca.yml` sincroniza o Kubernetes Secret
`simplaca-api-env` no namespace `simplaca` com os segredos do GitHub Actions
da aplicação. As configurações não sensíveis ficam no ConfigMap deste values.
O CI da aplicação publica a imagem no ACR e chama esse workflow para o AKS.

O Dockerfile atual executa `prisma migrate deploy` no CMD. Os values
sobrescrevem esse CMD para iniciar apenas o servidor. Um Job Helm executa a
migração uma vez antes de cada upgrade. A migração deve manter compatibilidade
com a versão anterior, pois o rollback do Helm não reverte o banco.

O endpoint `/health` apenas retorna uma resposta HTTP; ele não verifica banco
nem integrações externas. A readiness e os testes pós-deploy devem evoluir
antes de depender de rollback automático como única proteção.
