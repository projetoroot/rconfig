#!/usr/bin/env bash

#########################################################################################################
# rConfig V8 Core - Instalador automático
#
# Observação importante: a documentação oficial do rConfig já oferece um instalador 
# de dependências para Ubuntu 22.04+, então este script do Projeto Root está essencialmente 
# criando uma instalação automatizada e reproduzível específica para Debian 13 + PHP 8.4, 
# em vez de simplesmente chamar o instalador oficial.
#
# Projeto Root
# https://wiki.projetoroot.com.br
#
# Stack:
#   PHP 8.4
#   Apache 2.4 + mod_php
#   MariaDB
#   Redis
#   Supervisor
#   Composer 2
#
# O script não assume:
#   - IP
#   - hostname
#   - domínio
#   - senha
#   - interface de rede
#
# Requisitos:
#   - Debian 13
#   - Root
#   - Internet
#
# Diretório:
#   /var/www/html/rconfig
#
# Acesso:
#   http://IP_DO_SERVIDOR/
#
#########################################################################################################

set -Eeuo pipefail
export COMPOSER_ALLOW_SUPERUSER=1

# =============================================================================
# VARIÁVEIS DE AMBIENTE / CONFIGURAÇÃO
# =============================================================================

# -----------------------------------------------------------------------------
# rConfig
# -----------------------------------------------------------------------------

RCONFIG_DIR="/var/www/html/rconfig"
RCONFIG_REPO="https://github.com/rconfig/rconfig.git"

# -----------------------------------------------------------------------------
# Banco de dados
# -----------------------------------------------------------------------------

DB_NAME="rconfig"
DB_USER="rconfig_user"

# Deixe vazio para solicitar durante a instalação.
#
# Para instalação automática:
#
# export RCONFIG_DB_PASSWORD='SuaSenha'
#
RCONFIG_DB_PASSWORD=""

# -----------------------------------------------------------------------------
# Web Server
# -----------------------------------------------------------------------------

WEB_USER="www-data"
WEB_GROUP="www-data"

APACHE_SITE="/etc/apache2/sites-available/rconfig.conf"
APACHE_CONFIG_DIR="/etc/apache2"
APACHE_LOG_DIR="/var/log/apache2"

# Utilitários Apache
APACHECTL="/usr/sbin/apache2ctl"
A2ENMOD="/usr/sbin/a2enmod"
A2ENSITE="/usr/sbin/a2ensite"
A2DISSITE="/usr/sbin/a2dissite"
A2ENCONF="/usr/sbin/a2enconf"

# -----------------------------------------------------------------------------
# Supervisor / Laravel Horizon
# -----------------------------------------------------------------------------

SUPERVISOR_DIR="/etc/supervisor/conf.d"
SUPERVISOR_FILE="${SUPERVISOR_DIR}/horizon_supervisor.conf"
SUPERVISOR_SERVICE="supervisor"

HORIZON_SOURCE="${RCONFIG_DIR}/horizon_supervisor.ini"

# -----------------------------------------------------------------------------
# PHP
# -----------------------------------------------------------------------------

PHP_VERSION="8.4"
PHP_BIN="/usr/bin/php"

# -----------------------------------------------------------------------------
# Sistema operacional
# -----------------------------------------------------------------------------

REQUIRED_OS="debian"
REQUIRED_VERSION="13"

# -----------------------------------------------------------------------------
# Rede
# -----------------------------------------------------------------------------

# Deixe vazio para detectar automaticamente.
#
# Exemplo:
# SERVER_IP="192.168.200.175"
#
SERVER_IP=""

# -----------------------------------------------------------------------------
# Serviços
# -----------------------------------------------------------------------------

APACHE_SERVICE="apache2"
MARIADB_SERVICE="mariadb"
REDIS_SERVICE="redis-server"

# -----------------------------------------------------------------------------
# Pacotes opcionais
# -----------------------------------------------------------------------------

