#!/usr/bin/env bash
set -Eeuo pipefail
MODE="${1:-check}"
if (( $# > 1 )); then
    printf 'Usage: %s [check|apply]\n' "$0" >&2
    exit 2
fi
case "${MODE}" in
    check|apply) ;;
    *) printf 'Usage: %s [check|apply]\n' "$0" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="/etc/agent-setup.conf"
[[ -r ${CONFIG_FILE} ]] || {
    printf 'ERROR: конфигурация не найдена: %s\n' "${CONFIG_FILE}" >&2
    exit 1
}
# shellcheck disable=SC1090
source "${CONFIG_FILE}"

: "${SECOND_USERNAME:?SECOND_USERNAME не задан}"

[[ $(id --user --name) == "${SECOND_USERNAME}" ]] || {
    printf 'ERROR: запустите second.sh от имени %s\n' "${SECOND_USERNAME}" >&2
    exit 1
}

# Запуск пользовательского скрипта без root в выбранном режиме.
if [[ ${MODE} == apply ]]; then
    bash "${SCRIPT_DIR}/setup.sh" apply
    printf 'Run: source ~/.bashrc\n'
else
    bash "${SCRIPT_DIR}/setup.sh" check
fi

printf '\n===== Проверка пользовательских инструментов =====\n'
for command_name in python fd bat eza fzf rg jq git go psql node npm pnpm bun uv dotnet dotnet-ef csharp-ls omp; do
    command_path="$(command -v "${command_name}" 2>/dev/null || true)"
    printf '  %-14s %s\n' "${command_name}" "${command_path:-НЕ НАЙДЕН}"
done
