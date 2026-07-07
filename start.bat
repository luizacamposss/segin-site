@echo off
setlocal EnableExtensions

cd /d "%~dp0"

set "APP_URL=http://localhost:3000"

echo ========================================
echo  SegIn Web - primeira execucao
echo ========================================
echo.

where node >nul 2>nul
if errorlevel 1 (
  echo ERRO: Node.js nao encontrado. Instale Node.js 20 LTS ou superior antes de continuar.
  exit /b 1
)

where npm >nul 2>nul
if errorlevel 1 (
  echo ERRO: npm nao encontrado. Instale o npm antes de continuar.
  exit /b 1
)

for /f "usebackq delims=" %%v in (`node -p "Number(process.versions.node.split('.')[0])"`) do set "NODE_MAJOR=%%v"
if %NODE_MAJOR% LSS 20 (
  echo AVISO: Node atual abaixo da versao recomendada. Use Node 20 LTS ou superior.
  echo.
)
if %NODE_MAJOR% GEQ 26 (
  echo AVISO: Node atual muito novo para algumas dependencias nativas. Recomendado: Node 20 LTS ate Node 25.
  echo O sqlite3 pode falhar em versoes muito novas. Se falhar, use Node 20 LTS.
  echo.
)

if not exist ".env" (
  echo Criando .env...
  node -e "const fs=require('fs'),crypto=require('crypto');const secret=crypto.randomBytes(32).toString('hex');fs.writeFileSync('.env',`NODE_ENV=development\nPORT=3000\nSESSION_SECRET=${secret}\nSEGIN_DB_URL=sqlite:./data/segin.sqlite3\n\nNETBOX_URL=\nNETBOX_TOKEN=\nNETBOX_TOKEN_SCHEME=auto\n\nSAMBA_HOST=\nSAMBA_USERNAME=\nSAMBA_PASSWORD=\nSAMBA_WORKGROUP=\n`);"
  echo .env criado.
) else (
  echo .env ja existe; mantendo configuracao atual.
)

echo.
echo Instalando dependencias...
call npm install
if errorlevel 1 (
  echo ERRO: npm install falhou.
  exit /b 1
)

echo.
echo Inicializando banco...
call npm run init-db
if errorlevel 1 (
  echo ERRO: init-db falhou.
  exit /b 1
)

echo.
echo Criacao do usuario administrador
set "ADMIN_USER="
set /p "ADMIN_USER=Usuario admin [admin]: "
if "%ADMIN_USER%"=="" set "ADMIN_USER=admin"

set "ADMIN_EMAIL="
set /p "ADMIN_EMAIL=Email admin [admin@local]: "
if "%ADMIN_EMAIL%"=="" set "ADMIN_EMAIL=admin@local"

:password_prompt
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "$p=Read-Host 'Senha admin (minimo 6 caracteres)' -AsSecureString; $b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($p); try {[Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)} finally {[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)}"`) do set "ADMIN_PASSWORD=%%p"
if "%ADMIN_PASSWORD%"=="" (
  echo A senha precisa ter pelo menos 6 caracteres.
  goto password_prompt
)
powershell -NoProfile -Command "if ($env:ADMIN_PASSWORD.Length -lt 6) { exit 1 }"
if errorlevel 1 (
  echo A senha precisa ter pelo menos 6 caracteres.
  goto password_prompt
)

set "SEGIN_ADMIN_PASSWORD=%ADMIN_PASSWORD%"
node src\cli.js create-admin --username "%ADMIN_USER%" --email "%ADMIN_EMAIL%"
if errorlevel 1 (
  echo ERRO: criacao do admin falhou.
  exit /b 1
)
set "SEGIN_ADMIN_PASSWORD="

echo.
echo Tudo pronto.
echo Acesse: %APP_URL%
echo Login: %ADMIN_USER%
echo.
echo Iniciando servidor...
call npm start
