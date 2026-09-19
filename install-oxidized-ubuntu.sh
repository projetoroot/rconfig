#!/usr/bin/env bash
###############################################################################
# Oxidized 0.37.0 + oxidized-web 0.18.1
# Ubuntu 26.04 LTS
#
# Projeto Root
# https://github.com/projetoroot
# https://youtube.com/projetoroot
# https://wiki.projetoroot.com.br
#
# Recursos:
# - Ubuntu 26.04 LTS
# - Oxidized 0.37.0
# - oxidized-web 0.18.1
# - Ruby
# - RubyGems
# - systemd
# - SSH seguro
# - Verificação de host keys
# - router.db protegido
# - Git para histórico
# - cadastro/remocao/listagem/teste
# - validacao de modelos
# - backup automatico do router.db
# - hardening systemd
# - equipamento temporario para inicializacao do Web
#
# IMPORTANTE:
# - Nao existe usuario/senha do Web neste instalador.
# - username/password do Oxidized sao credenciais dos equipamentos.
###############################################################################

set -Eeuo pipefail
IFS=$'\n\t'

###############################################################################
# PATH
###############################################################################

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

###############################################################################
# CONFIG
###############################################################################

OXIDIZED_VERSION="0.37.0"
OXIDIZED_WEB_VERSION="0.18.1"

OX_USER="oxidized"
OX_GROUP="oxidized"

OX_HOME="/var/lib/oxidized"
OX_CONFIG_DIR="/etc/oxidized"
OX_CONFIG_FILE="${OX_CONFIG_DIR}/config"
OX_CONFIG="${OX_CONFIG_DIR}/config"
OX_ROUTER_DB="${OX_CONFIG_DIR}/router.db"
OX_BACKUP_DIR="${OX_CONFIG_DIR}/backups"
OX_CRASH_DIR="${OX_CONFIG_DIR}/crash"

OX_GIT_REPO="${OX_HOME}/configs.git"
OX_CONFIG_REPO="${OX_HOME}/configs.git"
OX_SSH_DIR="${OX_HOME}/.ssh"
OX_KNOWN_HOSTS="${OX_SSH_DIR}/known_hosts"

OX_SERVICE="/etc/systemd/system/oxidized.service"

HELPER_ADD="/usr/local/bin/oxidized-add"
HELPER_LIST="/usr/local/bin/oxidized-list"
HELPER_REMOVE="/usr/local/bin/oxidized-remove"
HELPER_TEST="/usr/local/bin/oxidized-test"
HELPER_MODELS="/usr/local/bin/oxidized-models"

TEMP_NODE="127.0.0.1"
TEMP_NAME="switch-teste"
TEMP_MARKER="* Remover assim que puder"

WEB_PORT="8888"
WEB_LISTEN="127.0.0.1"

HOST_IP=""
GEM_BIN_DIR=""
OXIDIZED_BIN=""

###############################################################################
# CORES
###############################################################################

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

###############################################################################
# FUNCOES
###############################################################################

log() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[AVISO]${NC} $*"
}

error() {
    echo -e "${RED}[ERRO]${NC} $*" >&2
}

die() {
    error "$*"
    exit 1
}

section() {
    echo
    echo "==========================================================================="
    echo " $*"
    echo "==========================================================================="
}

cleanup_on_error() {
    error "A instalação foi interrompida."
    error "Verifique os dados exibidos acima."
}

trap cleanup_on_error ERR

###############################################################################
# ROOT
###############################################################################

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "Execute como root: sudo $0"
    fi
}

###############################################################################
# SISTEMA OPERACIONAL
###############################################################################

detect_os() {

    section "VALIDANDO SISTEMA OPERACIONAL"

    if [[ ! -r /etc/os-release ]]; then
        die "Não foi possível identificar o sistema operacional."
    fi

    . /etc/os-release

    log "Sistema : ${PRETTY_NAME}"
    log "ID      : ${ID}"
    log "Versão  : ${VERSION_ID}"
    log "Codename: ${VERSION_CODENAME:-desconhecido}"

    if [[ "${ID}" != "ubuntu" ]]; then
        die "Este instalador é exclusivo para Ubuntu 26.04 LTS."
    fi

    if [[ "${VERSION_ID}" != "26.04" ]]; then
        die "Este instalador exige Ubuntu 26.04 LTS."
    fi

    if [[ "${VERSION_CODENAME:-}" != "resolute" ]]; then
        die "Ubuntu detectado, mas o codename não é resolute."
    fi

    log "Ubuntu 26.04 LTS detectado."
}

###############################################################################
# IP
###############################################################################

detect_ip() {

    section "DETECTANDO IP"

    HOST_IP="$(ip -4 route get 1.1.1.1 2>/dev/null \
        | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"

    if [[ -z "${HOST_IP}" ]]; then
        HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi

    [[ -n "${HOST_IP}" ]] || HOST_IP="127.0.0.1"

    log "IP detectado: ${HOST_IP}"
}

###############################################################################
# REPOSITÓRIOS
###############################################################################

configure_repositories() {

    section "CONFIGURANDO REPOSITÓRIOS"

    export DEBIAN_FRONTEND=noninteractive

    apt-get update

    apt-get install -y \
        software-properties-common

    if ! grep -RqsE \
        '^[[:space:]]*deb .*ubuntu.* universe|^[[:space:]]*Components:.*universe' \
        /etc/apt/sources.list \
        /etc/apt/sources.list.d \
        2>/dev/null; then

        log "Habilitando repositório universe..."

        add-apt-repository -y universe
    else
        log "Repositório universe já está habilitado."
    fi

    apt-get update

    log "Repositórios atualizados."
}

###############################################################################
# DEPENDÊNCIAS
###############################################################################

install_packages() {

    section "INSTALANDO DEPENDÊNCIAS"

    export DEBIAN_FRONTEND=noninteractive

    apt-get install -y \
        ca-certificates \
        qemu-guest-agent \
        wget \
        net-tools \
        iptraf \
        htop \
        curl \
        git \
        ruby \
        ruby-dev \
        ruby-rubygems \
        build-essential \
        g++ \
        pkg-config \
        cmake \
        libsqlite3-dev \
        libssl-dev \
        libssh2-1-dev \
        libicu-dev \
        zlib1g-dev \
        libyaml-dev \
        libzstd-dev \
        openssh-client \
        passwd \
        gawk \
        sed \
        grep \
        coreutils \
        procps \
        iproute2

    log "Dependências instaladas."
}

