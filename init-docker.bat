@echo off
setlocal EnableExtensions

cd /d "%~dp0"

if "%SEGIN_PORT%"=="" set "SEGIN_PORT=3000"
if "%NETBOX_PORT%"=="" set "NETBOX_PORT=18080"

set "SEGIN_URL=http://localhost:%SEGIN_PORT%"
set "NETBOX_URL=http://localhost:%NETBOX_PORT%"
set "NETBOX_TOKEN=nbt_seginweb0001.0123456789abcdef0123456789abcdef01234567"

echo ========================================
echo  SegIn Web - init Docker
echo ========================================
echo.

where docker >nul 2>nul
if errorlevel 1 (
  echo ERRO: Docker nao encontrado. Instale Docker Desktop, abra o Docker e rode este script novamente.
  exit /b 1
)

docker compose version >nul 2>nul
if errorlevel 1 (
  echo ERRO: Docker Compose nao encontrado. Instale ou atualize o Docker Desktop.
  exit /b 1
)

if not exist ".env" (
  if exist ".env.example" (
    echo Criando .env a partir do .env.example...
    copy /Y ".env.example" ".env" >nul
  ) else (
    echo ERRO: .env.example nao encontrado.
    exit /b 1
  )
) else (
  echo .env ja existe; mantendo configuracao atual.
)

echo.
echo Construindo imagens e iniciando containers...
docker compose up --build -d
if errorlevel 1 (
  echo ERRO: docker compose up falhou.
  exit /b 1
)

echo.
echo Status dos containers:
docker compose ps

echo.
echo Primeiro boot do NetBox pode demorar varios minutos por causa das migracoes.

call :wait_url "SegIn" "%SEGIN_URL%" 300 ""
if errorlevel 1 (
  echo ERRO: SegIn nao respondeu a tempo.
  echo Veja os logs com: docker compose logs segin
  exit /b 1
)

call :wait_url "NetBox API" "%NETBOX_URL%/api/dcim/devices/" 1800 "Bearer %NETBOX_TOKEN%"
if errorlevel 1 (
  echo ERRO: NetBox ainda nao respondeu com o token esperado.
  echo Veja os logs com: docker compose logs netbox
  echo Se for uma base antiga quebrada de teste, use: docker compose down -v
  exit /b 1
)

echo.
echo Tudo pronto.
echo SegIn:  %SEGIN_URL%
echo NetBox: %NETBOX_URL%
echo Login SegIn: admin / admin123
echo Login NetBox: admin / admin123
exit /b 0

:wait_url
set "WAIT_NAME=%~1"
set "WAIT_URL=%~2"
set /a "WAIT_MAX=%~3"
set "WAIT_AUTH=%~4"
set /a "WAIT_ELAPSED=0"

echo Aguardando %WAIT_NAME% responder em %WAIT_URL%

:wait_loop
if "%WAIT_AUTH%"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $r=Invoke-WebRequest -Uri '%WAIT_URL%' -UseBasicParsing -TimeoutSec 5; if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>nul
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $h=@{Authorization='%WAIT_AUTH%'}; $r=Invoke-WebRequest -Uri '%WAIT_URL%' -Headers $h -UseBasicParsing -TimeoutSec 5; if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>nul
)

if not errorlevel 1 (
  echo %WAIT_NAME% pronto.
  exit /b 0
)

timeout /t 10 /nobreak >nul
set /a "WAIT_ELAPSED+=10"
if %WAIT_ELAPSED% GEQ %WAIT_MAX% exit /b 1
goto wait_loop