INSTALL_QEMU_GUEST_AGENT="yes"
INSTALL_NET_TOOLS="yes"
INSTALL_SUDO="yes"

# =============================================================================
# CORES
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# FUNÇÕES
# =============================================================================

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
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

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# =============================================================================
# TRATAMENTO DE ERROS
# =============================================================================

trap 'error "Falha na linha ${LINENO}. Comando: ${BASH_COMMAND}"' ERR

# =============================================================================
# ROOT
# =============================================================================

if [[ "${EUID}" -ne 0 ]]; then
    die "Execute este script como root."
fi

# =============================================================================
# SISTEMA OPERACIONAL
# =============================================================================

if [[ ! -f /etc/os-release ]]; then
    die "Não foi possível identificar o sistema operacional."
fi

source /etc/os-release

if [[ "${ID}" != "${REQUIRED_OS}" ]]; then
    die "Este instalador foi desenvolvido exclusivamente para Debian 13."
fi

if [[ "${VERSION_ID}" != "${REQUIRED_VERSION}" ]]; then
    die "Versão detectada: Debian ${VERSION_ID}. Este instalador requer Debian 13."
fi

ok "Debian 13 detectado."

# =============================================================================
# VALIDAÇÃO DO SISTEMA
# =============================================================================

if ! command_exists apt-get; then
    die "apt-get não encontrado."
fi

if ! command_exists systemctl; then
    die "systemctl não encontrado."
fi

if [[ ! -x "${PHP_BIN}" ]]; then
    warn "PHP ${PHP_VERSION} ainda não está instalado. Será instalado durante o processo."
fi

# =============================================================================
# CABEÇALHO
# =============================================================================

clear

echo
echo "=============================================================="
echo "              rConfig V8 Core Installer"
echo "                    Projeto Root"
echo "=============================================================="
echo
echo "Sistema       : Debian ${VERSION_ID}"
echo "Arquitetura   : $(dpkg --print-architecture)"
echo "Diretório     : ${RCONFIG_DIR}"
echo "PHP           : ${PHP_VERSION}"
echo "Banco         : ${DB_NAME}"
echo "Usuário DB    : ${DB_USER}"
echo
echo "=============================================================="
echo

# =============================================================================
# IP
# =============================================================================

if [[ -z "${SERVER_IP}" ]]; then
    SERVER_IP="$(hostname -I | awk '{print $1}')"
fi

if [[ -z "${SERVER_IP}" ]]; then
    SERVER_IP="127.0.0.1"
fi

echo
echo "IP detectado/configurado: ${SERVER_IP}"
echo

# =============================================================================
# SENHA DO BANCO
# =============================================================================

if [[ -z "${RCONFIG_DB_PASSWORD}" ]]; then

    while true; do

        read -rsp "Senha do usuário ${DB_USER}: " DB_PASSWORD
        echo

        read -rsp "Confirme a senha: " DB_PASSWORD_CONFIRM
        echo

        if [[ -z "${DB_PASSWORD}" ]]; then
            warn "A senha não pode ser vazia."
            continue
        fi

        if [[ "${DB_PASSWORD}" != "${DB_PASSWORD_CONFIRM}" ]]; then
            warn "As senhas não conferem."
            continue
        fi

        break

    done

else

    DB_PASSWORD="${RCONFIG_DB_PASSWORD}"

fi

# =============================================================================
# CONFIRMAÇÃO
# =============================================================================

echo
echo "=============================================================="
echo "                  RESUMO DA INSTALAÇÃO"
echo "=============================================================="
echo
echo "Sistema       : Debian ${VERSION_ID}"
echo "IP            : ${SERVER_IP}"
echo "rConfig       : ${RCONFIG_DIR}"
echo "PHP           : ${PHP_VERSION}"
echo "Banco         : ${DB_NAME}"
echo "Usuário DB    : ${DB_USER}"
echo "Apache        : ${APACHE_SERVICE}"
echo "MariaDB       : ${MARIADB_SERVICE}"
echo "Redis         : ${REDIS_SERVICE}"
echo "Supervisor    : ${SUPERVISOR_SERVICE}"
echo
echo "=============================================================="
echo