###############################################################################
# RUBY
###############################################################################

validate_ruby() {

    section "VALIDANDO RUBY"

    local ruby_version
    local ruby_major
    local ruby_minor

    ruby_version="$(ruby -e 'print RUBY_VERSION')"

    ruby_major="$(ruby -e 'puts RUBY_VERSION.split(".")[0]')"
    ruby_minor="$(ruby -e 'puts RUBY_VERSION.split(".")[1]')"

    log "Ruby: ${ruby_version}"
    log "RubyGems: $(gem --version)"

    if (( ruby_major < 3 )); then
        die "Ruby ${ruby_version} não é compatível. Oxidized exige Ruby >= 3.0."
    fi

    if (( ruby_major == 3 && ruby_minor < 0 )); then
        die "Ruby ${ruby_version} não é compatível."
    fi

    log "Versão do Ruby compatível."
}

###############################################################################
# USUARIO
###############################################################################

create_user() {

    section "CRIANDO USUÁRIO DO SERVIÇO"

    if ! getent group "${OX_GROUP}" >/dev/null 2>&1; then
        groupadd --system "${OX_GROUP}"
    fi

    if ! id "${OX_USER}" >/dev/null 2>&1; then

        useradd \
            --system \
            --gid "${OX_GROUP}" \
            --home-dir "${OX_HOME}" \
            --create-home \
            --shell /usr/sbin/nologin \
            "${OX_USER}"

    fi

    mkdir -p \
        "${OX_HOME}" \
        "${OX_CONFIG_DIR}" \
        "${OX_BACKUP_DIR}" \
        "${OX_CRASH_DIR}" \
        "${OX_SSH_DIR}"

    chown -R "${OX_USER}:${OX_GROUP}" "${OX_HOME}"
    chown -R "${OX_USER}:${OX_GROUP}" "${OX_CONFIG_DIR}"

    chmod 750 "${OX_HOME}"
    chmod 750 "${OX_CONFIG_DIR}"
    chmod 750 "${OX_BACKUP_DIR}"
    chmod 750 "${OX_CRASH_DIR}"

    chmod 700 "${OX_SSH_DIR}"

    log "Usuário ${OX_USER} configurado."
}

###############################################################################
# GEM BIN
###############################################################################

detect_gem_bin() {

    section "DETECTANDO DIRETÓRIO DO RUBYGEMS"

    GEM_BIN_DIR="$(ruby -rrubygems -e 'puts Gem.bindir')"

    if [[ -z "${GEM_BIN_DIR}" ]]; then
        die "Não foi possível determinar Gem.bindir."
    fi

    if [[ ! -d "${GEM_BIN_DIR}" ]]; then
        die "Diretório RubyGems não existe: ${GEM_BIN_DIR}"
    fi

    log "Gem.bindir: ${GEM_BIN_DIR}"

    export PATH="${GEM_BIN_DIR}:${PATH}"
}

###############################################################################
# GEMS
###############################################################################

install_gems() {

    section "INSTALANDO OXIDIZED"

    log "Instalando Oxidized ${OXIDIZED_VERSION}..."

    gem install oxidized \
        -v "${OXIDIZED_VERSION}" \
        --no-document

    log "Oxidized ${OXIDIZED_VERSION} instalado."

    log "Instalando oxidized-web ${OXIDIZED_WEB_VERSION}..."

    gem install oxidized-web \
        -v "${OXIDIZED_WEB_VERSION}" \
        --no-document

    log "oxidized-web ${OXIDIZED_WEB_VERSION} instalado."

    GEM_BIN_DIR="$(ruby -rrubygems -e 'puts Gem.bindir')"

    export PATH="${GEM_BIN_DIR}:${PATH}"

    if [[ ! -x "${GEM_BIN_DIR}/oxidized" ]]; then
        die "Executável oxidized não encontrado em ${GEM_BIN_DIR}."
    fi

    OXIDIZED_BIN="${GEM_BIN_DIR}/oxidized"

    log "Executável: ${OXIDIZED_BIN}"

    if [[ -x "${GEM_BIN_DIR}/oxidized-web" ]]; then
        log "Executável oxidized-web encontrado."
    else
        log "A gem oxidized-web não fornece executável separado."
        log "Isso é esperado para esta versão."
    fi

    if ! gem list '^oxidized$' \
        -i \
        -v "${OXIDIZED_VERSION}" >/dev/null 2>&1; then

        die "Oxidized ${OXIDIZED_VERSION} não foi encontrado."
    fi

    if ! gem list '^oxidized-web$' \
        -i \
        -v "${OXIDIZED_WEB_VERSION}" >/dev/null 2>&1; then

        die "oxidized-web ${OXIDIZED_WEB_VERSION} não foi encontrado."
    fi

    log "Gems verificadas com sucesso."
}

###############################################################################
# LINK DO EXECUTÁVEL
###############################################################################

create_oxidized_link() {

    section "CONFIGURANDO EXECUTÁVEL DO OXIDIZED"

    if [[ ! -x "${OXIDIZED_BIN}" ]]; then
        die "Executável não encontrado: ${OXIDIZED_BIN}"
    fi

    ln -sfn "${OXIDIZED_BIN}" /usr/local/bin/oxidized

    chown -h root:root /usr/local/bin/oxidized
    chmod 755 "${OXIDIZED_BIN}"

    log "Link criado:"
    log "  /usr/local/bin/oxidized -> ${OXIDIZED_BIN}"
}

###############################################################################
# MODELOS
###############################################################################

get_model_dir() {

    ruby -rrubygems -e '
        spec = Gem::Specification.find_by_name("oxidized")
        puts File.join(spec.full_gem_path, "lib", "oxidized", "model")
    '
}

model_exists() {

    local model="$1"
    local model_dir

    model_dir="$(get_model_dir)"

    [[ -f "${model_dir}/${model}.rb" ]]
}

validate_model() {

    local model="$1"

    if ! model_exists "${model}"; then
        error "Modelo '${model}' não existe nesta instalação do Oxidized."
        return 1
    fi

    return 0
}

