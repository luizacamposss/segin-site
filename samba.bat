@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0"

echo ========================================
echo  SegIn Web - configurar SMB Windows
echo ========================================
echo.
echo Este script configura compartilhamento SMB nativo do Windows.
echo Execute como Administrador.
echo.

net session >nul 2>nul
if errorlevel 1 (
  echo ERRO: abra o Prompt de Comando como Administrador.
  exit /b 1
)

set "SHARE_NAME="
set /p "SHARE_NAME=Nome do share [segin]: "
if "%SHARE_NAME%"=="" set "SHARE_NAME=segin"

powershell -NoProfile -Command "if ($env:SHARE_NAME -notmatch '^[A-Za-z0-9_.\-$]+$') { exit 1 }"
if errorlevel 1 (
  echo ERRO: nome de share invalido. Use letras, numeros, _, ., - ou $.
  exit /b 1
)

set "SHARE_PATH="
set /p "SHARE_PATH=Diretorio compartilhado [C:\SegInSamba]: "
if "%SHARE_PATH%"=="" set "SHARE_PATH=C:\SegInSamba"

set "SMB_USER="
set /p "SMB_USER=Usuario local SMB [segin_smb]: "
if "%SMB_USER%"=="" set "SMB_USER=segin_smb"

powershell -NoProfile -Command "if ($env:SMB_USER -notmatch '^[A-Za-z_][A-Za-z0-9_.-]*$') { exit 1 }"
if errorlevel 1 (
  echo ERRO: usuario invalido.
  exit /b 1
)

:password_prompt
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "$p=Read-Host 'Senha SMB (minimo 6 caracteres)' -AsSecureString; $b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($p); try {[Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)} finally {[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)}"`) do set "SMB_PASSWORD=%%p"
if "%SMB_PASSWORD%"=="" (
  echo A senha precisa ter pelo menos 6 caracteres.
  goto password_prompt
)
powershell -NoProfile -Command "if ($env:SMB_PASSWORD.Length -lt 6) { exit 1 }"
if errorlevel 1 (
  echo A senha precisa ter pelo menos 6 caracteres.
  goto password_prompt
)

echo.
echo Criando diretorio e usuario local, se necessario...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$share=$env:SHARE_NAME; $path=$env:SHARE_PATH; $user=$env:SMB_USER; $pass=$env:SMB_PASSWORD;" ^
  "New-Item -ItemType Directory -Path $path -Force | Out-Null;" ^
  "if (-not (Get-LocalUser -Name $user -ErrorAction SilentlyContinue)) {" ^
  "  $secure=ConvertTo-SecureString $pass -AsPlainText -Force;" ^
  "  New-LocalUser -Name $user -Password $secure -FullName 'Usuario SMB do SegIn' -Description 'Usuario local para compartilhamento SMB do SegIn' | Out-Null;" ^
  "}" ^
  "$acl=Get-Acl $path;" ^
  "$rule=New-Object System.Security.AccessControl.FileSystemAccessRule($user,'Modify','ContainerInherit,ObjectInherit','None','Allow');" ^
  "$acl.SetAccessRule($rule); Set-Acl -Path $path -AclObject $acl;" ^
  "if (Get-SmbShare -Name $share -ErrorAction SilentlyContinue) { Remove-SmbShare -Name $share -Force }" ^
  "New-SmbShare -Name $share -Path $path -FullAccess $user -Description 'Share usado pelo SegIn' | Out-Null;" ^
  "Grant-SmbShareAccess -Name $share -AccountName $user -AccessRight Full -Force | Out-Null;" ^
  "try { Enable-NetFirewallRule -DisplayGroup 'File and Printer Sharing' | Out-Null } catch {}"
if errorlevel 1 (
  echo ERRO: falha ao configurar SMB no Windows.
  exit /b 1
)

for /f "usebackq delims=" %%h in (`powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown'} | Select-Object -First 1 -ExpandProperty IPAddress)"`) do set "HOST_NAME=%%h"
if "%HOST_NAME%"=="" set "HOST_NAME=localhost"

echo.
set "UPDATE_ENV="
set /p "UPDATE_ENV=Atualizar .env do SegIn com esse SMB? [S/n]: "
if "%UPDATE_ENV%"=="" set "UPDATE_ENV=S"
if /I "%UPDATE_ENV%"=="S" goto update_env
if /I "%UPDATE_ENV%"=="Y" goto update_env
goto done

:update_env
if not exist ".env" (
  if exist ".env.example" (
    copy ".env.example" ".env" >nul
  ) else (
    type nul > ".env"
  )
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$path='.env'; $data=@{}; if (Test-Path $path) { Get-Content $path | ForEach-Object { if ($_ -match '^([^=]+)=(.*)$') { $data[$matches[1]]=$matches[2] } } }" ^
  "$data['SAMBA_HOST']=$env:HOST_NAME; $data['SAMBA_USERNAME']=$env:SMB_USER; $data['SAMBA_PASSWORD']=$env:SMB_PASSWORD; $data['SAMBA_WORKGROUP']='';" ^
  "$order=@('NODE_ENV','PORT','SESSION_SECRET','SEGIN_DB_URL','NETBOX_URL','NETBOX_TOKEN','NETBOX_TOKEN_SCHEME','SAMBA_HOST','SAMBA_USERNAME','SAMBA_PASSWORD','SAMBA_WORKGROUP');" ^
  "$lines=New-Object System.Collections.Generic.List[string]; foreach ($k in $order) { if ($data.ContainsKey($k)) { $lines.Add($k + '=' + $data[$k]); $data.Remove($k) } } foreach ($k in $data.Keys) { $lines.Add($k + '=' + $data[$k]) } Set-Content -Path $path -Value $lines -Encoding ascii;"
echo .env atualizado.

:done
echo.
echo SMB configurado.
echo Host: %HOST_NAME%
echo Share: %SHARE_NAME%
echo Caminho: %SHARE_PATH%
echo Usuario: %SMB_USER%
echo.
echo Teste manual no Windows Explorer:
echo \\%HOST_NAME%\%SHARE_NAME%

set "SMB_PASSWORD="
endlocal
