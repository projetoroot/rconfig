#!/usr/bin/env bash

#########################################################################################################
# rConfig V8 Core - Instalador automático
#
# Observação importante: a documentação oficial do rConfig já oferece um instalador 
# de dependências para Ubuntu 22.04+, então este script do Projeto Root está essencialmente 
# criando uma instalação automatizada e reproduzível específica para Ubuntu 26.04 + PHP 8.4, 
# em vez de simplesmente chamar o instalador oficial.
#
# Autor: Diego Costa (@diegocostaroot) / Projeto Root (youtube.com/projetoroot)         
# Versão: 1.0                                                                           
# 2026                                                                                  
# Projeto Root
# https://wiki.projetoroot.com.br
#
# Compatibilidade:
#   VM / Bare metal
#   Ubuntu 26.04 LTS
#
# Stack:
#   PHP 8.4
#   Apache 2.4 + mod_php
#   MariaDB
#   Redis
#   Supervisor
#   Composer 2
#
# Install:
#   chmod +x install-rconfig-ubuntu.sh
#   ./install-rconfig-ubuntu.sh 
#
# O script não assume:
#   - IP
#   - hostname
#   - domínio
#   - senha
#   - interface de rede
#
#########################################################################################################

set -Eeuo pipefail

#########################################################################################################
# CONFIGURAÇÕES
#########################################################################################################

RCONFIG_DIR="/var/www/html/rconfig"
RCONFIG_REPO="https://github.com/rconfig/rconfig.git"

PHP_VERSION="8.4"

DB_NAME="rconfig"
DB_USER="rconfig_user"

VHOST_FILE="/etc/apache2/sites-available/rconfig-vhost.conf"
VHOST_LINK="/etc/apache2/sites-enabled/rconfig-vhost.conf"

SUPERVISOR_FILE="/etc/supervisor/conf.d/rconfig-horizon.conf"

#########################################################################################################
# CORES
#########################################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

#########################################################################################################
# FUNÇÕES
#########################################################################################################

log() {
    echo -e "${GREEN}[OK]${NC} $1"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERRO]${NC} $1"
}

die() {
    error "$1"
    exit 1
}

trap 'error "Falha na linha ${LINENO}. Instalação interrompida."' ERR

#########################################################################################################
# ROOT
#########################################################################################################

if [ "${EUID}" -ne 0 ]; then
    die "Execute o script como root ou com sudo."
fi

#########################################################################################################
# DETECTAR SISTEMA
#########################################################################################################

if [ ! -f /etc/os-release ]; then
    die "Não foi possível identificar o sistema operacional."
fi

source /etc/os-release

if [ "${ID}" != "ubuntu" ]; then
    die "Sistema não suportado. Este instalador requer Ubuntu 26.04."
fi

if [ "${VERSION_ID}" != "26.04" ]; then
    die "Versão não suportada: Ubuntu ${VERSION_ID}. Este instalador requer Ubuntu 26.04."
fi

#########################################################################################################
# ARQUITETURA
#########################################################################################################

ARCH="$(dpkg --print-architecture)"

case "${ARCH}" in
    amd64|arm64)
        ;;
    *)
        die "Arquitetura não suportada: ${ARCH}"
        ;;
esac

#########################################################################################################
# DETECTAR IP PRINCIPAL
#########################################################################################################

PRIMARY_IP="$(ip -4 route get 1.1.1.1 2>/dev/null \
    | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"

if [ -z "${PRIMARY_IP}" ]; then
    PRIMARY_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi

if [ -z "${PRIMARY_IP}" ]; then
    die "Não foi possível detectar o endereço IPv4 principal."
fi

#########################################################################################################
# DETECTAR HOSTNAME
#########################################################################################################

CURRENT_HOSTNAME="$(hostname -f 2>/dev/null || hostname)"

#########################################################################################################
# APRESENTAÇÃO
#########################################################################################################

clear

echo
echo "=============================================================="
echo "              rConfig V8 Core Installer"
echo "                    Projeto Root"
echo "=============================================================="
echo
echo "Sistema       : Ubuntu ${VERSION_ID}"
echo "Arquitetura   : ${ARCH}"
echo "IP detectado  : ${PRIMARY_IP}"
echo "Hostname      : ${CURRENT_HOSTNAME}"
echo "PHP           : ${PHP_VERSION}"
echo "Diretório     : ${RCONFIG_DIR}"
echo
echo "=============================================================="
echo

