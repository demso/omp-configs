#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.env"
FORCE_INSTALL=0
SERVICE_NAME="ompweb"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
ENV_DIR="/etc/ompweb"
ENV_PATH="${ENV_DIR}/ompweb.env"

usage() {
    printf 'Usage: %s [--force] [path-to-env]\n' "$(basename -- "$0")"
}

if [[ ${1:-} == "--force" ]]; then
    FORCE_INSTALL=1
    shift
fi
if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
    usage
    exit 0
fi
if (( $# > 1 )); then
    usage >&2
    exit 2
fi
CONFIG_FILE="${1:-${CONFIG_FILE}}"

[[ -r ${CONFIG_FILE} ]] || {
    printf 'ERROR: configuration file is not readable: %s\n' "${CONFIG_FILE}" >&2
    exit 1
}
[[ -d /run/systemd/system ]] || {
    printf 'ERROR: systemd is not running. Enable systemd in /etc/wsl.conf and restart WSL.\n' >&2
    exit 1
}

# shellcheck disable=SC1090
source "${CONFIG_FILE}"
: "${OMPWEB_USER:?OMPWEB_USER is not set in ${CONFIG_FILE}}"

OMPWEB_VERSION="${OMPWEB_VERSION:-0.5.0}"
OMPWEB_NPM_REGISTRY="${OMPWEB_NPM_REGISTRY:-https://registry.npmjs.org}"
PORT="${PORT:-30177}"
OMP_WEB_HOSTNAME="${OMP_WEB_HOSTNAME:-127.0.0.1}"
OMP_WEB_PASSWORD="${OMP_WEB_PASSWORD:-}"
OMP_WEB_NO_OPEN="${OMP_WEB_NO_OPEN:-1}"
OMP_WEB_OMP_BIN="${OMP_WEB_OMP_BIN:-}"
PI_CODING_AGENT_DIR="${PI_CODING_AGENT_DIR:-}"
OMP_WEB_STT_ENDPOINT="${OMP_WEB_STT_ENDPOINT:-}"
OMP_WEB_STT_KEY="${OMP_WEB_STT_KEY:-}"
OMP_WEB_STT_MODEL="${OMP_WEB_STT_MODEL:-}"

if [[ ${OMP_WEB_HOSTNAME} == "0.0.0.0" && -z ${OMP_WEB_PASSWORD} ]]; then
    printf 'ERROR: OMP_WEB_PASSWORD is required when OMP_WEB_HOSTNAME=0.0.0.0.\n' >&2
    exit 1
fi

service_home="$(getent passwd -- "${OMPWEB_USER}" | cut -d: -f6)"
service_group="$(id -gn -- "${OMPWEB_USER}")"
if [[ -z ${service_home} ]]; then
    printf 'ERROR: Linux user does not exist: %s\n' "${OMPWEB_USER}" >&2
    exit 1
fi

if (( EUID == 0 )); then
    sudo_cmd=()
else
    sudo_cmd=(sudo)
fi

npm_prefix="$(npm prefix --global)"
ompweb_bin="${npm_prefix%/}/bin/ompweb"
installed_version=""
if [[ -x ${ompweb_bin} ]]; then
    installed_version="$(${ompweb_bin} --version 2>/dev/null || true)"
fi

if (( FORCE_INSTALL == 1 )) || [[ ${installed_version} != "${OMPWEB_VERSION}" ]]; then
    "${sudo_cmd[@]}" npm install --global \
        --registry="${OMPWEB_NPM_REGISTRY}" \
        "@kahme247/ompweb@${OMPWEB_VERSION}"
fi

[[ -x ${ompweb_bin} ]] || {
    printf 'ERROR: ompweb binary is not executable: %s\n' "${ompweb_bin}" >&2
    exit 1
}

escape_value() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"
    printf '%s' "${value}"
}

runtime_env_tmp="$(mktemp)"
unit_tmp="$(mktemp)"
trap 'rm -f -- "${runtime_env_tmp}" "${unit_tmp}"' EXIT

for key in PORT OMP_WEB_HOSTNAME OMP_WEB_PASSWORD OMP_WEB_NO_OPEN \
    OMP_WEB_OMP_BIN PI_CODING_AGENT_DIR OMP_WEB_STT_ENDPOINT \
    OMP_WEB_STT_KEY OMP_WEB_STT_MODEL; do
    [[ -n ${!key} ]] || continue
    printf '%s="%s"\n' "${key}" "$(escape_value "${!key}")"
done > "${runtime_env_tmp}"

cat > "${unit_tmp}" <<EOF
[Unit]
Description=ompweb web service for Oh My Pi
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${OMPWEB_USER}
Group=${service_group}
WorkingDirectory=${service_home}
Environment="HOME=${service_home}"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${service_home}/.local/bin"
EnvironmentFile=${ENV_PATH}
ExecStart=${ompweb_bin}
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

"${sudo_cmd[@]}" install -d -o root -g root -m 0755 "${ENV_DIR}"
"${sudo_cmd[@]}" install -o root -g root -m 0600 "${runtime_env_tmp}" "${ENV_PATH}"
"${sudo_cmd[@]}" install -o root -g root -m 0644 "${unit_tmp}" "${UNIT_PATH}"
"${sudo_cmd[@]}" systemctl daemon-reload
"${sudo_cmd[@]}" systemctl enable "${SERVICE_NAME}.service"
"${sudo_cmd[@]}" systemctl restart "${SERVICE_NAME}.service"

if ! "${sudo_cmd[@]}" systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    printf 'ERROR: %s did not start.\n' "${SERVICE_NAME}.service" >&2
    "${sudo_cmd[@]}" journalctl --no-pager -n 20 -u "${SERVICE_NAME}.service" >&2 || true
    exit 1
fi

printf 'Installed and started %s.service at http://%s:%s\n' \
    "${SERVICE_NAME}" "${OMP_WEB_HOSTNAME}" "${PORT}"
printf 'Configuration: %s\n' "${CONFIG_FILE}"
printf 'Status: sudo systemctl status %s.service\n' "${SERVICE_NAME}"
printf 'Logs:   sudo journalctl -u %s.service -f\n' "${SERVICE_NAME}"
