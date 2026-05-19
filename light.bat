@echo off
setlocal

set COMPOSE_FILE=docker-compose.yml

if "%~1"=="" goto usage

if "%~1"=="up" goto up
if "%~1"=="down" goto down
if "%~1"=="restart" goto restart
if "%~1"=="logs" goto logs
if "%~1"=="ps" goto ps
if "%~1"=="pull" goto pull
if "%~1"=="config" goto config

goto usage


:write_compose
(
echo services:
echo   celestia-light-node-test:
echo     image: ghcr.io/celestiaorg/celestia-node:v0.28.5-mocha
echo     container_name: celestia-light-node-test
echo     restart: unless-stopped
echo     environment:
echo       - NODE_TYPE=light
echo       - P2P_NETWORK=private
echo     volumes:
echo       - ./light:/home/celestia
echo     ports:
echo       - "26762:26658"
echo     entrypoint: ["/bin/bash", "-c"]
echo     command:
echo       - ^|
echo         set -euo pipefail
echo.
echo         if [ ! -f /home/celestia/config.toml ]; then
echo           celestia light init \
echo             --p2p.network private \
echo             --rpc.addr 0.0.0.0
echo         fi
echo.
echo         exec celestia light start \
echo           --p2p.network private \
echo           --rpc.addr 0.0.0.0 \
echo           --rpc.port 26658 \
echo           --core.ip 103.67.203.71 \
echo           --core.port 14090 \
echo           --headers.trusted-peers /ip4/103.67.203.71/tcp/2201/p2p/12D3KooWGKuJauY5bRWpL52Xa9JWBrHp1qdz3vNAFsRQnS7ZZexz \
echo           --p2p.mutual /ip4/103.67.203.71/tcp/2201/p2p/12D3KooWGKuJauY5bRWpL52Xa9JWBrHp1qdz3vNAFsRQnS7ZZexz \
echo           --metrics \
echo           --metrics.endpoint 103.67.203.71:4318 \
echo           --metrics.tls=false
) > "%COMPOSE_FILE%"
exit /b 0


:check_docker
docker compose version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Khong tim thay Docker Compose.
    echo Hay cai Docker Desktop va dam bao lenh "docker compose" chay duoc trong CMD/PowerShell.
    exit /b 1
)
exit /b 0


:up
call :check_docker
if errorlevel 1 exit /b 1

if not exist light mkdir light

call :write_compose

echo Starting Celestia light node...
docker compose -f "%COMPOSE_FILE%" up -d
goto end


:down
call :check_docker
if errorlevel 1 exit /b 1

call :write_compose

echo Stopping Celestia light node...
docker compose -f "%COMPOSE_FILE%" down
goto end


:restart
call :check_docker
if errorlevel 1 exit /b 1

call :write_compose

echo Restarting Celestia light node...
docker compose -f "%COMPOSE_FILE%" down
docker compose -f "%COMPOSE_FILE%" up -d
goto end


:logs
call :check_docker
if errorlevel 1 exit /b 1

call :write_compose

docker compose -f "%COMPOSE_FILE%" logs -f celestia-light-node-test
goto end


:ps
call :check_docker
if errorlevel 1 exit /b 1

call :write_compose

docker compose -f "%COMPOSE_FILE%" ps
goto end


:pull
call :check_docker
if errorlevel 1 exit /b 1

call :write_compose

docker compose -f "%COMPOSE_FILE%" pull
goto end


:config
call :write_compose
type "%COMPOSE_FILE%"
goto end


:usage
echo Usage:
echo   light.bat up        - tao docker-compose.yml va chay node
echo   light.bat down      - dung va xoa container
echo   light.bat restart   - restart node
echo   light.bat logs      - xem logs
echo   light.bat ps        - xem trang thai
echo   light.bat pull      - pull image
echo   light.bat config    - in noi dung docker-compose.yml
exit /b 1


:end
endlocal