#########################################################################################################
# URL DA APLICAÇÃO
#########################################################################################################

echo
echo "Como deseja acessar o rConfig?"
echo
echo "1) Usar o IP detectado: ${PRIMARY_IP}"
echo "2) Informar um hostname/domínio"
echo

read -r -p "Opção [1]: " URL_OPTION
URL_OPTION="${URL_OPTION:-1}"

case "${URL_OPTION}" in

    1)
        APP_HOST="${PRIMARY_IP}"
        ;;

    2)
        read -r -p "Hostname/domínio do rConfig: " APP_HOST

        if [ -z "${APP_HOST}" ]; then
            die "Hostname/domínio não pode ser vazio."
        fi
        ;;

    *)
        die "Opção inválida."
        ;;

esac

APP_URL="http://${APP_HOST}"

#########################################################################################################
# BANCO
#########################################################################################################

echo
echo "Configuração do banco de dados"
echo

read -r -p "Nome do banco [${DB_NAME}]: " INPUT_DB_NAME
DB_NAME="${INPUT_DB_NAME:-${DB_NAME}}"

read -r -p "Usuário do banco [${DB_USER}]: " INPUT_DB_USER
DB_USER="${INPUT_DB_USER:-${DB_USER}}"

#########################################################################################################
# GERAR SENHA
#########################################################################################################

DB_PASSWORD="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)"

if [ "${#DB_PASSWORD}" -lt 24 ]; then
    die "Não foi possível gerar uma senha segura para o banco."
fi

#########################################################################################################
# CONFIRMAÇÃO
#########################################################################################################

echo
echo "=============================================================="
echo "Resumo da instalação"
echo "=============================================================="
echo
echo "Ubuntu        : ${VERSION_ID}"
echo "Arquitetura   : ${ARCH}"
echo "IP detectado  : ${PRIMARY_IP}"
echo "URL rConfig   : ${APP_URL}"
echo "Diretório     : ${RCONFIG_DIR}"
echo "Banco         : ${DB_NAME}"
echo "Usuário DB    : ${DB_USER}"
echo
echo "A senha do banco será gerada automaticamente."
echo
echo "=============================================================="
echo

read -r -p "Continuar com a instalação? [s/N]: " CONFIRM

case "${CONFIRM}" in
    s|S|sim|SIM|Sim)
        ;;
    *)
        echo "Instalação cancelada."
        exit 0
        ;;
esac

#########################################################################################################
# APT
#########################################################################################################

export DEBIAN_FRONTEND=noninteractive

info "Atualizando repositórios APT..."

apt-get update

#########################################################################################################
# DEPENDÊNCIAS BÁSICAS
#########################################################################################################

info "Instalando dependências básicas..."

apt-get install -y \
    ca-certificates \
    curl \
    wget \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    git \
    unzip \
    zip \
    rsync \
    acl \
    openssl \
    cron \
    mariadb-server \
    mariadb-client \
    redis-server \
    apache2 \
    supervisor

#########################################################################################################
# REPOSITÓRIO PHP Sury
#########################################################################################################

info "Configurando repositório PHP..."

install -d -m 0755 /etc/apt/keyrings

if [ ! -f /etc/apt/keyrings/sury-php.gpg ]; then

    curl -fsSL https://packages.sury.org/php/apt.gpg \
        | gpg --dearmor \
        > /etc/apt/keyrings/sury-php.gpg

    chmod 0644 /etc/apt/keyrings/sury-php.gpg

fi

cat > /etc/apt/sources.list.d/php-sury.list <<EOF
deb [signed-by=/etc/apt/keyrings/sury-php.gpg] https://packages.sury.org/php/ ${VERSION_CODENAME} main
EOF

apt-get update

#########################################################################################################
# PHP 8.4
#########################################################################################################

info "Instalando PHP ${PHP_VERSION}..."

apt-get install -y \
    php8.4 \
    php8.4-cli \
    php8.4-common \
    php8.4-curl \
    php8.4-gd \
    php8.4-gmp \
    php8.4-ldap \
    php8.4-mbstring \
    php8.4-mysql \
    php8.4-readline \
    php8.4-snmp \
    php8.4-xml \
    php8.4-zip \
    php8.4-bcmath \
    php8.4-intl \
    libapache2-mod-php8.4

#########################################################################################################
# PHP 8.4 COMO PADRÃO
#########################################################################################################

info "Configurando PHP 8.4 como versão padrão..."

