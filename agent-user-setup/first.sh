#!/usr/bin/env bash
#
# Первоначальная настройка пользователя agent в WSL.
#
# 1. Установите общий конфиг до запуска:
#      sudo install -o root -g root -m 644 \
#          agent-setup.conf.example /etc/agent-setup.conf
# 2. При необходимости отредактируйте его:
#      sudoedit /etc/agent-setup.conf
# 3. Убедитесь, что диски Windows смонтированы в /mnt/c и /mnt/d.
# 4. Запустите скрипт от root:
#      sudo ./first.sh
# 5. Перезапустите WSL из PowerShell:
#      wsl --shutdown
#
# Скрипт не изменяет права и содержимое каталогов на дисках Windows.
#

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

umask 027

CONFIG_FILE="/etc/agent-setup.conf"
MOUNT_UNIT="/etc/systemd/system/agent-wsl-mounts.service"
MOUNT_SCRIPT="/usr/local/sbin/agent-wsl-mounts"
PRIVATE_DIR_MODE=700

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ ${EUID} -eq 0 ]] || fail 'запустите скрипт через sudo или из root-shell'
[[ -r ${CONFIG_FILE} ]] || fail "конфигурация не найдена: ${CONFIG_FILE}"
[[ $(stat --format='%U:%G:%a' "${CONFIG_FILE}") == root:root:644 ]] ||
    fail "${CONFIG_FILE} должен принадлежать root:root и иметь режим 644"

# Общий конфиг не должен содержать секреты: его читают first.sh, second.sh и setup.sh.
# shellcheck disable=SC1090
source "${CONFIG_FILE}"

: "${MAIN_USERNAME:?MAIN_USERNAME не задан}"
: "${SECOND_USERNAME:?SECOND_USERNAME не задан}"
: "${GIT_NAME:?GIT_NAME не задан}"
: "${GIT_EMAIL:?GIT_EMAIL не задан}"
: "${APT_MIRROR:?APT_MIRROR не задан}"
: "${TZ_VALUE:?TZ_VALUE не задан}"

declare -p AGENT_MOUNT_SOURCES >/dev/null 2>&1 ||
    fail 'AGENT_MOUNT_SOURCES должен быть Bash-массивом'
declare -p AGENT_MOUNT_TARGETS >/dev/null 2>&1 ||
    fail 'AGENT_MOUNT_TARGETS должен быть Bash-массивом'

AGENT_HOME="/home/${SECOND_USERNAME}"
AGENT_GROUP=''
AGENT_UID=''
AGENT_GID=''
SECOND_USER_MISSING=0