show_installed_models() {

    local model_dir

    model_dir="$(get_model_dir)"

    find "${model_dir}" \
        -maxdepth 1 \
        -type f \
        -name '*.rb' \
        -printf '%f\n' \
        | sed 's/\.rb$//' \
        | sort
}

###############################################################################
# ROUTER.DB
###############################################################################

create_router_db() {

    section "CRIANDO ROUTER.DB"

    if [[ ! -f "${OX_ROUTER_DB}" ]]; then

        cat > "${OX_ROUTER_DB}" <<'EOF'
# Oxidized router.db
#
# Formato:
# nome:ip:model:usuario:senha:grupo:enable:porta_ssh
#
# Exemplos:
#
# Core:10.0.0.1:vrp:oxidized:SENHA:Huawei::22
# SW01:10.0.0.2:ios:oxidized:SENHA:Cisco:ENABLE:22
#
# IMPORTANTE:
# Este arquivo contém credenciais.
# Não publique este arquivo.
EOF

    fi

    chown "${OX_USER}:${OX_GROUP}" "${OX_ROUTER_DB}"
    chmod 600 "${OX_ROUTER_DB}"

    log "router.db criado/protegido."
}

###############################################################################
# BACKUP
###############################################################################

backup_file() {

    local file="$1"

    [[ -f "${file}" ]] || return 0

    local base
    base="$(basename "${file}")"

    cp -a \
        "${file}" \
        "${OX_BACKUP_DIR}/${base}.$(date +%Y%m%d-%H%M%S).bak"

    chown "${OX_USER}:${OX_GROUP}" \
        "${OX_BACKUP_DIR}"/*.bak 2>/dev/null || true

    chmod 600 \
        "${OX_BACKUP_DIR}"/*.bak 2>/dev/null || true
}

###############################################################################
# GIT
###############################################################################

create_git_repo() {

    section "CONFIGURANDO GIT"

    mkdir -p "${OX_CONFIG_REPO}"

    chown -R "${OX_USER}:${OX_GROUP}" "${OX_CONFIG_REPO}"

    if [[ ! -d "${OX_CONFIG_REPO}/objects" ]]; then

        runuser -u "${OX_USER}" -- \
            git -C "${OX_CONFIG_REPO}" init --bare

    fi

    runuser -u "${OX_USER}" -- \
        git -C "${OX_CONFIG_REPO}" config user.name "Oxidized"

    runuser -u "${OX_USER}" -- \
        git -C "${OX_CONFIG_REPO}" config user.email "oxidized@localhost"

    log "Git configurado em ${OX_CONFIG_REPO}"
}

###############################################################################
# WEB
###############################################################################

configure_web() {

    section "CONFIGURAÇÃO DO OXIDIZED-WEB"

    echo
    echo "Por padrão, o Web ficará disponível somente localmente:"
    echo
    echo "  http://127.0.0.1:${WEB_PORT}/"
    echo
    echo "Isso é mais seguro."
    echo
    echo "Para acesso pela rede, informe o IP da interface:"
    echo "  ${HOST_IP}"
    echo

    read -r -p "Endereço de escuta [127.0.0.1]: " INPUT_LISTEN

    if [[ -n "${INPUT_LISTEN}" ]]; then
        WEB_LISTEN="${INPUT_LISTEN}"
    fi

    while true; do

        read -r -p "Porta Web [8888]: " INPUT_PORT

        if [[ -z "${INPUT_PORT}" ]]; then
            WEB_PORT="8888"
            break
        fi

        if [[ "${INPUT_PORT}" =~ ^[0-9]+$ ]] &&
           (( INPUT_PORT >= 1024 && INPUT_PORT <= 65535 )); then

            WEB_PORT="${INPUT_PORT}"
            break
        fi

        warn "Informe uma porta entre 1024 e 65535."

    done

    log "Web: ${WEB_LISTEN}:${WEB_PORT}"
}

###############################################################################
# CONFIG
###############################################################################

create_config() {

    section "CRIANDO CONFIGURAÇÃO DO OXIDIZED"

    backup_file "${OX_CONFIG}"

    cat > "${OX_CONFIG}" <<EOF
---
# ============================================================================
# Oxidized
# Projeto Root
# Ubuntu 26.04 LTS
# ============================================================================

interval: 3600

use_syslog: false
debug: false

threads: 5
use_max_threads: false

timeout: 30
timelimit: 300
retries: 3

resolve_dns: false

next_adds_job: true

vars:
  remove_secret: true

groups: {}

models: {}

pid: ${OX_HOME}/oxidized.pid

crash:
  directory: ${OX_CRASH_DIR}
  hostnames: false

stats:
  history_size: 10

# ============================================================================
# WEB
# ============================================================================

extensions:
  oxidized-web:
    load: true
    listen: ${WEB_LISTEN}
    port: ${WEB_PORT}

# ============================================================================
# INPUT
# ============================================================================

input:
  default: ssh

  debug: false

  ssh:
    secure: true

# ============================================================================
# OUTPUT
# ============================================================================

output:
  default: git

  git:
    user: Oxidized
    email: oxidized@localhost
    repo: ${OX_CONFIG_REPO}

# ============================================================================
# SOURCE
# ============================================================================

source:
  default: csv

  csv:
    file: ${OX_ROUTER_DB}

    delimiter: !ruby/regexp /:/

    map:
      name: 0
      ip: 1
      model: 2
      username: 3
      password: 4
      group: 5

    vars_map:
      enable: 6
      ssh_port: 7

# ============================================================================
# ALIASES
# ============================================================================

model_map:
  cisco: ios
  cisco_ios: ios
  cisco_iosxe: ios

  cisco_iosxr: iosxr
  cisco_nxos: nxos

  huawei: vrp
  huawei_vrp: vrp

  juniper: junos

  mikrotik: routeros

  fortinet: fortigate
  fortigate: fortigate

  arista: eos

  hp: procurve
  hpe: procurve

  hpe_comware: comware

  ubiquiti: edgeos
  edgeos: edgeos
EOF

    chown "${OX_USER}:${OX_GROUP}" "${OX_CONFIG}"
    chmod 600 "${OX_CONFIG}"

    log "Configuração criada."
}

###############################################################################
# TEMPORARIO
###############################################################################

create_temp_node() {

    section "CRIANDO EQUIPAMENTO TEMPORÁRIO"

    if grep -qE "^${TEMP_NAME}:" \
        "${OX_ROUTER_DB}" 2>/dev/null; then

        return 0
    fi

    cat >> "${OX_ROUTER_DB}" <<EOF

# ${TEMP_MARKER}
${TEMP_NAME}:${TEMP_NODE}:ios:teste:teste:teste::22
EOF

    chown "${OX_USER}:${OX_GROUP}" "${OX_ROUTER_DB}"
    chmod 600 "${OX_ROUTER_DB}"

    log "Equipamento temporário criado."
}

remove_temp_node() {

    local tmpfile

    tmpfile="$(mktemp)"

    awk -F: -v name="${TEMP_NAME}" '
        $1 != name { print }
    ' "${OX_ROUTER_DB}" > "${tmpfile}"

    chown "${OX_USER}:${OX_GROUP}" "${tmpfile}"
    chmod 600 "${tmpfile}"

    mv -f "${tmpfile}" "${OX_ROUTER_DB}"

    log "Equipamento temporário removido."
}

###############################################################################
# CONTAGEM
###############################################################################

count_real_nodes() {

    awk -F: '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        $1 == "switch-teste" { next }
        NF >= 3 { count++ }
        END { print count + 0 }
    ' "${OX_ROUTER_DB}"
}

###############################################################################
# VALIDAR ROUTER.DB
###############################################################################

validate_router_db() {

    section "VALIDANDO ROUTER.DB"

    local line=0
    local bad=0

    while IFS= read -r entry; do

        line=$((line + 1))

        [[ -z "${entry}" ]] && continue
        [[ "${entry}" =~ ^[[:space:]]*# ]] && continue

        local fields
        fields="$(awk -F: '{print NF}' <<< "${entry}")"

        if (( fields < 5 )); then
            error "router.db linha ${line}: campos insuficientes."
            bad=1
            continue
        fi

        local name
        local model
        local ip

        name="$(cut -d: -f1 <<< "${entry}")"
        ip="$(cut -d: -f2 <<< "${entry}")"
        model="$(cut -d: -f3 <<< "${entry}")"

        if [[ -z "${name}" ||
              -z "${ip}" ||
              -z "${model}" ]]; then

            error "router.db linha ${line}: nome/IP/modelo inválido."
            bad=1
            continue
        fi

        if ! validate_model "${model}"; then

            error "router.db linha ${line}: modelo inválido: ${model}"
            bad=1

        fi

    done < "${OX_ROUTER_DB}"

    if (( bad != 0 )); then
        die "router.db possui erros."
    fi

    log "router.db válido."
}

###############################################################################
# VALIDAR CONFIG
###############################################################################

validate_config() {

    section "VALIDANDO CONFIGURAÇÃO"

    local output
    local rc=0

    output="$(
        timeout 15 \
        runuser -u "${OX_USER}" -- \
        env \
            HOME="${OX_HOME}" \
            OXIDIZED_HOME="${OX_CONFIG_DIR}" \
            OXIDIZED_LOGS="${OX_CONFIG_DIR}" \
            PATH="${GEM_BIN_DIR}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            "${OXIDIZED_BIN}" \
        2>&1
    )" || rc=$?

    echo "${output}" \
        | sed \
            -E 's/(password[=:][[:space:]]*)[^,} ]+/\1[OCULTO]/Ig' \
        | tail -n 80

    if grep -qiE \
        "InvalidConfig|YAML|ModelNotFound|source returns no usable nodes|Error loading config" \
        <<< "${output}"; then

        die "A configuração não passou na validação."
    fi

    if grep -q "Loaded 0 nodes" <<< "${output}"; then
        die "Nenhum node válido foi carregado."
    fi

    log "Configuração carregada corretamente."
}

###############################################################################
# SYSTEMD
###############################################################################

create_systemd() {

    section "CONFIGURANDO SYSTEMD"

    cat > "${OX_SERVICE}" <<EOF
[Unit]
Description=Oxidized Network Configuration Backup
Documentation=https://github.com/ytti/oxidized
After=network-online.target
Wants=network-online.target

[Service]
Type=simple

User=${OX_USER}
Group=${OX_GROUP}

Environment=HOME=${OX_HOME}
Environment=OXIDIZED_HOME=${OX_CONFIG_DIR}
Environment=OXIDIZED_LOGS=${OX_CONFIG_DIR}
Environment=PATH=${GEM_BIN_DIR}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ExecStart=/usr/local/bin/oxidized

Restart=on-failure
RestartSec=10

TimeoutStartSec=120
TimeoutStopSec=30

UMask=0077

NoNewPrivileges=true

PrivateTmp=true
PrivateDevices=true

ProtectSystem=strict
ProtectHome=true

ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true

RestrictSUIDSGID=true
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictRealtime=true
RestrictNamespaces=true

CapabilityBoundingSet=
AmbientCapabilities=

RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6

ReadWritePaths=${OX_CONFIG_DIR}
ReadWritePaths=${OX_HOME}

SystemCallArchitectures=native

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "${OX_SERVICE}"

    systemctl daemon-reload
    systemctl enable oxidized.service

    log "systemd configurado."
}

###############################################################################
# HELPERS
###############################################################################

install_helpers() {

    section "INSTALANDO FERRAMENTAS AUXILIARES"

    ###########################################################################
    # MODELS
    ###########################################################################

    cat > "${HELPER_MODELS}" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

MODEL_DIR="$(
    ruby -rrubygems -e '
        spec = Gem::Specification.find_by_name("oxidized")
        puts File.join(spec.full_gem_path, "lib", "oxidized", "model")
    '
)"

echo
echo "Modelos instalados no Oxidized:"
echo

find "${MODEL_DIR}" \
    -maxdepth 1 \
    -type f \
    -name '*.rb' \
    -printf '%f\n' \
    | sed 's/\.rb$//' \
    | sort

echo
EOF

    chmod 755 "${HELPER_MODELS}"

    ###########################################################################
    # LIST
    ###########################################################################

    cat > "${HELPER_LIST}" <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

DB="/etc/oxidized/router.db"

echo
echo "==========================================================================="
echo " EQUIPAMENTOS CADASTRADOS"
echo "==========================================================================="
echo

if [[ ! -f "${DB}" ]]; then
    echo "Nenhum router.db encontrado."
    exit 0
fi

printf "%-25s %-20s %-15s %-18s %-20s %-8s\n" \
    "NOME" "IP" "MODELO" "USUARIO" "GRUPO" "SSH"

echo "------------------------------------------------------------------------------------------------"

awk -F: '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }

    {
        printf "%-25s %-20s %-15s %-18s %-20s %-8s\n",
        $1, $2, $3, $4, $6, ($8 == "" ? "22" : $8)
    }
' "${DB}"

echo
EOF

    chmod 755 "${HELPER_LIST}"

    ###########################################################################
    # REMOVE
    ###########################################################################

    cat > "${HELPER_REMOVE}" <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

DB="/etc/oxidized/router.db"
BACKUP_DIR="/etc/oxidized/backups"
SERVICE="oxidized"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Execute como root."
    exit 1
fi

if [[ $# -lt 1 ]]; then
    echo "Uso: oxidized-remove NOME"
    exit 1
fi

NAME="$1"

if [[ "${NAME}" == "switch-teste" ]]; then
    echo "O equipamento temporário não deve ser removido manualmente."
    exit 1
fi

if [[ ! -f "${DB}" ]]; then
    echo "router.db não encontrado."
    exit 1
fi

if ! awk -F: -v name="${NAME}" \
    '$1 == name { found=1 } END { exit !found }' \
    "${DB}"; then

    echo "Equipamento não encontrado: ${NAME}"
    exit 1
fi

mkdir -p "${BACKUP_DIR}"

cp -a "${DB}" \
    "${BACKUP_DIR}/router.db.$(date +%Y%m%d-%H%M%S).bak"

TMP="$(mktemp)"

awk -F: -v name="${NAME}" \
    '$1 != name { print }' \
    "${DB}" > "${TMP}"

chown oxidized:oxidized "${TMP}"
chmod 600 "${TMP}"

mv -f "${TMP}" "${DB}"

echo "Equipamento removido: ${NAME}"

if systemctl is-active --quiet "${SERVICE}"; then

    PORT="$(
        awk '
            /extensions:/ { ext=1 }
            ext && /oxidized-web:/ { web=1 }
            web && /port:/ {
                gsub(/[^0-9]/,"",$2)
                print $2
                exit
            }
        ' /etc/oxidized/config
    )"

    PORT="${PORT:-8888}"

    curl \
        --fail \
        --silent \
        --show-error \
        --max-time 5 \
        "http://127.0.0.1:${PORT}/reload" \
        >/dev/null || true
fi

echo "Oxidized atualizado."
EOF

    chmod 755 "${HELPER_REMOVE}"

    ###########################################################################
    # TEST
    ###########################################################################

    cat > "${HELPER_TEST}" <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

DB="/etc/oxidized/router.db"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Execute como root."
    exit 1
fi

if [[ $# -lt 1 ]]; then
    echo "Uso: oxidized-test NOME"
    exit 1
fi

NAME="$1"

if [[ ! -f "${DB}" ]]; then
    echo "router.db não encontrado."
    exit 1
fi

LINE="$(
    awk -F: -v name="${NAME}" \
        '$1 == name { print; exit }' \
        "${DB}"
)"

if [[ -z "${LINE}" ]]; then
    echo "Equipamento não encontrado: ${NAME}"
    exit 1
fi

IP="$(cut -d: -f2 <<< "${LINE}")"
USER="$(cut -d: -f4 <<< "${LINE}")"
PORT="$(cut -d: -f8 <<< "${LINE}")"

PORT="${PORT:-22}"

echo
echo "Teste TCP/SSH"
echo "Equipamento : ${NAME}"
echo "IP          : ${IP}"
echo "Usuário     : ${USER}"
echo "Porta       : ${PORT}"
echo

if timeout 5 bash -c "</dev/tcp/${IP}/${PORT}" 2>/dev/null; then

    echo "[OK] Porta ${PORT}/TCP acessível."

else

    echo "[ERRO] Não foi possível conectar em ${IP}:${PORT}."
    exit 1

fi

echo
echo "Para testar autenticação SSH manualmente:"
echo
echo "ssh -p ${PORT} ${USER}@${IP}"
echo
EOF

    chmod 755 "${HELPER_TEST}"

    ###########################################################################
    # ADD
    ###########################################################################

    cat > "${HELPER_ADD}" <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

DB="/etc/oxidized/router.db"
BACKUP_DIR="/etc/oxidized/backups"
CONFIG="/etc/oxidized/config"
TEMP_NAME="switch-teste"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Execute como root."
    exit 1
fi

if [[ ! -f "${DB}" ]]; then
    echo "router.db não encontrado."
    exit 1
fi

get_model_dir() {

    ruby -rrubygems -e '
        spec = Gem::Specification.find_by_name("oxidized")
        puts File.join(spec.full_gem_path, "lib", "oxidized", "model")
    '
}

model_exists() {

    local model="$1"
    local dir

    dir="$(get_model_dir)"

    [[ -f "${dir}/${model}.rb" ]]
}

validate_safe_field() {

    local field="$1"
    local label="$2"

    if [[ -z "${field}" ]]; then
        echo "Campo obrigatório: ${label}"
        return 1
    fi

    if [[ "${field}" == *:* ||
          "${field}" == *$'\n'* ||
          "${field}" == *$'\r'* ]]; then

        echo "O campo ${label} contém caracteres inválidos."
        echo "O caractere ':' não pode ser usado."
        return 1
    fi

    return 0
}

WEB_PORT="$(
    awk '
        /extensions:/ { ext=1 }
        ext && /oxidized-web:/ { web=1 }
        web && /port:/ {
            gsub(/[^0-9]/,"",$2)
            print $2
            exit
        }
    ' "${CONFIG}"
)"

WEB_PORT="${WEB_PORT:-8888}"

echo
echo "==========================================================================="
echo " OXIDIZED - CADASTRAR EQUIPAMENTO"
echo "==========================================================================="
echo

read -r -p "Nome/hostname do equipamento: " NAME
validate_safe_field "${NAME}" "nome" || exit 1

if [[ "${NAME}" == "${TEMP_NAME}" ]]; then
    echo "Esse nome é reservado para o equipamento temporário."
    exit 1
fi

if awk -F: -v name="${NAME}" \
    '$1 == name { found=1 } END { exit !found }' \
    "${DB}"; then

    echo "Já existe um equipamento com esse nome."
    exit 1
fi

read -r -p "IP ou hostname para conexão: " IP
validate_safe_field "${IP}" "IP/hostname" || exit 1

echo
echo "Modelos:"
echo
echo "  1) Cisco IOS / IOS-XE"
echo "  2) Cisco IOS-XR"
echo "  3) Cisco NX-OS"
echo "  4) Huawei VRP"
echo "  5) Juniper JunOS"
echo "  6) MikroTik RouterOS"
echo "  7) Fortinet FortiGate"
echo "  8) Fortinet FortiOS"
echo "  9) Arista EOS"
echo " 10) HPE ProCurve"
echo " 11) HPE Comware"
echo " 12) Ubiquiti EdgeOS"
echo " 13) Ubiquiti UniFi/AP/AirOS"
echo " 14) Informar modelo manualmente"
echo

read -r -p "Escolha [1-14]: " OPTION

case "${OPTION}" in

    1)
        VENDOR_NAME="Cisco IOS/IOS-XE"
        MODEL="ios"
        ;;

    2)
        VENDOR_NAME="Cisco IOS-XR"
        MODEL="iosxr"
        ;;

    3)
        VENDOR_NAME="Cisco NX-OS"
        MODEL="nxos"
        ;;

    4)
        VENDOR_NAME="Huawei VRP"
        MODEL="vrp"
        ;;

    5)
        VENDOR_NAME="Juniper JunOS"
        MODEL="junos"
        ;;

    6)
        VENDOR_NAME="MikroTik RouterOS"
        MODEL="routeros"
        ;;

    7)
        VENDOR_NAME="Fortinet FortiGate"
        MODEL="fortigate"
        ;;

    8)
        VENDOR_NAME="Fortinet FortiOS"
        MODEL="fortios"
        ;;

    9)
        VENDOR_NAME="Arista EOS"
        MODEL="eos"
        ;;

    10)
        VENDOR_NAME="HPE ProCurve"
        MODEL="procurve"
        ;;

    11)
        VENDOR_NAME="HPE Comware"
        MODEL="comware"
        ;;

    12)
        VENDOR_NAME="Ubiquiti EdgeOS"
        MODEL="edgeos"
        ;;

    13)
        VENDOR_NAME="Ubiquiti UniFi/AP/AirOS"
        MODEL="unifiap"
        ;;

    14)
        read -r -p "Modelo Oxidized: " MODEL
        VENDOR_NAME="Manual"
        ;;

    *)
        echo "Opção inválida."
        exit 1
        ;;

esac

if ! model_exists "${MODEL}"; then

    echo
    echo "ERRO: o modelo '${MODEL}' não está instalado nesta versão."
    echo
    echo "Modelos disponíveis:"
    echo

    get_model_dir \
        | xargs -I{} find {} \
            -maxdepth 1 \
            -type f \
            -name '*.rb' \
            -printf '%f\n' \
        | sed 's/\.rb$//' \
        | sort

    exit 1
fi

echo
echo "Modelo: ${MODEL}"
echo "Fabricante: ${VENDOR_NAME}"
echo

read -r -p "Usuário SSH: " USERNAME
validate_safe_field "${USERNAME}" "usuário" || exit 1

read -r -s -p "Senha SSH: " PASSWORD
echo

if [[ -z "${PASSWORD}" ]]; then
    echo "A senha não pode ser vazia."
    exit 1
fi

if [[ "${PASSWORD}" == *:* ||
      "${PASSWORD}" == *$'\n'* ||
      "${PASSWORD}" == *$'\r'* ]]; then

    echo
    echo "ERRO: a senha contém ':' ou quebra de linha."
    echo
    echo "O formato CSV usado pelo router.db utiliza ':' como separador."
    echo "Para senhas contendo ':' será necessário migrar para outro Source."
    exit 1
fi

echo
read -r -p "Grupo [${VENDOR_NAME}]: " GROUP

if [[ -z "${GROUP}" ]]; then
    GROUP="${VENDOR_NAME}"
fi

validate_safe_field "${GROUP}" "grupo" || exit 1

echo
read -r -s -p "Senha enable/super (opcional): " ENABLE
echo

if [[ "${ENABLE}" == *:* ||
      "${ENABLE}" == *$'\n'* ||
      "${ENABLE}" == *$'\r'* ]]; then

    echo "Senha enable contém caractere inválido."
    exit 1
fi

echo
read -r -p "Porta SSH [22]: " SSH_PORT

if [[ -z "${SSH_PORT}" ]]; then
    SSH_PORT="22"
fi

if ! [[ "${SSH_PORT}" =~ ^[0-9]+$ ]] ||
   (( SSH_PORT < 1 || SSH_PORT > 65535 )); then

    echo "Porta SSH inválida."
    exit 1
fi

echo
echo "==========================================================================="
echo " CONFIRMAÇÃO"
echo "==========================================================================="
echo
echo "Nome       : ${NAME}"
echo "IP         : ${IP}"
echo "Fabricante : ${VENDOR_NAME}"
echo "Modelo     : ${MODEL}"
echo "Usuário    : ${USERNAME}"
echo "Grupo      : ${GROUP}"
echo "Porta SSH  : ${SSH_PORT}"
echo

read -r -p "Confirmar cadastro? [s/N]: " CONFIRM

if [[ "${CONFIRM,,}" != "s" ]]; then
    echo "Cadastro cancelado."
    exit 0
fi

mkdir -p "${BACKUP_DIR}"

cp -a \
    "${DB}" \
    "${BACKUP_DIR}/router.db.$(date +%Y%m%d-%H%M%S).bak"

TMP="$(mktemp)"

awk -F: -v name="${NAME}" \
    '$1 != name { print }' \
    "${DB}" > "${TMP}"

printf '%s:%s:%s:%s:%s:%s:%s:%s\n' \
    "${NAME}" \
    "${IP}" \
    "${MODEL}" \
    "${USERNAME}" \
    "${PASSWORD}" \
    "${GROUP}" \
    "${ENABLE}" \
    "${SSH_PORT}" >> "${TMP}"

chown oxidized:oxidized "${TMP}"
chmod 600 "${TMP}"

mv -f "${TMP}" "${DB}"

echo
echo "[OK] Equipamento gravado."

###############################################################################
# SSH HOST KEY
###############################################################################

mkdir -p /var/lib/oxidized/.ssh

chown -R oxidized:oxidized /var/lib/oxidized/.ssh
chmod 700 /var/lib/oxidized/.ssh

echo
echo "Obtendo chave SSH do equipamento..."

KEYSCAN_OUTPUT=""

if KEYSCAN_OUTPUT="$(
    timeout 10 ssh-keyscan \
        -T 5 \
        -H \
        -p "${SSH_PORT}" \
        "${IP}" \
        2>/dev/null
)"; then

    if [[ -n "${KEYSCAN_OUTPUT}" ]]; then

        TMP_KNOWN="$(mktemp)"

        cat /var/lib/oxidized/.ssh/known_hosts \
            2>/dev/null > "${TMP_KNOWN}" || true

        printf '%s\n' "${KEYSCAN_OUTPUT}" >> "${TMP_KNOWN}"

        sort -u "${TMP_KNOWN}" \
            > /var/lib/oxidized/.ssh/known_hosts

        rm -f "${TMP_KNOWN}"

        chown oxidized:oxidized \
            /var/lib/oxidized/.ssh/known_hosts

        chmod 600 \
            /var/lib/oxidized/.ssh/known_hosts

        echo "[OK] Host key adicionada ao known_hosts."

    else

        echo "[AVISO] Não foi possível obter a host key."
        echo "O backup poderá falhar até a chave ser cadastrada."

    fi

else

    echo "[AVISO] Equipamento não respondeu ao ssh-keyscan."

fi

###############################################################################
# VALIDACAO
###############################################################################

echo
echo "Validando router.db..."

if ! awk -F: -v name="${NAME}" '
    $1 == name {
        if ($2 == "" || $3 == "" || $4 == "" || $5 == "") exit 1
        found=1
    }

    END {
        exit found ? 0 : 1
    }
' "${DB}"; then

    echo "ERRO: equipamento não passou na validação."
    exit 1
fi

###############################################################################
# REMOVE TEMPORARIO
###############################################################################

REAL_COUNT="$(
    awk -F: '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        $1 == "switch-teste" { next }
        NF >= 3 { count++ }
        END { print count + 0 }
    ' "${DB}"
)"

if (( REAL_COUNT > 0 )); then

    TMP2="$(mktemp)"

    awk -F: -v name="${TEMP_NAME}" \
        '$1 != name { print }' \
        "${DB}" > "${TMP2}"

    chown oxidized:oxidized "${TMP2}"
    chmod 600 "${TMP2}"

    mv -f "${TMP2}" "${DB}"

    echo "[OK] Equipamento temporário removido."

fi

###############################################################################
# RELOAD
###############################################################################

echo
echo "Recarregando Oxidized..."

if ! systemctl is-active --quiet oxidized; then

    echo "Oxidized não está ativo."
    echo

    systemctl status oxidized \
        --no-pager \
        -l || true

    exit 1

fi

if curl \
    --fail \
    --silent \
    --show-error \
    --max-time 10 \
    "http://127.0.0.1:${WEB_PORT}/reload" \
    >/dev/null; then

    echo "[OK] Configuração recarregada."

else

    echo "[AVISO] Endpoint /reload não respondeu."
    echo "O serviço continua ativo, mas pode ser necessário reiniciar."

    exit 1

fi

echo
echo "==========================================================================="
echo " CADASTRO CONCLUÍDO"
echo "==========================================================================="
echo
echo "Equipamento : ${NAME}"
echo "IP          : ${IP}"
echo "Modelo      : ${MODEL}"
echo "Grupo       : ${GROUP}"
echo "SSH         : ${SSH_PORT}"
echo
EOF

    chmod 755 "${HELPER_ADD}"

    log "Ferramentas instaladas:"
    log "  oxidized-add"
    log "  oxidized-list"
    log "  oxidized-remove"
    log "  oxidized-test"
    log "  oxidized-models"
}

###############################################################################
# OWNERSHIP DOS HELPERS
###############################################################################

set_helper_ownership() {

    chown root:root \
        "${HELPER_ADD}" \
        "${HELPER_LIST}" \
        "${HELPER_REMOVE}" \
        "${HELPER_TEST}" \
        "${HELPER_MODELS}"

    chmod 755 \
        "${HELPER_ADD}" \
        "${HELPER_LIST}" \
        "${HELPER_REMOVE}" \
        "${HELPER_TEST}" \
        "${HELPER_MODELS}"
}

###############################################################################
# PERMISSOES
###############################################################################

set_permissions() {

    section "AJUSTANDO PERMISSÕES"

    if [[ -d "${OX_CONFIG_DIR}" ]]; then
        chown "${OX_USER}:${OX_GROUP}" "${OX_CONFIG_DIR}"
        chmod 750 "${OX_CONFIG_DIR}"
    fi

    if [[ -f "${OX_CONFIG_FILE}" ]]; then
        chown "${OX_USER}:${OX_GROUP}" "${OX_CONFIG_FILE}"
        chmod 640 "${OX_CONFIG_FILE}"
    fi

    if [[ -f "${OX_ROUTER_DB}" ]]; then
        chown "${OX_USER}:${OX_GROUP}" "${OX_ROUTER_DB}"
        chmod 600 "${OX_ROUTER_DB}"
    fi

    for dir in \
        "${OX_HOME}" \
        "${OX_BACKUP_DIR}" \
        "${OX_CRASH_DIR}"
    do

        if [[ -d "${dir}" ]]; then

            chown -R "${OX_USER}:${OX_GROUP}" "${dir}"

            chmod 750 "${dir}"

        fi

    done

    if [[ -d "${OX_SSH_DIR}" ]]; then

        chown -R "${OX_USER}:${OX_GROUP}" \
            "${OX_SSH_DIR}"

        chmod 700 "${OX_SSH_DIR}"

        if [[ -f "${OX_KNOWN_HOSTS}" ]]; then

            chmod 600 "${OX_KNOWN_HOSTS}"

            chown "${OX_USER}:${OX_GROUP}" \
                "${OX_KNOWN_HOSTS}"

        fi

    fi

    if [[ -d "${OX_GIT_REPO}" ]]; then

        chown -R "${OX_USER}:${OX_GROUP}" \
            "${OX_GIT_REPO}"

        chmod 750 "${OX_GIT_REPO}"

    fi

    for helper in \
        oxidized-add \
        oxidized-list \
        oxidized-remove \
        oxidized-test \
        oxidized-models
    do

        local path="/usr/local/bin/${helper}"

        if [[ -f "${path}" ]]; then

            chown root:root "${path}"
            chmod 755 "${path}"

        fi

    done

    log "Permissões ajustadas."
}

###############################################################################
# START
###############################################################################

start_service() {

    section "INICIANDO OXIDIZED"

    systemctl daemon-reload

    systemctl enable oxidized

    systemctl restart oxidized

    sleep 5

    if ! systemctl is-active --quiet oxidized; then

        error "Oxidized não iniciou."

        journalctl \
            -u oxidized \
            -n 100 \
            --no-pager

        die "Falha ao iniciar o serviço."

    fi

    log "Oxidized está ativo."
}

###############################################################################
# TEST WEB
###############################################################################

test_web() {

    section "TESTANDO WEB"

    local attempts=0
    local max_attempts=15

    while (( attempts < max_attempts )); do

        if curl \
            --silent \
            --show-error \
            --fail \
            --max-time 3 \
            "http://127.0.0.1:${WEB_PORT}/" \
            >/dev/null 2>&1; then

            log "Oxidized Web respondeu na porta ${WEB_PORT}."

            return 0
        fi

        attempts=$((attempts + 1))

        sleep 1

    done

    warn "O Web não respondeu automaticamente."

    systemctl status oxidized \
        --no-pager \
        -l || true

    return 1
}

###############################################################################
# STATUS
###############################################################################

show_status() {

    section "STATUS FINAL"

    echo

    systemctl \
        --no-pager \
        --full \
        status oxidized || true

    echo
    echo "==========================================================================="
    echo " INSTALAÇÃO CONCLUÍDA"
    echo "==========================================================================="
    echo

    echo "Sistema:"
    echo "  Ubuntu 26.04 LTS"
    echo

    echo "Ruby:"
    echo "  $(ruby -e 'print RUBY_VERSION')"
    echo

    echo "Oxidized:"
    echo "  Versão : ${OXIDIZED_VERSION}"
    echo "  Binário: ${OXIDIZED_BIN}"
    echo "  Serviço: oxidized.service"
    echo

    echo "Oxidized Web:"
    echo "  Versão : ${OXIDIZED_WEB_VERSION}"
    echo "  Escuta : ${WEB_LISTEN}"
    echo "  Porta  : ${WEB_PORT}"
    echo

    if [[ "${WEB_LISTEN}" == "127.0.0.1" ]]; then

        echo "  URL local:"
        echo "    http://127.0.0.1:${WEB_PORT}/"

        echo
        echo "  Para acessar remotamente com segurança:"
        echo "    ssh -L ${WEB_PORT}:127.0.0.1:${WEB_PORT} usuario@servidor"

    else

        echo "  URL:"
        echo "    http://${WEB_LISTEN}:${WEB_PORT}/"

        echo

        warn "O Web está acessível pela rede."
        warn "Recomenda-se restringir a porta no firewall ou usar reverse proxy."

    fi

    echo

    echo "Arquivos:"
    echo "  Config : ${OX_CONFIG}"
    echo "  Devices: ${OX_ROUTER_DB}"
    echo "  Git    : ${OX_CONFIG_REPO}"
    echo "  SSH    : ${OX_KNOWN_HOSTS}"
    echo

    echo "Comandos:"
    echo "  oxidized-list"
    echo "  oxidized-add"
    echo "  oxidized-remove NOME"
    echo "  oxidized-test NOME"
    echo "  oxidized-models"
    echo

    echo "Logs:"
    echo "  journalctl -u oxidized -f"
    echo

    echo "Status:"
    echo "  systemctl status oxidized"
    echo

    echo "==========================================================================="
}

###############################################################################
# MAIN
###############################################################################

main() {

    clear 2>/dev/null || true

    echo
    echo "==========================================================================="
    echo "              OXIDIZED ${OXIDIZED_VERSION}"
    echo "             PROJETO ROOT INSTALLER"
    echo "                 UBUNTU 26.04 LTS"
    echo "==========================================================================="
    echo

    require_root

    detect_os

    detect_ip

    # =========================================================================
    # REPOSITÓRIOS
    # =========================================================================

    configure_repositories

    # =========================================================================
    # DEPENDÊNCIAS
    # =========================================================================

    install_packages

    validate_ruby

    detect_gem_bin

    # =========================================================================
    # USUÁRIO
    # =========================================================================

    create_user

    # =========================================================================
    # GEMS
    # =========================================================================

    install_gems

    create_oxidized_link

    # =========================================================================
    # WEB
    # =========================================================================

    configure_web

    # =========================================================================
    # CONFIGURAÇÃO
    # =========================================================================

    create_router_db

    create_git_repo

    create_config

    create_temp_node

    validate_router_db

    # =========================================================================
    # HELPERS
    # =========================================================================

    install_helpers

    set_helper_ownership

    # =========================================================================
    # PERMISSÕES
    # =========================================================================

    set_permissions

    # =========================================================================
    # SYSTEMD
    # =========================================================================

    create_systemd

    # =========================================================================
    # SERVIÇO
    # =========================================================================

    start_service

    # =========================================================================
    # WEB
    # =========================================================================

    if ! test_web; then
        warn "O serviço está ativo, mas o teste HTTP falhou."
    fi

    # =========================================================================
    # STATUS
    # =========================================================================

    show_status

    echo
    warn "IMPORTANTE:"
    echo
    echo "O equipamento temporário '${TEMP_NAME}' existe somente para garantir"
    echo "que o Oxidized tenha um node durante a instalação."
    echo
    echo "Ao cadastrar o primeiro equipamento real com:"
    echo
    echo "  oxidized-add"
    echo
    echo "ele será removido automaticamente."
    echo
    echo "Se alguma senha real foi exposta durante testes/logs, altere-a."
    echo
}

main "$@"