read -rp "Pressione ENTER para continuar ou CTRL+C para cancelar..."

# =============================================================================
# ATUALIZAÇÃO DO SISTEMA
# =============================================================================

log "Atualizando repositórios..."

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get upgrade -y

ok "Sistema atualizado."

# =============================================================================
# PACOTES BASE
# =============================================================================

log "Instalando dependências..."

PACKAGES=(
    apache2
    mariadb-server
    mariadb-client
    redis-server
    supervisor
    git
    curl
    wget
    unzip
    zip
    ca-certificates
    gnupg
    lsb-release
    build-essential
    nodejs
    npm
    libapache2-mod-php8.4
    php8.4
    php8.4-cli
    php8.4-common
    php8.4-mysql
    php8.4-curl
    php8.4-mbstring
    php8.4-xml
    php8.4-zip
    php8.4-bcmath
    php8.4-gd
    php8.4-intl
    php8.4-readline
)

if [[ "${INSTALL_SUDO}" == "yes" ]]; then
    PACKAGES+=(sudo)
fi

if [[ "${INSTALL_NET_TOOLS}" == "yes" ]]; then
    PACKAGES+=(net-tools)
fi

if [[ "${INSTALL_QEMU_GUEST_AGENT}" == "yes" ]]; then
    PACKAGES+=(qemu-guest-agent)
fi

apt-get install -y "${PACKAGES[@]}"

ok "Dependências instaladas."

# =============================================================================
# VALIDAÇÃO DOS UTILITÁRIOS APACHE
# =============================================================================

if [[ ! -x "${A2ENMOD}" ]]; then
    die "a2enmod não encontrado em ${A2ENMOD}."
fi

if [[ ! -x "${A2ENSITE}" ]]; then
    die "a2ensite não encontrado em ${A2ENSITE}."
fi

if [[ ! -x "${A2DISSITE}" ]]; then
    die "a2dissite não encontrado em ${A2DISSITE}."
fi

if [[ ! -x "${A2ENCONF}" ]]; then
    die "a2enconf não encontrado em ${A2ENCONF}."
fi

if [[ ! -x "${APACHECTL}" ]]; then
    die "apache2ctl não encontrado em ${APACHECTL}."
fi

ok "Ferramentas do Apache encontradas."

# =============================================================================
# SERVIÇOS
# =============================================================================

log "Habilitando serviços..."

systemctl enable "${APACHE_SERVICE}"
systemctl enable "${MARIADB_SERVICE}"
systemctl enable "${REDIS_SERVICE}"
systemctl enable "${SUPERVISOR_SERVICE}"

systemctl start "${APACHE_SERVICE}"
systemctl start "${MARIADB_SERVICE}"
systemctl start "${REDIS_SERVICE}"
systemctl start "${SUPERVISOR_SERVICE}"

ok "Serviços iniciados."

# =============================================================================
# APACHE
# =============================================================================

log "Configurando Apache..."

"${A2ENMOD}" rewrite
"${A2ENMOD}" headers
"${A2ENMOD}" env
"${A2ENMOD}" dir
"${A2ENMOD}" mime

# Desabilita o site padrão
"${A2DISSITE}" 000-default.conf >/dev/null 2>&1 || true

cat > "${APACHE_SITE}" <<EOF
<VirtualHost *:80>

    ServerName ${SERVER_IP}

    DocumentRoot ${RCONFIG_DIR}/public

    <Directory ${RCONFIG_DIR}/public>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    DirectoryIndex index.php

    ErrorLog \${APACHE_LOG_DIR}/rconfig_error.log
    CustomLog \${APACHE_LOG_DIR}/rconfig_access.log combined

</VirtualHost>
EOF

"${A2ENSITE}" rconfig.conf

# ServerName global
cat > "${APACHE_CONFIG_DIR}/conf-available/servername.conf" <<EOF
ServerName ${SERVER_IP}
EOF