update-alternatives --install \
    /usr/bin/php \
    php \
    /usr/bin/php8.4 \
    840

update-alternatives --set php /usr/bin/php8.4

#########################################################################################################
# APACHE PHP
#########################################################################################################

info "Configurando PHP 8.4 no Apache..."

if [ -e /etc/apache2/mods-enabled/php8.5.load ]; then
    a2dismod php8.5 || true
fi

if [ -e /etc/apache2/mods-enabled/php8.5.conf ]; then
    a2dismod php8.5 || true
fi

a2enmod php8.4
a2enmod rewrite
a2enmod headers
a2enmod expires

#########################################################################################################
# PHP.INI
#########################################################################################################

PHP_APACHE_INI="/etc/php/${PHP_VERSION}/apache2/php.ini"
PHP_CLI_INI="/etc/php/${PHP_VERSION}/cli/php.ini"

info "Configurando PHP..."

for PHP_INI in "${PHP_APACHE_INI}" "${PHP_CLI_INI}"; do

    if [ -f "${PHP_INI}" ]; then

        sed -i 's/^memory_limit = .*/memory_limit = 512M/' "${PHP_INI}"
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' "${PHP_INI}"
        sed -i 's/^post_max_size = .*/post_max_size = 100M/' "${PHP_INI}"
        sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "${PHP_INI}"
        sed -i 's/^max_input_time = .*/max_input_time = 300/' "${PHP_INI}"

    fi

done

#########################################################################################################
# COMPOSER
#########################################################################################################

info "Instalando Composer..."

if command -v composer >/dev/null 2>&1; then

    composer self-update --2 || true

else

    curl -fsSL \
        https://getcomposer.org/installer \
        -o /tmp/composer-setup.php

    php8.4 /tmp/composer-setup.php \
        --install-dir=/usr/local/bin \
        --filename=composer

    rm -f /tmp/composer-setup.php

fi

#########################################################################################################
# SERVIÇOS
#########################################################################################################

info "Habilitando serviços..."

systemctl enable --now mariadb.service
systemctl enable --now redis-server.service
systemctl enable --now supervisor.service
systemctl enable --now apache2.service
systemctl enable --now cron.service

#########################################################################################################
# TESTE PHP
#########################################################################################################

PHP_CURRENT="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"

if [ "${PHP_CURRENT}" != "8.4" ]; then
    die "PHP 8.4 não está ativo. Versão detectada: ${PHP_CURRENT}"
fi

log "PHP ${PHP_CURRENT} confirmado."

#########################################################################################################
# MARIA DB
#########################################################################################################

info "Configurando MariaDB..."

mysql <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost'
    IDENTIFIED BY '${DB_PASSWORD}';

ALTER USER '${DB_USER}'@'localhost'
    IDENTIFIED BY '${DB_PASSWORD}';

