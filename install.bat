@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
title Traçado - Instalador (Windows)
cd /d "%~dp0"

REM ══════════════════════════════════════════════════════════════════
REM  Traçado — instalador do Windows.
REM
REM  Estratégia: NÃO usa Docker Desktop. Instala o WSL2 (subsistema
REM  Linux do proprio Windows) e, dentro dele, o Docker Engine +
REM  Compose (open source, sem restricao de licenca comercial).
REM  O WSL2 encaminha "localhost" automaticamente, entao o navegador
REM  do Windows acessa https://localhost normalmente.
REM
REM  Basta dar DUPLO CLIQUE neste arquivo.
REM ══════════════════════════════════════════════════════════════════

REM ── Auto-elevacao (UAC): WSL e o repositorio de certificados exigem admin ──
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo  Solicitando privilegios de administrador...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo  ═══════════════════════════════════════════════
echo    Traçado — Instalador (Windows / WSL2)
echo  ═══════════════════════════════════════════════
echo.

REM ── 1. WSL2 presente? ─────────────────────────────────────────────
where wsl >nul 2>&1
if %errorLevel% neq 0 goto :instalar_wsl

wsl --status >nul 2>&1
if %errorLevel% neq 0 goto :instalar_wsl
echo  [1/6] WSL detectado.
goto :checar_distro

:instalar_wsl
echo  [1/6] WSL nao encontrado — instalando (requer reinicializacao)...
echo.
wsl --install --no-launch
if %errorLevel% neq 0 (
    echo.
    echo  ✖ Falha ao instalar o WSL.
    echo.
    echo    Causa mais comum: virtualizacao desabilitada na BIOS/UEFI.
    echo    Habilite "Intel VT-x" ou "AMD-V" e rode este instalador de novo.
    echo.
    pause & exit /b 1
)
echo.
echo  ✓ WSL instalado.
echo.
echo  ═══════════════════════════════════════════════
echo   REINICIE O WINDOWS e execute este instalador
echo   novamente para concluir. O progresso ate aqui
echo   ja esta salvo.
echo  ═══════════════════════════════════════════════
echo.
pause & exit /b 0

:checar_distro
wsl --set-default-version 2 >nul 2>&1

REM ── 2. Distribuicao Ubuntu ────────────────────────────────────────
set DISTRO=Ubuntu
wsl -d %DISTRO% -- true >nul 2>&1
if %errorLevel% equ 0 (
    echo  [2/6] Distribuicao %DISTRO% ja instalada.
) else (
    echo  [2/6] Instalando a distribuicao %DISTRO%...
    wsl --install -d %DISTRO% --no-launch
    if !errorLevel! neq 0 (
        echo  ✖ Nao foi possivel instalar o %DISTRO%.
        pause & exit /b 1
    )
    REM primeira inicializacao cria o sistema de arquivos
    wsl -d %DISTRO% -u root -- true >nul 2>&1
    echo  ✓ %DISTRO% instalado.
)

REM ── 3. systemd (necessario para o servico do Docker subir sozinho) ─
echo  [3/6] Habilitando systemd no WSL...
wsl -d %DISTRO% -u root -- bash -c "grep -q '^systemd=true' /etc/wsl.conf 2>/dev/null || printf '[boot]\nsystemd=true\n' >> /etc/wsl.conf"
wsl --shutdown
timeout /t 3 /nobreak >nul

REM ── 4. Docker Engine + Compose DENTRO do WSL ──────────────────────
echo  [4/6] Verificando o Docker dentro do WSL...
wsl -d %DISTRO% -u root -- bash -c "command -v docker >/dev/null 2>&1"
if %errorLevel% equ 0 (
    echo  ✓ Docker ja instalado no WSL.
) else (
    echo       Instalando o Docker Engine ^(open source, sem licenca comercial^)...
    wsl -d %DISTRO% -u root -- bash -c "curl -fsSL https://get.docker.com | sh"
    if !errorLevel! neq 0 (
        echo  ✖ Falha ao instalar o Docker no WSL. Verifique a conexao com a internet.
        pause & exit /b 1
    )
    echo  ✓ Docker Engine instalado.
)
wsl -d %DISTRO% -u root -- bash -c "systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1; true"

REM ── 5. Copia o projeto para dentro do WSL e instala ───────────────
echo  [5/6] Preparando o Traçado dentro do WSL...
for /f "usebackq delims=" %%i in (`wsl -d %DISTRO% -u root -- wslpath "'%CD%'"`) do set "SRC=%%i"
wsl -d %DISTRO% -u root -- bash -c "mkdir -p /opt/tracado && cp -r '%SRC%/.' /opt/tracado/ 2>/dev/null; cd /opt/tracado && chmod +x install.sh scripts/*.sh 2>/dev/null; true"
echo       Executando a instalacao (pode demorar na primeira vez)...
wsl -d %DISTRO% -u root -- bash -c "cd /opt/tracado && ./install.sh local"
if %errorLevel% neq 0 (
    echo  ✖ A instalacao dentro do WSL falhou. Veja as mensagens acima.
    pause & exit /b 1
)

REM ── 6. Confiar na CA interna (Windows + Firefox) ──────────────────
echo  [6/6] Instalando o certificado da CA interna...
wsl -d %DISTRO% -u root -- bash -c "cd /opt/tracado && docker exec sgsi_caddy sh -c 'cat /data/caddy/pki/authorities/local/root.crt' > /opt/tracado/caddy/Tracado-CA-local.crt 2>/dev/null; true"
wsl -d %DISTRO% -u root -- bash -c "cp /opt/tracado/caddy/Tracado-CA-local.crt '%SRC%/caddy/Tracado-CA-local.crt' 2>/dev/null; true"
if exist "%CD%\caddy\Tracado-CA-local.crt" (
    certutil -addstore -f Root "%CD%\caddy\Tracado-CA-local.crt" >nul 2>&1
    if !errorLevel! equ 0 (
        echo  ✓ CA confiada no Windows ^(Chrome e Edge^).
    ) else (
        echo  ! Nao foi possivel instalar a CA automaticamente.
    )
    REM Firefox usa repositorio proprio: a politica abaixo faz ele
    REM confiar nas CAs do Windows, cobrindo todos os navegadores.
    for %%D in ("%ProgramFiles%\Mozilla Firefox" "%ProgramFiles(x86)%\Mozilla Firefox") do (
        if exist "%%~D" (
            if not exist "%%~D\distribution" mkdir "%%~D\distribution" >nul 2>&1
            > "%%~D\distribution\policies.json" echo {"policies":{"Certificates":{"ImportEnterpriseRoots":true}}}
            echo  ✓ Firefox configurado para usar as CAs do Windows.
        )
    )
) else (
    echo  ! CA nao localizada — o navegador podera exibir aviso de certificado.
)

echo.
echo  ═══════════════════════════════════════════════
echo    ✓ Traçado instalado
echo.
echo    Acesse:  https://localhost
echo.
echo    Feche o navegador POR COMPLETO antes de abrir,
echo    para que ele releia os certificados.
echo  ═══════════════════════════════════════════════
echo.
start "" "https://localhost"
pause
endlocal