"${A2ENCONF}" servername

"${APACHECTL}" configtest

systemctl reload "${APACHE_SERVICE}"

ok "Apache configurado."

# =============================================================================
# MARIADB
# =============================================================================

log "Configurando MariaDB..."

systemctl enable "${MARIADB_SERVICE}"
systemctl start "${MARIADB_SERVICE}"

# -----------------------------------------------------------------------------
# Escape de caracteres para SQL
# -----------------------------------------------------------------------------

DB_PASSWORD_SQL="${DB_PASSWORD}"

# Escapa barra invertida
DB_PASSWORD_SQL="${DB_PASSWORD_SQL//\\/\\\\}"

# Escapa aspas simples
DB_PASSWORD_SQL="${DB_PASSWORD_SQL//\'/\'\'}"

# -----------------------------------------------------------------------------
# Criação do banco
# -----------------------------------------------------------------------------

mysql <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;
EOF

# -----------------------------------------------------------------------------
# Criação/configuração do usuário
# -----------------------------------------------------------------------------

mysql <<EOF
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost'
IDENTIFIED BY '${DB_PASSWORD_SQL}';

ALTER USER '${DB_USER}'@'localhost'
IDENTIFIED BY '${DB_PASSWORD_SQL}';

GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.*
TO '${DB_USER}'@'localhost';

FLUSH PRIVILEGES;
EOF

ok "Banco de dados configurado."

# =============================================================================
# TESTE DO BANCO
# =============================================================================

log "Testando conexão com MariaDB..."

MYSQL_PWD="${DB_PASSWORD}" \
mysql \
    -u "${DB_USER}" \
    -h localhost \
    "${DB_NAME}" \
    -e "SELECT 1;" >/dev/null

ok "Conexão com MariaDB funcionando."

# =============================================================================
# REDIS
# =============================================================================

log "Verificando Redis..."

systemctl enable "${REDIS_SERVICE}"
systemctl restart "${REDIS_SERVICE}"

if systemctl is-active --quiet "${REDIS_SERVICE}"; then
    ok "Redis está RUNNING."
else
    die "Redis não iniciou corretamente."
fi

# =============================================================================
# COMPOSER
# =============================================================================

if ! command_exists composer; then

    log "Instalando Composer..."

    cd /tmp

    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"

    php composer-setup.php \
        --install-dir=/usr/local/bin \
        --filename=composer

    rm -f composer-setup.php

fi

composer --version

ok "Composer disponível."

# =============================================================================
# CLONE / ATUALIZAÇÃO DO RCONFIG
# =============================================================================

if [[ ! -d "${RCONFIG_DIR}/.git" ]]; then

    log "Clonando rConfig..."

    mkdir -p "$(dirname "${RCONFIG_DIR}")"

    git clone "${RCONFIG_REPO}" "${RCONFIG_DIR}"

else

    log "rConfig já existe. Atualizando repositório..."

    cd "${RCONFIG_DIR}"

    git config --global --add safe.directory "${RCONFIG_DIR}"

    git fetch --all

    git pull --ff-only || warn "Não foi possível atualizar automaticamente."

fi

cd "${RCONFIG_DIR}"

ok "Código do rConfig disponível."

# =============================================================================
# ENV
# =============================================================================

if [[ ! -f "${RCONFIG_DIR}/.env" ]]; then

    log "Criando .env..."

    cp .env.example .env

fi

# =============================================================================
# CONFIGURAÇÃO DO .ENV
# =============================================================================

log "Configurando ambiente..."

set_env() {

    local KEY="$1"
    local VALUE="$2"

    if grep -q "^${KEY}=" .env; then
        sed -i "s|^${KEY}=.*|${KEY}=${VALUE}|" .env
    else
        echo "${KEY}=${VALUE}" >> .env
    fi
}