GRANT ALL PRIVILEGES
    ON \`${DB_NAME}\`.*
    TO '${DB_USER}'@'localhost';

FLUSH PRIVILEGES;
EOF

#########################################################################################################
# TESTE BANCO
#########################################################################################################

info "Testando conexão com MariaDB..."

MYSQL_PWD="${DB_PASSWORD}" \
mysql \
    -u "${DB_USER}" \
    -h 127.0.0.1 \
    "${DB_NAME}" \
    -e "SELECT VERSION();" >/dev/null

log "MariaDB funcionando."

#########################################################################################################
# RCONFIG
#########################################################################################################

if [ -d "${RCONFIG_DIR}/.git" ]; then

    warn "rConfig já existe em ${RCONFIG_DIR}."

else

    if [ -d "${RCONFIG_DIR}" ] && \
       [ "$(find "${RCONFIG_DIR}" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]; then

        die "${RCONFIG_DIR} existe e não está vazio."

    fi

    info "Clonando rConfig V8 Core..."

    mkdir -p "$(dirname "${RCONFIG_DIR}")"

    git clone \
        "${RCONFIG_REPO}" \
        "${RCONFIG_DIR}"

fi

cd "${RCONFIG_DIR}"

#########################################################################################################
# .ENV
#########################################################################################################

info "Configurando ambiente do rConfig..."

if [ ! -f .env ]; then
    cp .env.example .env
fi

#########################################################################################################
# ESCAPAR SENHA PARA .ENV
#########################################################################################################

ENV_DB_PASSWORD="$(printf '%s' "${DB_PASSWORD}" | sed 's/[&/\]/\\&/g')"

#########################################################################################################
# APP_URL
#########################################################################################################

if grep -q '^APP_URL=' .env; then
    sed -i "s|^APP_URL=.*|APP_URL=\"${APP_URL}\"|" .env
else
    echo "APP_URL=\"${APP_URL}\"" >> .env
fi

#########################################################################################################
# APP PATH
#########################################################################################################

if grep -q '^APP_DIR_PATH=' .env; then
    sed -i "s|^APP_DIR_PATH=.*|APP_DIR_PATH=${RCONFIG_DIR}|" .env
else
    echo "APP_DIR_PATH=${RCONFIG_DIR}" >> .env
fi

#########################################################################################################
# DATABASE
#########################################################################################################

sed -i "s|^DB_HOST=.*|DB_HOST=127.0.0.1|" .env
sed -i "s|^DB_PORT=.*|DB_PORT=3306|" .env
sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|" .env
sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${DB_USER}|" .env
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${ENV_DB_PASSWORD}|" .env

#########################################################################################################
# REDIS
#########################################################################################################

if grep -q '^REDIS_HOST=' .env; then
    sed -i 's|^REDIS_HOST=.*|REDIS_HOST=127.0.0.1|' .env
else
    echo 'REDIS_HOST=127.0.0.1' >> .env
fi

if grep -q '^REDIS_PORT=' .env; then
    sed -i 's|^REDIS_PORT=.*|REDIS_PORT=6379|' .env
else
    echo 'REDIS_PORT=6379' >> .env
fi

#########################################################################################################
# COMPOSER
#########################################################################################################

info "Instalando dependências do rConfig..."

export COMPOSER_ALLOW_SUPERUSER=1

composer self-update --2 || true

composer install \
    --no-dev \
    --prefer-dist \
    --optimize-autoloader \
    --no-interaction

#########################################################################################################
# PERMISSÕES
#########################################################################################################

info "Configurando permissões..."

chown -R www-data:www-data "${RCONFIG_DIR}"

find "${RCONFIG_DIR}" \
    -type d \
    -exec chmod 755 {} \;

find "${RCONFIG_DIR}" \
    -type f \
    -exec chmod 644 {} \;

chmod -R 775 "${RCONFIG_DIR}/storage"
chmod -R 775 "${RCONFIG_DIR}/bootstrap/cache"

#########################################################################################################
# APACHE VHOST
#########################################################################################################

info "Configurando Apache..."

cat > "${VHOST_FILE}" <<EOF
<VirtualHost *:80>

    ServerName ${APP_HOST}

    DocumentRoot ${RCONFIG_DIR}/public

    <Directory ${RCONFIG_DIR}/public>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/rconfig-error.log
    CustomLog \${APACHE_LOG_DIR}/rconfig-access.log combined

</VirtualHost>
EOF

ln -sf "${VHOST_FILE}" "${VHOST_LINK}"

#########################################################################################################
# DESABILITAR SITE DEFAULT
#########################################################################################################

a2dissite 000-default.conf >/dev/null 2>&1 || true

#########################################################################################################
# SERVER NAME GLOBAL
#########################################################################################################

cat > /etc/apache2/conf-available/servername.conf <<EOF
ServerName ${APP_HOST}
EOF

a2enconf servername >/dev/null

#########################################################################################################
# STORAGE LINK
#########################################################################################################

info "Criando link de storage..."

cd "${RCONFIG_DIR}"

if [ ! -L "${RCONFIG_DIR}/public/storage" ]; then
    php artisan storage:link
fi

#########################################################################################################
# INSTALAÇÃO DO RCONFIG
#########################################################################################################

info "Executando instalador do rConfig..."

php artisan v8core:install

#########################################################################################################
# PERMISSÕES FINAIS
#########################################################################################################

chown -R www-data:www-data \
    "${RCONFIG_DIR}/storage" \
    "${RCONFIG_DIR}/bootstrap/cache"

chmod -R 775 \
    "${RCONFIG_DIR}/storage" \
    "${RCONFIG_DIR}/bootstrap/cache"

#########################################################################################################
# LIMPAR CACHE
#########################################################################################################

info "Limpando caches..."

php artisan rconfig:clear-all

#########################################################################################################
# SUPERVISOR
#########################################################################################################

info "Configurando Horizon..."

cat > "${SUPERVISOR_FILE}" <<EOF
[program:rconfig-horizon]

process_name=%(program_name)s

command=/usr/bin/php8.4 ${RCONFIG_DIR}/artisan horizon

directory=${RCONFIG_DIR}

autostart=true
autorestart=true

stopasgroup=true
killasgroup=true

user=www-data

redirect_stderr=true

stdout_logfile=${RCONFIG_DIR}/storage/logs/horizon-supervisor.log
stdout_logfile_maxbytes=20MB
stdout_logfile_backups=5

stopwaitsecs=3600
EOF

#########################################################################################################
# SUPERVISOR
#########################################################################################################

systemctl restart supervisor

sleep 2

supervisorctl reread
supervisorctl update

sleep 2

#########################################################################################################
# APACHE
#########################################################################################################

info "Validando configuração do Apache..."

apache2ctl configtest

systemctl restart apache2

#########################################################################################################
# TESTES
#########################################################################################################

echo
echo "=============================================================="
echo "                    TESTES FINAIS"
echo "=============================================================="
echo

printf "PHP:        "
php -r 'echo PHP_VERSION . PHP_EOL;'

printf "Apache:     "
systemctl is-active apache2

printf "MariaDB:    "
systemctl is-active mariadb

printf "Redis:      "
systemctl is-active redis-server

printf "Supervisor: "
systemctl is-active supervisor

echo
echo "Supervisor:"
supervisorctl status || true

echo
echo "Apache VirtualHosts:"
apache2ctl -S

echo
echo "Teste HTTP local:"

HTTP_STATUS="$(
    curl \
        -s \
        -o /dev/null \
        -w "%{http_code}" \
        --max-time 10 \
        -H "Host: ${APP_HOST}" \
        http://127.0.0.1/ \
        || true
)"

echo "HTTP Status: ${HTTP_STATUS}"

#########################################################################################################
# VERIFICAÇÃO HTTP
#########################################################################################################

case "${HTTP_STATUS}" in
    200|301|302|303|307|308)
        log "Apache/rConfig respondeu corretamente."
        ;;
    000)
        warn "Não foi possível realizar o teste HTTP local."
        ;;
    *)
        warn "O rConfig retornou HTTP ${HTTP_STATUS}."
        warn "Consulte:"
        warn "  /var/log/apache2/rconfig-error.log"
        warn "  ${RCONFIG_DIR}/storage/logs/"
        ;;
esac

#########################################################################################################
# CREDENCIAIS
#########################################################################################################

CREDENTIAL_FILE="/root/rconfig-install-credentials.txt"

cat > "${CREDENTIAL_FILE}" <<EOF
rConfig V8 Core
========================================

URL:
${APP_URL}

IP detectado:
${PRIMARY_IP}

Hostname:
${APP_HOST}

Diretório:
${RCONFIG_DIR}

Banco:
${DB_NAME}

Usuário:
${DB_USER}

Senha do banco:
${DB_PASSWORD}

========================================
Gerado em:
$(date '+%Y-%m-%d %H:%M:%S %z')
========================================
EOF

chmod 600 "${CREDENTIAL_FILE}"

#########################################################################################################
# RESULTADO
#########################################################################################################

echo
echo "==========================================================================="
echo "              INSTALAÇÃO CONCLUÍDA"
echo "                                   by Script https://github.com/projetoroot"
echo " Se puder apoiar nosso trabalho,veja nosso canal no youtube.com/projetoroot"
echo "==========================================================================="
echo
echo "URL:"
echo "  ${APP_URL}"
echo
echo "IP detectado:"
echo "  ${PRIMARY_IP}"
echo
echo "Banco:"
echo "  ${DB_NAME}"
echo
echo "Usuário do banco:"
echo "  ${DB_USER}"
echo
echo "Senha do banco:"
echo "  ${DB_PASSWORD}"
echo
echo "Credenciais também foram salvas em:"
echo "  ${CREDENTIAL_FILE}"
echo
echo "Logs Apache:"
echo "  /var/log/apache2/rconfig-error.log"
echo "  /var/log/apache2/rconfig-access.log"
echo
echo "Logs Laravel:"
echo "  ${RCONFIG_DIR}/storage/logs/"
echo
echo "Supervisor:"
echo "  supervisorctl status"
echo
echo "=============================================================="
echo
echo "ATENÇÃO:"
echo "O rConfig possui credenciais administrativas padrão."
echo "Altere-as imediatamente após o primeiro acesso."
echo
echo "=============================================================="
echo
