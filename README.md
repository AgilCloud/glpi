# GLPI Docker

[![CI](https://github.com/AgilCloud/glpi/actions/workflows/ci.yaml/badge.svg)](https://github.com/AgilCloud/glpi/actions/workflows/ci.yaml)
[![CD](https://github.com/AgilCloud/glpi/actions/workflows/cd.yaml/badge.svg)](https://github.com/AgilCloud/glpi/actions/workflows/cd.yaml)
[![Docker Hub](https://img.shields.io/docker/pulls/DOCKERHUB_REPOSITORY)](https://hub.docker.com/r/DOCKERHUB_REPOSITORY)
[![License: GPL](https://img.shields.io/badge/license-GPL-blue.svg)](https://www.gnu.org/licenses/gpl-3.0.html)

Imagem Docker e ambiente Docker Compose para executar o [GLPI](https://glpi-project.org/) 10.0.18 com MariaDB 10.11.

> Este projeto empacota o GLPI para facilitar build, execucao local, publicacao e operacao em containers. Ele nao promete plugins pre-instalados: plugins devem ser instalados e atualizados explicitamente pelo operador.

## Requisitos

- Docker Engine recente.
- Docker Compose v2.
- Acesso de escrita aos diretorios usados pelos volumes persistentes.
- Um arquivo `.env` local, quando quiser sobrescrever valores padrao.

## Imagem Docker Hub

Imagem publicada:

- Docker Hub: <https://hub.docker.com/r/DOCKERHUB_REPOSITORY>
- Tag recomendada para GLPI 10.0.18: `DOCKERHUB_REPOSITORY:10.0.18`

Tambem e esperado publicar tags imutaveis por versao e, quando fizer sentido para o fluxo do projeto, tags moveis como `latest`.

## Build local

```bash
docker build \
  -f docker/Dockerfile \
  --build-arg GLPI_VERSION=10.0.18 \
  -t glpi-local:10.0.18 .
```

Para validar a imagem localmente:

```bash
docker run --rm glpi-local:10.0.18 php -v
```

## Execucao local com Docker Compose

Crie um `.env` a partir do exemplo do projeto:

```bash
make setup-env
```

Crie os arquivos de secrets usados pelo Compose:

```bash
mkdir -p secrets
printf '%s\n' 'troque-esta-senha-do-banco' > secrets/glpi_db_password.txt
printf '%s\n' 'troque-esta-senha-admin' > secrets/glpi_admin_password.txt
chmod 600 secrets/*.txt
```

Suba a aplicacao:

```bash
make up
```

Acompanhe os logs:

```bash
docker compose logs -f glpi
```

Abra o GLPI no navegador:

```text
http://localhost:8080
```

Na primeira execucao, a imagem configura o GLPI contra o banco MariaDB definido no Compose. Para ambientes persistentes, mantenha os volumes entre reinicializacoes.

## Credenciais iniciais

Ao iniciar pela primeira vez, o GLPI cria um usuario admin com as seguintes credenciais padrao:

| Campo | Valor |
| --- | --- |
| **Usuario** | `glpi` |
| **Senha** | Definida em `secrets/glpi_admin_password.txt` (padrao: `glpi-ci-admin-password`) |
| **URL** | `http://localhost:8080` |

### Alterar senha do admin inicial

A senha do admin inicial e definida no arquivo `secrets/glpi_admin_password.txt`. Para trocar a senha **antes** da primeira execucao:

```bash
printf '%s\n' 'sua-nova-senha-aqui' > secrets/glpi_admin_password.txt
chmod 600 secrets/glpi_admin_password.txt
```

Depois, destrua os containers e suba novamente:

```bash
docker compose down
docker compose up -d
```

### Alterar senha apos a primeira execucao

Apos logar no GLPI:

1. Clique no seu usuario (canto superior direito).
2. Selecione "Meu perfil".
3. Vá para a aba "Senha".
4. Digite a nova senha e confirme.
5. Clique em "Atualizar".

Alternativamente, use a CLI do GLPI:

```bash
docker compose exec glpi php bin/console user:update \
  --login=glpi \
  --password=sua-nova-senha-aqui \
  --no-interaction
```

## Decisao sobre PostgreSQL

O plano inicial previa PostgreSQL 16, mas o GLPI 10.0.18 nao suporta PostgreSQL como banco da aplicacao. A documentacao oficial informa que apenas MySQL e MariaDB sao suportados atualmente, e o instalador CLI `db:install` tenta usar MySQL/MariaDB. Por isso, este projeto usa MariaDB 10.11 como padrao para ficar executavel e aderente ao GLPI oficial.

## Variaveis disponiveis

As variaveis podem ser definidas no `.env`, no `docker-compose.yaml` ou pelo orquestrador. Quando houver suporte a secret, prefira `*_FILE`; o fallback por variavel de ambiente existe para desenvolvimento local e ambientes simples.

| Variavel ou uso | Padrao sugerido | Descricao |
| --- | --- | --- |
| `GLPI_VERSION` | `10.0.18` | Versao do GLPI usada no build da imagem. |
| `MARIADB_VERSION` | `10.11` | Versao principal do MariaDB usada pelo Compose. |
| `GLPI_HTTP_PORT` | `8080` | Porta publicada no host para acessar o GLPI. |
| `GLPI_DB_TYPE` | `mysql` | Tipo de banco usado pelo GLPI. Para GLPI 10, use MySQL/MariaDB. |
| `GLPI_DB_NAME` | `glpi` | Nome do banco criado pelo MariaDB e usado pelo GLPI. |
| `GLPI_DB_USER` | `glpi` | Usuario criado pelo MariaDB e usado pelo GLPI. |
| `GLPI_DB_PASSWORD_FILE` no `.env` | `./secrets/glpi_db_password.txt` | Arquivo local usado pelo Compose para criar o secret de senha do banco. |
| `GLPI_ADMIN_PASSWORD_FILE` no `.env` | `./secrets/glpi_admin_password.txt` | Arquivo local usado pelo Compose para criar o secret de senha do admin inicial, quando a imagem configurar esse usuario. |
| `GLPI_DB_HOST` | `db` | Host MariaDB visto pelo container GLPI. |
| `GLPI_DB_PORT` | `3306` | Porta MariaDB vista pelo container GLPI. |
| `MARIADB_DATABASE` | `${GLPI_DB_NAME:-glpi}` | Alias operacional para o banco criado pelo container MariaDB. |
| `MARIADB_USER` | `${GLPI_DB_USER:-glpi}` | Alias operacional para o usuario criado pelo container MariaDB. |
| `GLPI_DB_PASSWORD_FILE` | `/run/secrets/glpi_db_password` | Secret montado dentro do container GLPI. |
| `GLPI_DB_PASSWORD` | vazio | Fallback em env para `GLPI_DB_PASSWORD_FILE`. Use apenas quando secret nao estiver disponivel. |
| `MARIADB_PASSWORD_FILE` | `/run/secrets/glpi_db_password` | Secret montado dentro do container MariaDB. |
| `MARIADB_PASSWORD` | vazio | Fallback em env para `MARIADB_PASSWORD_FILE`, quando usado fora do Compose padrao. |
| `GLPI_ADMIN_USER` | vazio | Login do admin inicial, quando a imagem criar ou atualizar usuario por CLI. |
| `GLPI_ADMIN_PASSWORD_FILE` | `/run/secrets/glpi_admin_password` | Secret montado dentro do container GLPI para senha do admin inicial. |
| `GLPI_ADMIN_PASSWORD` | vazio | Fallback em env para `GLPI_ADMIN_PASSWORD_FILE`. |
| `GLPI_DB_WAIT_TIMEOUT` | `60` | Tempo maximo, em segundos, para aguardar o banco ficar pronto. |
| `GLPI_START_CRON` | `1` | Liga ou desliga a tentativa de iniciar cron no container. Use `0` se o cron for externo. |
| `PHP_MEMORY_LIMIT` | `512M` | Limite de memoria do PHP renderizado no bootstrap. |
| `PHP_MAX_UPLOAD` | `128M` | Limite de upload e `post_max_size` do PHP. |
| `PHP_MAX_EXECUTION_TIME` | `300` | Tempo maximo de execucao PHP em segundos. |
| `TZ` / `GLPI_TIMEZONE` | `America/Bahia` | Timezone aplicado ao GLPI e ao PHP. |
| `GLPI_LANGUAGE` / `GLPI_LANG` | `pt_BR` | Idioma padrao do GLPI, quando suportado pela CLI. |
| `GLPI_URL` / `GLPI_BASE_URL` | vazio | URL publica base configurada no GLPI, quando informada. |

## Secrets e fallback por env

Em producao, prefira secrets:

```yaml
services:
  glpi:
    environment:
      GLPI_DB_PASSWORD_FILE: /run/secrets/glpi_db_password
    secrets:
      - glpi_db_password

  db:
    environment:
      MARIADB_PASSWORD_FILE: /run/secrets/glpi_db_password
    secrets:
      - glpi_db_password

secrets:
  glpi_db_password:
    file: ./secrets/glpi_db_password.txt
```

Para desenvolvimento local, o fallback por `.env` e aceitavel:

```env
GLPI_DB_PASSWORD=glpi_dev_password
MARIADB_PASSWORD=glpi_dev_password
```

Nao versionar arquivos de secrets nem `.env` com senhas reais.

## Volumes persistentes

Persistir, no minimo:

| Volume | Uso |
| --- | --- |
| `glpi_files` | Arquivos enviados, documentos e dados persistentes do GLPI. |
| `glpi_plugins` | Plugins instalados pelo operador. |
| `glpi_config` | Configuracoes geradas pelo GLPI, quando separadas pela imagem. |
| `glpi_marketplace` | Dados do marketplace/plugins, quando separados pela imagem. |
| `mariadb_data` | Dados do MariaDB. |

Na imagem, esses volumes sao montados em `/var/lib/glpi/files`, `/var/lib/glpi/plugins`, `/var/lib/glpi/config` e `/var/lib/glpi/marketplace`. O GLPI continua instalado em `/var/www/html`, com `DocumentRoot` em `/var/www/html/public`.

Exemplo Compose:

```yaml
volumes:
  glpi_files:
  glpi_plugins:
  glpi_config:
  glpi_marketplace:
  mariadb_data:
```

Evite remover volumes em upgrades ou recriacoes de container, salvo quando estiver restaurando um backup validado. Em projetos Compose, o nome fisico do volume pode receber o prefixo do projeto; confira com `docker volume ls`.

## Backup

Faca backup do banco e dos volumes do GLPI juntos, na mesma janela operacional.

Backup do MariaDB:

```bash
mkdir -p backup
docker compose exec -T db mariadb-dump \
  -u "$GLPI_DB_USER" \
  --password="$(cat secrets/glpi_db_password.txt)" \
  "$GLPI_DB_NAME" \
  > backup/glpi-mariadb.sql
```

Backup dos arquivos persistentes:

```bash
docker run --rm \
  -v glpi_files:/data:ro \
  -v "$PWD/backup:/backup" \
  alpine tar -czf /backup/glpi-files.tar.gz -C /data .
```

Se houver volumes separados para configuracao, marketplace ou plugins, inclua cada um deles no mesmo procedimento.

## Restore

Pare a aplicacao antes de restaurar:

```bash
docker compose down
```

Restaure os arquivos persistentes:

```bash
docker run --rm \
  -v glpi_files:/data \
  -v "$PWD/backup:/backup" \
  alpine sh -c 'rm -rf /data/* && tar -xzf /backup/glpi-files.tar.gz -C /data'
```

Suba apenas o MariaDB e restaure o dump:

```bash
docker compose up -d db
docker compose exec -T db mariadb \
  -u "$GLPI_DB_USER" \
  --password="$(cat secrets/glpi_db_password.txt)" \
  "$GLPI_DB_NAME" \
  < backup/glpi-mariadb.sql
```

Depois suba o GLPI:

```bash
docker compose up -d
```

Valide login, inventario de plugins, anexos e tarefas automaticas apos o restore.

## Upgrade de versao

Fluxo recomendado:

1. Leia as notas oficiais da versao alvo do GLPI.
2. Tire backup do MariaDB e dos volumes persistentes.
3. Atualize `GLPI_VERSION` e a tag da imagem.
4. Execute `docker compose pull` ou faca novo build local.
5. Suba o ambiente com `docker compose up -d`.
6. Execute as migracoes exigidas pelo GLPI, quando aplicavel.
7. Valide tela inicial, login, chamados, anexos, plugins e cron.

Exemplo:

```bash
docker compose pull
docker compose up -d
docker compose logs -f glpi
```

Para plugins, confirme compatibilidade antes de atualizar o GLPI em producao.

## Instalar e atualizar plugins

Plugins nao sao garantidos como pre-instalados por esta imagem.

Formas comuns de instalacao:

- Marketplace do GLPI, quando habilitado no ambiente.
- Copia manual do plugin para o diretorio persistente de plugins.
- Imagem derivada que adiciona plugins homologados pela sua organizacao.

Depois de adicionar ou atualizar um plugin:

1. Acesse `Configuracao > Plugins` no GLPI.
2. Instale, habilite ou atualize o plugin pela interface.
3. Verifique compatibilidade com GLPI 10.0.18.
4. Inclua o diretorio do plugin no backup, se ele estiver em volume separado.

Evite atualizar plugins diretamente em producao sem backup e sem teste previo em ambiente equivalente.

## Cron do GLPI

O GLPI depende de tarefas automaticas para acoes recorrentes, notificacoes e manutencao. Em containers, prefira executar o cron via CLI em um servico dedicado ou job do orquestrador.

Exemplo de servico Compose:

```yaml
services:
  glpi-cron:
    image: DOCKERHUB_REPOSITORY:10.0.18
    command: php /var/www/html/front/cron.php --force
    depends_on:
      - glpi
    environment:
      GLPI_START_CRON: "0"
```

Em producao, agende a execucao em intervalo regular, por exemplo a cada minuto, usando cron do host, Kubernetes CronJob, systemd timer ou outro mecanismo do ambiente.

## Healthchecks

O Compose deve expor healthchecks separados para aplicacao e banco.

Exemplo para o MariaDB:

```yaml
healthcheck:
  test: ["CMD-SHELL", "healthcheck.sh --connect --innodb_initialized"]
  interval: 10s
  timeout: 5s
  retries: 5
  start_period: 20s
```

Exemplo para o GLPI:

```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -fsS http://localhost:8080/ || exit 1"]
  interval: 30s
  timeout: 10s
  retries: 5
  start_period: 60s
```

Verifique o estado:

```bash
docker compose ps
docker inspect --format='{{json .State.Health}}' "$(docker compose ps -q glpi)"
```

## Publicacao no Docker Hub

Build e push manual:

```bash
docker login
docker buildx build \
  -f docker/Dockerfile \
  --platform linux/amd64,linux/arm64 \
  --build-arg GLPI_VERSION=10.0.18 \
  -t DOCKERHUB_REPOSITORY:10.0.18 \
  -t DOCKERHUB_REPOSITORY:latest \
  --push .
```

CI/CD recomendado:

- Rodar lint e testes de build em pull requests.
- Publicar a imagem apenas a partir da branch principal ou de tags.
- Usar secrets do GitHub Actions para `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` e `DOCKERHUB_REPOSITORY` no formato `namespace/repositorio`.
- Gerar tags por versao do GLPI e por SHA do commit.
- Nao imprimir secrets em logs.

## Troubleshooting

### O GLPI nao conecta no MariaDB

- Confirme `GLPI_DB_HOST`, `GLPI_DB_PORT`, `GLPI_DB_NAME`, `GLPI_DB_USER` e senha.
- Verifique se `GLPI_DB_NAME`, `GLPI_DB_USER` e `MARIADB_PASSWORD_FILE` ou `MARIADB_PASSWORD` estao alinhados.
- Rode `docker compose logs db`.
- Confirme que o healthcheck do MariaDB esta saudavel.

### Permissao negada em arquivos

- Verifique dono e permissoes dos volumes.
- Confirme se os volumes foram restaurados com UID/GID compativeis com a imagem.
- Evite montar diretorios do host com permissoes restritivas sem ajuste explicito.

### Uploads falham ou arquivos grandes nao entram

- Ajuste os limites de PHP/Apache na imagem ou em uma imagem derivada.
- Verifique limites do proxy reverso, se existir.

### Plugins nao aparecem

- Confirme que o plugin foi copiado para o diretorio correto.
- Verifique compatibilidade com GLPI 10.0.18.
- Acesse a tela de plugins para instalar ou habilitar.
- Confira logs do container `glpi`.

### Cron nao executa tarefas

- Confirme que ha um servico ou agendamento externo chamando `front/cron.php`.
- Verifique se o cron interno esta ativo com `GLPI_START_CRON=1` ou se existe um agendamento externo chamando o script.
- Confira a pagina de tarefas automaticas no GLPI.

### Upgrade incompleto

- Leia os logs da aplicacao.
- Confirme se as migracoes do GLPI foram executadas.
- Restaure backup em ambiente temporario antes de tentar novamente em producao.

## Licenca e obrigacoes GPL

O GLPI e distribuido sob licenca GPL. Ao redistribuir imagens Docker baseadas no GLPI ou contendo o GLPI, mantenha as obrigacoes da GPL:

- Preservar avisos de copyright e licenca.
- Disponibilizar o codigo-fonte correspondente das modificacoes distribuidas, quando aplicavel.
- Nao impor restricoes adicionais incompativeis com a GPL.
- Documentar claramente alteracoes feitas sobre o GLPI original.
- Respeitar tambem as licencas de dependencias, plugins e imagens base.

Consulte a licenca oficial do GLPI e dos componentes empacotados antes de publicar imagens para terceiros.

## Fluxo de contribuicao

Este repositorio segue GitHub Flow:

1. Crie uma branch curta a partir da branch principal.
2. Faca commits pequenos e revisaveis.
3. Abra um pull request.
4. Aguarde CI/CD, revisao e ajustes.
5. Faca merge apos aprovacao.

### Conventional Commits

Use [Conventional Commits](https://www.conventionalcommits.org/) nas mensagens:

```text
feat: adiciona healthcheck do GLPI
fix: corrige permissao do volume de arquivos
docs: documenta restore do MariaDB
ci: publica imagem no Docker Hub
chore: atualiza versao base do GLPI
```