set_env "APP_URL" "\"http://${SERVER_IP}\""
set_env "APP_DIR_PATH" "${RCONFIG_DIR}"
set_env "DB_CONNECTION" "mysql"
set_env "DB_HOST" "localhost"
set_env "DB_PORT" "3306"
set_env "DB_DATABASE" "${DB_NAME}"
set_env "DB_USERNAME" "${DB_USER}"

# IMPORTANTE:
# Aspas evitam problemas com caracteres especiais como #.
sed -i '/^DB_PASSWORD=/d' .env
echo "DB_PASSWORD=\"${DB_PASSWORD}\"" >> .env

ok ".env configurado."

# =============================================================================
# COMPOSER
# =============================================================================

log "Instalando dependências PHP..."


composer self-update --2 >/dev/null 2>&1 || true

if composer install \
    --no-dev \
    --optimize-autoloader \
    --no-interaction; then

    ok "Dependências PHP instaladas."

else

    error "Composer encontrou um erro durante a instalação."
    echo
    echo "Verifique os detalhes executando:"
    echo
    echo "  cd ${RCONFIG_DIR}"
    echo "  composer install --no-dev --optimize-autoloader -vvv"
    echo

    exit 1

fi

# =============================================================================
# PERMISSÕES
# =============================================================================

log "Configurando permissões..."

chown -R "${WEB_USER}:${WEB_GROUP}" \
    storage \
    bootstrap/cache

chmod -R 775 \
    storage \
    bootstrap/cache

ok "Permissões configuradas."

# =============================================================================
# ARTISAN
# =============================================================================

log "Limpando configuração Laravel..."

"${PHP_BIN}" artisan config:clear
"${PHP_BIN}" artisan cache:clear

# =============================================================================
# INSTALAÇÃO DO RCONFIG
# =============================================================================

log "Executando instalador do rConfig..."

"${PHP_BIN}" artisan v8core:install

ok "Instalação do rConfig concluída."

# =============================================================================
# SUPERVISOR / HORIZON
# =============================================================================

log "Configurando Supervisor..."

mkdir -p "${SUPERVISOR_DIR}"

HORIZON_SOURCE="${RCONFIG_DIR}/horizon_supervisor.ini"

if [[ ! -f "${HORIZON_SOURCE}" ]]; then
    die "Arquivo horizon_supervisor.ini não encontrado."
fi

# Substitui PWD pelo diretório real caso ainda exista
sed -i "s+PWD+${RCONFIG_DIR}+g" "${HORIZON_SOURCE}"

cat > "${SUPERVISOR_FILE}" <<EOF
[program:horizon]

process_name=%(program_name)s

command=${PHP_BIN} ${RCONFIG_DIR}/artisan horizon

autostart=true
autorestart=true

user=root

redirect_stderr=true

stdout_logfile=${RCONFIG_DIR}/storage/logs/horizon.log

stopwaitsecs=3600
EOF

supervisorctl reread
supervisorctl update

systemctl restart "${SUPERVISOR_SERVICE}"

# Aguarda o Horizon iniciar
log "Aguardando Laravel Horizon..."

HORIZON_OK="no"

for i in {1..10}; do

    if supervisorctl status horizon 2>/dev/null | grep -q "RUNNING"; then
        HORIZON_OK="yes"
        break
    fi

    sleep 2

done

if [[ "${HORIZON_OK}" == "yes" ]]; then

    ok "Laravel Horizon está RUNNING."

else

    warn "Laravel Horizon ainda não está RUNNING."

    echo
    echo "Status do Supervisor:"
    supervisorctl status || true

    echo
    echo "Últimas linhas do log do Horizon:"
    tail -50 "${RCONFIG_DIR}/storage/logs/horizon.log" 2>/dev/null || true

fi

# =============================================================================
# PERMISSÕES FINAIS
# =============================================================================

log "Aplicando permissões finais..."

chown -R "${WEB_USER}:${WEB_GROUP}" \
    storage \
    bootstrap/cache

chmod -R 775 \
    storage \
    bootstrap/cache

