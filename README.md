# SegIn Web

SegIn Web é uma aplicação Node.js para inventário local de ativos, auditoria, consulta a integrações NetBox/Samba e gestão de usuários internos. A aplicação roda como serviço local e é acessada pelo navegador em `http://localhost:3000`, sem Electron, Tauri, React, Vue, TypeScript ou bundler.

## Decisões técnicas

- **ORM**: Sequelize. Ele permite usar SQLite em desenvolvimento/testes e PostgreSQL/MySQL/MariaDB em produção com a mesma camada de modelos e queries parametrizadas.
- **Frontend**: arquivos estáticos HTML/CSS/JS vanilla. Isso evita dependência de template engine e mantém a interface simples de servir pelo próprio Express.
- **Senha**: PBKDF2-HMAC-SHA256 com salt de 16 bytes e 600.000 iterações.
- **Sessão**: cookie `httpOnly`, `sameSite=lax`, expiração configurada e store persistente via Sequelize. Em produção, use `SESSION_SECRET` longo e HTTPS para habilitar cookie seguro.

## Instalação

Use Node.js LTS compatível com `sqlite3` nativo. Este projeto recomenda Node 20 LTS, conforme `.nvmrc`.

## Rodar com Docker

O projeto inclui um `docker-compose.yml` para subir NetBox, Samba/SMB e o SegIn juntos.

Para a primeira execucao com Docker, use:

```bash
./init-docker.sh
```

No Windows:

```bat
init-docker.bat
```

Os scripts criam o `.env` quando ele ainda nao existe, constroem as imagens, iniciam os containers e aguardam SegIn/NetBox responderem.

```bash
docker compose up --build
```

Serviços expostos:

- SegIn: `http://localhost:3000`
- NetBox: `http://localhost:18080`
- Samba/SMB: `localhost:1445` no host, e `samba:445` dentro da rede Docker

Se alguma porta estiver ocupada, sobrescreva antes de subir:

```bash
SEGIN_PORT=3001 NETBOX_PORT=18081 SAMBA_PORT=2445 docker compose up --build
```

Credenciais de desenvolvimento:

- SegIn: usuário `admin`, senha `admin123`
- NetBox: usuário `admin`, senha `admin123`
- Token NetBox: `0123456789abcdef0123456789abcdef01234567`
- Samba: usuário `segin_smb`, senha `segin123`, share `segin`

O container do SegIn já recebe estas configurações:

```env
NETBOX_URL=http://netbox:8080
NETBOX_TOKEN=nbt_seginweb0001.0123456789abcdef0123456789abcdef01234567
SAMBA_HOST=samba
SAMBA_USERNAME=segin_smb
SAMBA_PASSWORD=segin123
SESSION_SECURE_COOKIE=false
```

Para parar:

```bash
docker compose down
```

Para apagar também os volumes e começar do zero:

```bash
docker compose down -v
```

Para primeira execução, use o script da sua plataforma:

```bash
./primeira-vez.sh
```

No Windows:

```bat
primeira-vez.bat
```

Esses scripts criam o `.env`, instalam dependências, inicializam o banco, criam um administrador e iniciam o servidor.

## Configurar Samba/SMB de teste

Para preparar um compartilhamento Samba/SMB para o SegIn consultar:

```bash
./configurar-samba.sh
```

No Windows, execute o Prompt de Comando como Administrador:

```bat
configurar-samba.bat
```

No Linux o script instala/configura Samba quando possível, cria um share e um usuário Samba local. No Windows ele configura um compartilhamento SMB nativo, equivalente para testes do SegIn. Ambos podem atualizar o `.env` com `SAMBA_HOST`, `SAMBA_USERNAME` e `SAMBA_PASSWORD`.

Fluxo manual equivalente:

```bash
nvm use
npm install
cp .env.example .env
npm run init-db
node src/cli.js create-admin --username admin --email admin@local --password "troque-esta-senha"
npm start
```

Depois acesse `http://localhost:3000`.

Para produção, configure `SEGIN_DB_URL` para PostgreSQL ou MySQL/MariaDB, por exemplo:

```env
SEGIN_DB_URL=postgres://segin_app:senha@localhost:5432/segin
```

SQLite fica como padrão apenas para desenvolvimento e demonstração.

## CLI

```bash
npm run init-db
node src/cli.js create-admin --username admin --email admin@local --password "senha-segura"
node src/cli.js create-demo-data
node src/cli.js sync-netbox
node src/cli.js list-samba-shares
npm run status
```

## Configuração

As variáveis principais ficam em `.env`:

- `SESSION_SECRET`: segredo longo e aleatório da sessão.
- `SEGIN_DB_URL`: conexão do banco.
- `NETBOX_URL`, `NETBOX_TOKEN`, `NETBOX_TOKEN_SCHEME`: integração NetBox.
- `SAMBA_HOST`, `SAMBA_USERNAME`, `SAMBA_PASSWORD`, `SAMBA_WORKGROUP`: integração Samba.

Mantenha `.env` com permissão restrita (`chmod 600 .env`) e nunca versione credenciais.

## Checklist de segurança

- Senhas internas com PBKDF2-HMAC-SHA256, salt único e comparação em tempo constante.
- Auditoria com hash encadeado e verificação pela tela de Auditoria.
- RBAC validado no backend em todas as rotas protegidas.
- CSRF próprio por sessão em rotas `POST`, `PUT` e `DELETE`, incluindo login/logout.
- Sessão com cookie `httpOnly`, `sameSite=lax`, expiração e store Sequelize.
- `helmet` ativo com CSP e cabeçalhos de segurança.
- CORS não é habilitado; frontend e API usam a mesma origem.
- Queries via Sequelize, sem SQL concatenado manualmente.
- Frontend renderiza dados dinâmicos com `textContent`/DOM, evitando `innerHTML` com dados da API.
- Samba usa `execFile` com lista de argumentos e `shell:false`.
- Senha Samba vai por arquivo temporário de credenciais com permissão `0600`, removido ao final.
- Entradas de IP, MAC, share e caminho SMB são validadas.
- Erros internos retornam mensagem genérica ao cliente e detalhes ficam no log do servidor.

## Limites funcionais

O SegIn é uma camada de governança, visualização e auditoria. Ele não substitui NetBox, Samba, SIEM, EDR ou NMS, e não faz monitoramento de rede em tempo real.
