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


CONFIG_FILE="/etc/agent-setup.conf"
[[ -r ${CONFIG_FILE} ]] || {
    printf 'ERROR: конфигурация не найдена: %s\n' "${CONFIG_FILE}" >&2
    exit 1
}
# shellcheck disable=SC1090
source "${CONFIG_FILE}"

: "${MAIN_USERNAME:?MAIN_USERNAME не задан}"
: "${SECOND_USERNAME:?SECOND_USERNAME не задан}"
: "${WINDOWS_USERNAME:?WINDOWS_USERNAME не задан}"

[[ $(id --user --name) == "${SECOND_USERNAME}" ]] || {
    printf 'ERROR: запустите second.sh от имени %s\n' "${SECOND_USERNAME}" >&2
    exit 1
}


# Проверка текущих монтирований drvfs.
findmnt --type drvfs || true
ls -ld /mnt/c /mnt/d

# Проверка разделения прав между пользователями.
if ls /mnt/c >/dev/null 2>&1; then
    echo "WARNING: ${SECOND_USERNAME} видит /mnt/c напрямую"
else
    echo "Access denied as expected"
fi
if [[ ${MODE} == apply ]]; then
    touch /mnt/d/test && echo "Write access confirmed"
    rm /mnt/d/test
else
    [[ -w /mnt/d ]] && echo "Write access available (no file created)" ||
        printf 'WARNING: нет записи в /mnt/d\n' >&2
fi


# Bind-монтирования создаёт root-owned systemd-сервис из first.sh.
for target in "${AGENT_MOUNT_TARGETS[@]}"; do
    mountpoint --quiet "${target}" ||
        printf 'WARNING: точка ещё не смонтирована: %s\n' "${target}" >&2
done

# Запуск пользовательского скрипта без root только в apply-режиме.
if [[ ${MODE} == apply ]]; then
    bash setup.sh apply
    # Перезапуск оболочки для обновления PATH и переменного окружения.
    exec bash
fi

printf '\n===== Проверка пользовательских инструментов =====\n'
for command_name in python fd bat eza fzf rg jq git go psql node npm pnpm bun uv dotnet dotnet-ef csharp-ls; do
    command_path="$(command -v "${command_name}" 2>/dev/null || true)"
    printf '  %-14s %s\n' "${command_name}" "${command_path:-НЕ НАЙДЕН}"
done