# =============================================================================
# LIMPEZA FINAL
# =============================================================================

systemctl reload "${APACHE_SERVICE}"
systemctl restart "${SUPERVISOR_SERVICE}"

# Aguarda o Horizon iniciar
log "Aguardando Laravel Horizon..."

HORIZON_OK="no"

for i in {1..10}; do

    if supervisorctl status horizon 2>/dev/null | grep -q "RUNNING"; then
        HORIZON_OK="yes"
        break
    fi

    sleep 2

done

if [[ "${HORIZON_OK}" == "yes" ]]; then

    ok "Laravel Horizon está RUNNING."

else

    warn "Laravel Horizon ainda não está RUNNING."

    echo
    echo "Status do Supervisor:"
    supervisorctl status || true

    echo
    echo "Últimas linhas do log do Horizon:"
    tail -50 "${RCONFIG_DIR}/storage/logs/horizon.log" 2>/dev/null || true

fi

# =============================================================================
# TESTES
# =============================================================================

echo
echo "=============================================================="
echo "                    VERIFICAÇÃO FINAL"
echo "=============================================================="
echo

echo -n "Apache:     "
if systemctl is-active --quiet "${APACHE_SERVICE}"; then
    echo -e "${GREEN}RUNNING${NC}"
else
    echo -e "${RED}ERRO${NC}"
fi

echo -n "MariaDB:    "
if systemctl is-active --quiet "${MARIADB_SERVICE}"; then
    echo -e "${GREEN}RUNNING${NC}"
else
    echo -e "${RED}ERRO${NC}"
fi

echo -n "Redis:      "
if systemctl is-active --quiet "${REDIS_SERVICE}"; then
    echo -e "${GREEN}RUNNING${NC}"
else
    echo -e "${RED}ERRO${NC}"
fi

echo -n "Supervisor: "
if systemctl is-active --quiet "${SUPERVISOR_SERVICE}"; then
    echo -e "${GREEN}RUNNING${NC}"
else
    echo -e "${RED}ERRO${NC}"
fi

echo
echo "Horizon:"
supervisorctl status horizon || true

echo
echo "Apache:"
"${APACHECTL}" configtest

echo
echo "PHP:"
"${PHP_BIN}" -v | head -n 1

echo
echo "Redis:"
redis-cli ping || true

echo
echo "HTTP:"
curl -sI "http://${SERVER_IP}/" | head -n 1 || true

# =============================================================================
# RESULTADO
# =============================================================================

echo
echo "==========================================================================="
echo "              INSTALAÇÃO CONCLUÍDA"
echo "                                   by Script https://github.com/projetoroot"
echo " Se puder apoiar nosso trabalho, veja nosso canal no youtube.com/projetoroot"
echo "==========================================================================="
echo
echo "rConfig URL:"
echo "http://${SERVER_IP}/"

echo

echo "Diretório:"
echo "${RCONFIG_DIR}"

echo
echo "=============================================================="
echo "                         ACESSOS"
echo "=============================================================="
echo
echo "rConfig:"
echo "Usuário: admin@domain.com"
echo "Senha:   admin"
echo
echo "MariaDB:"
echo "Banco:   ${DB_NAME}"
echo "Usuário: ${DB_USER}"
echo "Senha:   ${DB_PASSWORD}"
echo
echo "Redis:"
echo "Serviço: ${REDIS_SERVICE}"
echo
echo "Supervisor:"
echo "Serviço: ${SUPERVISOR_SERVICE}"
echo
echo "=============================================================="
echo
echo "=============================================================="
echo
echo "IMPORTANTE:"
echo
echo "1. Faça login usando as credenciais padrão do rConfig."
echo "2. Altere imediatamente a senha padrão."
echo "3. Configure HTTPS antes de disponibilizar o sistema externamente."
echo "4. Faça backup do banco e da aplicação."
echo "5. Proteja o arquivo .env contra acesso não autorizado."
echo
echo "=============================================================="
echo
