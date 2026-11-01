# Simplaca API

O chart usa a imagem publicada no ACR com tag igual ao SHA completo do commit.
O repositório e a tag são fornecidos pelo deploy, e não são fixados aqui.

O workflow do repositório `simplaca-backend` sincroniza o Kubernetes Secret
`simplaca-api-env` no namespace `simplaca` com os seus próprios Secrets do
GitHub Actions. Os valores de ambiente da aplicação ficam nesse Secret, não
no values do Helm. O mesmo workflow publica a imagem no ACR e executa
`helm upgrade` usando este chart e este values.

O Dockerfile atual executa `prisma migrate deploy` no CMD. Os values
sobrescrevem esse CMD para iniciar apenas o servidor. Um Job Helm executa a
migração uma vez antes de cada upgrade. A migração deve manter compatibilidade
com a versão anterior, pois o rollback do Helm não reverte o banco.

O endpoint `/health` apenas retorna uma resposta HTTP; ele não verifica banco
nem integrações externas. A readiness e os testes pós-deploy devem evoluir
antes de depender de rollback automático como única proteção.