FORBIDDEN_GROUPS=(sudo wheel docker lxd libvirt disk shadow adm kvm)
log() {
    printf '\n==> %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

on_error() {
    local exit_code=$?
    printf 'ERROR: command failed at line %s: %s\n' \
        "$1" "$2" >&2
    exit "$exit_code"
}

trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

require_root() {
    [[ ${EUID} -eq 0 ]] || die 'запустите скрипт от root: sudo -i; /root/configure-agent.sh'
}

validate_identifiers() {
    [[ ${MAIN_USERNAME} =~ ^[a-z_][a-z0-9_-]*$ ]] ||
        die "недопустимое Linux-имя: ${MAIN_USERNAME}"
    [[ ${SECOND_USERNAME} =~ ^[a-z_][a-z0-9_-]*$ ]] ||
        die "недопустимое Linux-имя: ${SECOND_USERNAME}"
    [[ ${MAIN_USERNAME} != "${SECOND_USERNAME}" ]] ||
        die 'основной и агентский пользователи должны отличаться'
}

install_dependencies() {
    log 'Установка системных зависимостей и инструментов'

    local apt_files f ls_package icu_package package status missing_packages=()
    local required_packages=(
        build-essential ca-certificates curl wget unzip
        git git-lfs python3 python3-dev python3-venv python3-pip
        python-is-python3 nodejs npm fd-find bat fzf ripgrep jq
        golang-go postgresql-client libssl-dev zlib1g-dev libffi-dev vim tree tzdata
    )
    APT_MIRROR="${APT_MIRROR%/}"
    if apt-cache show eza >/dev/null 2>&1; then
        ls_package=eza
    else
        ls_package=exa
    fi
    required_packages+=("${ls_package}")

    if [[ ${MODE} != apply ]]; then
        for package in "${required_packages[@]}"; do
            status="$(dpkg-query -W -f='${db:Status-Abbrev}' "${package}" 2>/dev/null || true)"
            [[ ${status} == 'ii '* ]] || missing_packages+=("${package}")
        done
        if (( ${#missing_packages[@]} )); then
            printf 'WARNING: отсутствуют пакеты: %s\n' "${missing_packages[*]}"
        else
            printf 'INFO: системные пакеты установлены.\n'
        fi
        command -v fdfind >/dev/null 2>&1 || printf 'WARNING: команда fdfind не найдена.\n'
        command -v batcat >/dev/null 2>&1 || printf 'WARNING: команда batcat не найдена.\n'
        return
    fi

    export DEBIAN_FRONTEND=noninteractive
    shopt -s nullglob
    apt_files=(/etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list)
    for f in "${apt_files[@]}"; do
        # Already configured mirrors are deliberately left untouched.  This
        # keeps apply idempotent and prevents .orig.orig files.
        if grep -qE "https?://([^[:space:]/]+\\.)?(ubuntu\\.com|kernel\\.org)/ubuntu" "${f}" 2>/dev/null; then
            [[ -e "${f}.orig" ]] || cp "${f}" "${f}.orig"
            sed -i -E \
                -e "s|https?://[^[:space:]/]*\\.ubuntu\\.com/ubuntu-ports/?|${APT_MIRROR}-ports/|g" \
                -e "s|https?://[^[:space:]/]*\\.kernel\\.org/ubuntu-ports/?|${APT_MIRROR}-ports/|g" \
                -e "s|https?://[^[:space:]/]*\\.ubuntu\\.com/ubuntu/?|${APT_MIRROR}/|g" \
                -e "s|https?://[^[:space:]/]*\\.kernel\\.org/ubuntu/?|${APT_MIRROR}/|g" \
                "${f}"
        elif grep -Fq "${APT_MIRROR}" "${f}" 2>/dev/null; then
            printf 'INFO: APT mirror already configured in %s.\n' "${f}"
        fi
    done
    shopt -u nullglob
    printf 'Acquire::Retries "5";\nAcquire::http::Timeout "60";\nAcquire::https::Timeout "60";\n' > /etc/apt/apt.conf.d/99retry
    apt-get update
    apt-get install -y --no-install-recommends \
        "${required_packages[@]}"
    icu_package="$(apt-cache search --names-only '^libicu[0-9]+$' | awk '{print $1}' | sort -V | tail -n1)"
    if [[ -n ${icu_package} ]] && apt-get install --dry-run "${icu_package}" >/dev/null 2>&1; then
        apt-get install -y "${icu_package}"
    fi
    apt-get clean
    command -v fdfind >/dev/null 2>&1 && ln -sf "$(command -v fdfind)" /usr/local/bin/fd
    command -v batcat >/dev/null 2>&1 && ln -sf "$(command -v batcat)" /usr/local/bin/bat
    ln -snf "/usr/share/zoneinfo/${TZ_VALUE}" /etc/localtime
    printf '%s\n' "${TZ_VALUE}" > /etc/timezone
}


ensure_users() {
    log 'Проверка пользователей'
    getent passwd "${MAIN_USERNAME}" >/dev/null ||
        die "основной Linux-пользователь не найден: ${MAIN_USERNAME}"
    if getent passwd "${SECOND_USERNAME}" >/dev/null; then
        if [[ ${MODE} == apply ]]; then
            usermod --shell /bin/bash "${SECOND_USERNAME}"
        else
            printf 'INFO: пользователь %s существует; изменения не требуются.\n' "${SECOND_USERNAME}"
        fi
        return
    fi
    if [[ ${MODE} != apply ]]; then
        printf 'WARNING: агентский пользователь не найден: %s\n' "${SECOND_USERNAME}"
        SECOND_USER_MISSING=1
        return
    fi
    useradd --create-home --shell /bin/bash "${SECOND_USERNAME}"
    printf 'INFO: пользователь %s создан; пароль не задан, вход выполняется через wsl --user.\n' \
        "${SECOND_USERNAME}"
}


remove_agent_sudo() {
    log "Проверка sudo-доступа у ${SECOND_USERNAME}"
    local sudoers_file="/etc/sudoers.d/${SECOND_USERNAME}"
    if [[ ${MODE} != apply ]]; then
        [[ ! -e ${sudoers_file} ]] || printf 'WARNING: найден sudoers-файл: %s\n' "${sudoers_file}"
        if getent group sudo >/dev/null 2>&1 && id -nG "${SECOND_USERNAME}" | grep -qw sudo; then
            printf 'WARNING: %s состоит в группе sudo.\n' "${SECOND_USERNAME}"
        fi
        return
    fi
    if getent group sudo >/dev/null 2>&1; then
        gpasswd --delete "${SECOND_USERNAME}" sudo >/dev/null 2>&1 || true
    fi
    rm -f "${sudoers_file}"
    if command -v visudo >/dev/null 2>&1; then
        visudo --check
    fi
}


assert_no_privileged_groups() {
    log 'Проверка привилегированных групп'

    local groups forbidden
    groups=" $(id --groups --name "${SECOND_USERNAME}") "

    for forbidden in "${FORBIDDEN_GROUPS[@]}"; do
        if [[ ${groups} == *" ${forbidden} "* ]]; then
            die "${SECOND_USERNAME} состоит в привилегированной группе: ${forbidden}"
        fi
    done
}

assert_no_sudo_access() {
    log 'Проверка sudo-доступа'

    local sudo_listing sudo_status

    if sudo_listing="$(sudo --non-interactive --list --user "${SECOND_USERNAME}" 2>&1)"; then
        sudo_status=0
    else
        sudo_status=$?
    fi

    if [[ ${sudo_status} -eq 0 ||
          ${sudo_listing} =~ 'may run sudo' ||
          ${sudo_listing} =~ \([[:space:]]*ALL ]]; then
        printf '%s\n' "${sudo_listing}" >&2
        die "у ${SECOND_USERNAME} остался sudo-доступ"
    fi
}

resolve_agent_ids() {
    AGENT_GROUP="$(id --group --name "${SECOND_USERNAME}")"
    AGENT_UID="$(id --user "${SECOND_USERNAME}")"
    AGENT_GID="$(id --group "${SECOND_USERNAME}")"
}

validate_mount_config() {
    log 'Проверка конфигурации монтирования'

    (( ${#AGENT_MOUNT_SOURCES[@]} > 0 )) ||
        die 'AGENT_MOUNT_SOURCES не должен быть пустым'
    [[ ${#AGENT_MOUNT_SOURCES[@]} -eq ${#AGENT_MOUNT_TARGETS[@]} ]] ||
        die 'AGENT_MOUNT_SOURCES и AGENT_MOUNT_TARGETS должны иметь одинаковую длину'

    local index source target
    local -A seen_targets=()

    for index in "${!AGENT_MOUNT_SOURCES[@]}"; do
        source="${AGENT_MOUNT_SOURCES[index]}"
        target="${AGENT_MOUNT_TARGETS[index]}"

        # Раздельные шаблоны: один case-паттерн со знаком | неотличим от
        # конвейера для статических анализаторов.
        case "${source}" in
            /mnt/c/*) ;;
            /mnt/d/*) ;;
            *) die "source должен лежать на диске Windows (/mnt/c или /mnt/d): ${source}" ;;
        esac
        [[ -d ${source} ]] ||
            die "source должен быть существующим каталогом: ${source}"

        case "${target}" in
            "${AGENT_HOME}/.agents"|"${AGENT_HOME}/.omp/"*|"${AGENT_HOME}/shared/"*) ;;
            *) die "недопустимая точка монтирования: ${target}" ;;
        esac
        [[ -z ${seen_targets["${target}"]+x} ]] ||
            die "точка монтирования указана повторно: ${target}"
        seen_targets["${target}"]=1
    done
}


# Создаёт каталог вместе с отсутствующими родителями ниже BASE, выставляя
# владельца и режим каждому созданному компоненту. Каталоги выше BASE не трогает.
install_dir_below() {
    local base="$1" path="$2" current="$1" rest part
    [[ ${path} == "${base}"/* ]] || die "путь вне ${base}: ${path}"
    rest="${path#"${base}"/}"
    while [[ -n ${rest} ]]; do
        if [[ ${rest} == */* ]]; then
            part="${rest%%/*}"
            rest="${rest#*/}"
        else
            part="${rest}"
            rest=''
        fi
        # Функция работает от root и создаёт каталоги: компонент . или ..
        # увёл бы создание за пределы BASE.
        case "${part}" in
            .|..) die "недопустимый компонент пути: ${path}" ;;
        esac
        current="${current}/${part}"
        install --directory \
            --owner="${SECOND_USERNAME}" --group="${AGENT_GROUP}" \
            --mode="${PRIVATE_DIR_MODE}" "${current}"
    done
}


prepare_agent_home() {
    log 'Подготовка домашнего каталога agent'

    if [[ ${MODE} != apply ]]; then
        [[ -d ${AGENT_HOME} ]] || die "домашний каталог не найден: ${AGENT_HOME}"
        printf 'INFO: check mode; домашний каталог не изменяется.\n'
        return
    fi

    [[ -d ${AGENT_HOME} ]] || die "домашний каталог не найден: ${AGENT_HOME}"

    local index target

    chown "${SECOND_USERNAME}:${AGENT_GROUP}" "${AGENT_HOME}"
    chmod "${PRIVATE_DIR_MODE}" "${AGENT_HOME}"

    for target in .config .cache .local work shared .omp; do
        install --directory \
            --owner="${SECOND_USERNAME}" --group="${AGENT_GROUP}" \
            --mode="${PRIVATE_DIR_MODE}" "${AGENT_HOME}/${target}"
    done

    for index in "${!AGENT_MOUNT_SOURCES[@]}"; do
        install_dir_below "${AGENT_HOME}" "${AGENT_MOUNT_TARGETS[index]}"
    done
}


configure_git_for_user() {
    local username="$1" home
    home="$(getent passwd "${username}" | cut -d: -f6)"

    runuser --user "${username}" -- env HOME="${home}" \
        git config --global user.name "${GIT_NAME}"
    runuser --user "${username}" -- env HOME="${home}" \
        git config --global user.email "${GIT_EMAIL}"
    runuser --user "${username}" -- env HOME="${home}" \
        git config --global core.autocrlf input
    runuser --user "${username}" -- env HOME="${home}" \
        git config --global core.sharedRepository world
    runuser --user "${username}" -- env HOME="${home}" \
        git config --global init.defaultBranch main
}

configure_git() {
    log 'Настройка Git'
    if [[ ${MODE} != apply ]]; then
        printf 'INFO: check mode; Git-конфигурация не изменяется.\n'
        return
    fi
    configure_git_for_user "${MAIN_USERNAME}"
    configure_git_for_user "${SECOND_USERNAME}"
}


install_mount_script() {
    log 'Установка root-скрипта монтирования'
    local tmp path
    tmp="$(mktemp)"

    # Шапка: значения, известные только инсталлятору, подставляем сразу.
    {
        printf '#!/usr/bin/env bash\n\n'
        printf 'set -Eeuo pipefail\n'
        printf 'umask 027\n\n'
        printf 'AGENT_HOME=%q\n' "${AGENT_HOME}"
        printf 'AGENT_USER=%q\n' "${SECOND_USERNAME}"
        printf 'AGENT_GROUP=%q\n' "${AGENT_GROUP}"
        printf 'AGENT_UID=%q\n' "${AGENT_UID}"
        printf 'AGENT_GID=%q\n' "${AGENT_GID}"
    } > "${tmp}"

    cat >> "${tmp}" <<'EOF'

SOURCE_PATHS=(
EOF
    for path in "${AGENT_MOUNT_SOURCES[@]}"; do
        printf '    %q\n' "${path}" >> "${tmp}"
    done
    cat >> "${tmp}" <<'EOF'
)
TARGET_PATHS=(
EOF
    for path in "${AGENT_MOUNT_TARGETS[@]}"; do
        printf '    %q\n' "${path}" >> "${tmp}"
    done
    cat >> "${tmp}" <<'EOF'
)
[[ ${#SOURCE_PATHS[@]} -eq ${#TARGET_PATHS[@]} ]] || {
    printf 'Mount source and target lists have different lengths\n' >&2
    exit 1
}

# Создаёт каталог вместе с отсутствующими родителями ниже AGENT_HOME.
ensure_dir_below() {
    local path="$1" current="$AGENT_HOME" rest part
    [[ "$path" == "$AGENT_HOME"/* ]] || {
        printf 'Mount target outside agent home: %s\n' "$path" >&2
        return 1
    }
    rest="${path#"$AGENT_HOME"/}"
    while [[ -n "$rest" ]]; do
        if [[ "$rest" == */* ]]; then
            part="${rest%%/*}"
            rest="${rest#*/}"
        else
            part="$rest"
            rest=''
        fi
        case "$part" in
            .|..) printf 'Invalid path component in mount target: %s\n' "$path" >&2; return 1 ;;
        esac
        current="$current/$part"
        install --directory --owner="$AGENT_USER" --group="$AGENT_GROUP" --mode=700 "$current"
    done
}

mount_one() {
    local source="$1" target="$2" win_source

    [[ -d "$source" ]] || {
        printf 'Invalid mount source, expected a directory: %s\n' "$source" >&2
        return 1
    }

    case "$source" in
        /mnt/c/*) win_source="C:${source#/mnt/c}" ;;
        /mnt/d/*) win_source="D:${source#/mnt/d}" ;;
        *) printf 'Unsupported mount source: %s\n' "$source" >&2; return 1 ;;
    esac

    if mountpoint --quiet "$target"; then
        return 0
    fi

    ensure_dir_below "$target" || return 1

    mount -t drvfs "$win_source" "$target" \
        -o "metadata,uid=${AGENT_UID},gid=${AGENT_GID},umask=077"

    chown "${AGENT_UID}:${AGENT_GID}" "$target"
    chmod 700 "$target"
}

for index in "${!SOURCE_PATHS[@]}"; do
    mount_one "${SOURCE_PATHS[$index]}" "${TARGET_PATHS[$index]}"
done
EOF

    if [[ ! -f ${MOUNT_SCRIPT} ]] || ! cmp -s "${tmp}" "${MOUNT_SCRIPT}"; then
        if [[ ${MODE} == apply ]]; then
            install -o root -g root -m 700 "${tmp}" "${MOUNT_SCRIPT}"
        else
            printf 'WARNING: root-скрипт отсутствует или требует обновления: %s\n' "${MOUNT_SCRIPT}"
        fi
    else
        printf 'INFO: root-скрипт актуален.\n'
    fi
    rm -f "${tmp}"
}


install_systemd_unit() {
    log 'Установка systemd-сервиса монтирования'
    local tmp source rest drive candidate
    local -a candidates=() mount_roots=()
    tmp="$(mktemp)"

    # Корни дисков, которые сервис обязан дождаться до старта.
    for source in "${AGENT_MOUNT_SOURCES[@]}"; do
        rest="${source#/}"
        drive="${rest#*/}"
        candidates+=("/${rest%%/*}/${drive%%/*}")
    done
    while IFS= read -r candidate; do
        mount_roots+=("${candidate}")
    done < <(printf '%s\n' "${candidates[@]}" | sort --unique)

    {
        printf '[Unit]\n'
        printf 'Description=Mount shared Windows directories for %s\n' "${SECOND_USERNAME}"
        printf 'After=local-fs.target\n'
        printf 'RequiresMountsFor=%s\n' "${mount_roots[*]}"
        printf '\n[Service]\n'
        printf 'Type=oneshot\n'
        printf 'ExecStart=%s\n' "${MOUNT_SCRIPT}"
        printf 'RemainAfterExit=yes\n'
        printf '\n[Install]\n'
        printf 'WantedBy=multi-user.target\n'
    } > "${tmp}"

    if [[ -f ${MOUNT_UNIT} ]] && cmp -s "${tmp}" "${MOUNT_UNIT}"; then
        printf 'INFO: systemd unit актуален.\n'
    elif [[ ${MODE} == apply ]]; then
        install -o root -g root -m 644 "${tmp}" "${MOUNT_UNIT}"
    else
        printf 'WARNING: systemd unit отсутствует или требует обновления.\n'
    fi
    rm -f "${tmp}"

    if [[ ${MODE} == apply && -d /run/systemd/system ]]; then
        systemctl daemon-reload
        systemctl enable agent-wsl-mounts.service
        systemctl restart agent-wsl-mounts.service
    elif [[ ${MODE} == check && -d /run/systemd/system ]]; then
        systemctl is-enabled agent-wsl-mounts.service >/dev/null 2>&1 ||
            printf 'WARNING: systemd unit не включён.\n'
    elif [[ ${MODE} == apply ]]; then
        printf 'INFO: systemd не запущен; сервис будет активирован после перезапуска WSL.\n'
    fi
}


write_checks() {
    log 'Проверка итоговых прав'
    assert_no_privileged_groups
    assert_no_sudo_access

    if [[ ${MODE} == apply ]]; then
        printf '\nНастройка выполнена.\n'
    else
        printf '\nПроверка завершена; изменения не выполнялись.\n'
    fi
}


main() {
    require_root
    validate_identifiers
    validate_mount_config
    install_dependencies
    ensure_users
    if (( SECOND_USER_MISSING )); then
        printf 'WARNING: проверки, требующие пользователя %s, пропущены.\n' "${SECOND_USERNAME}"
        return
    fi
    resolve_agent_ids
    remove_agent_sudo
    assert_no_privileged_groups
    assert_no_sudo_access
    prepare_agent_home
    configure_git
    install_mount_script
    install_systemd_unit
    write_checks
}

main "$@"
