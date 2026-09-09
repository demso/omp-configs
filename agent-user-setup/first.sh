#!/usr/bin/env bash
#
# Первоначальная настройка пользователя agent в WSL.
#
# 1. Установите общий конфиг до запуска:
#      sudo install -o root -g root -m 644 \
#          agent-setup.conf.example /etc/agent-setup.conf
# 2. При необходимости отредактируйте его:
#      sudoedit /etc/agent-setup.conf
# 3. Убедитесь, что C: смонтирован в /mnt/c через DrvFs с metadata.
# 4. Запустите скрипт от root:
#      sudo ./first.sh
# 5. Проверьте /etc/fstab и /etc/wsl.conf из итогового сообщения.
# 6. Перезапустите WSL из PowerShell:
#      wsl --shutdown
#
# Скрипт не изменяет права и содержимое /mnt/d.
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
: "${WINDOWS_USERNAME:?WINDOWS_USERNAME не задан}"
: "${SECOND_USERNAME:?SECOND_USERNAME не задан}"
: "${GIT_NAME:?GIT_NAME не задан}"
: "${GIT_EMAIL:?GIT_EMAIL не задан}"
: "${SHARE_GROUP:?SHARE_GROUP не задан}"
: "${APT_MIRROR:?APT_MIRROR не задан}"
: "${TZ_VALUE:?TZ_VALUE не задан}"

declare -p C_ALLOWED_RELATIVE_PATHS >/dev/null 2>&1 ||
    fail 'C_ALLOWED_RELATIVE_PATHS должен быть Bash-массивом'
declare -p AGENT_MOUNT_TARGETS >/dev/null 2>&1 ||
    fail 'AGENT_MOUNT_TARGETS должен быть Bash-массивом'


AGENT_HOME="/home/${SECOND_USERNAME}"
C_MOUNT="/mnt/c"
WINDOWS_PROFILE="${C_MOUNT}/Users/${WINDOWS_USERNAME}"

C_ALLOWED_PATHS=()
for relative_path in "${C_ALLOWED_RELATIVE_PATHS[@]}"; do
    [[ ${relative_path} != /* && ${relative_path} != *..* ]] ||
        fail "недопустимый относительный путь в конфигурации: ${relative_path}"
    C_ALLOWED_PATHS+=("${WINDOWS_PROFILE}/${relative_path}")
done

[[ ${#C_ALLOWED_PATHS[@]} -eq ${#AGENT_MOUNT_TARGETS[@]} ]] ||
    fail 'C_ALLOWED_RELATIVE_PATHS и AGENT_MOUNT_TARGETS должны иметь одинаковую длину'

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
    [[ ${SHARE_GROUP} =~ ^[a-z_][a-z0-9_-]*$ ]] ||
        die "недопустимое имя группы: ${SHARE_GROUP}"
    [[ ${MAIN_USERNAME} != "${SECOND_USERNAME}" ]] ||
        die 'основной и агентский пользователи должны отличаться'

    # The value is embedded into a root-owned generated shell script.
    [[ ${WINDOWS_USERNAME} =~ ^[A-Za-z0-9._-]+$ ]] ||
        die 'WINDOWS_USERNAME должен содержать только латинские буквы, цифры, точку, _ или -'
}

install_dependencies() {
    log 'Установка системных зависимостей и инструментов'

    if [[ ${MODE} != apply ]]; then
        printf 'INFO: check mode; системные зависимости не изменяются.\n'
        return
    fi

    export DEBIAN_FRONTEND=noninteractive
    local apt_files f ls_package icu_package
    APT_MIRROR="${APT_MIRROR%/}"
    shopt -s nullglob
    apt_files=(/etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list)
    for f in "${apt_files[@]}"; do
        grep -qE '(ubuntu\.com|kernel\.org)/ubuntu' "${f}" 2>/dev/null || continue
        [[ -e "${f}.orig" ]] || cp "${f}" "${f}.orig"
        sed -i -E \
            -e "s|https?://[^[:space:]/]*\.ubuntu\.com/ubuntu-ports/?|${APT_MIRROR}-ports/|g" \
            -e "s|https?://[^[:space:]/]*\.kernel\.org/ubuntu-ports/?|${APT_MIRROR}-ports/|g" \
            -e "s|https?://[^[:space:]/]*\.ubuntu\.com/ubuntu/?|${APT_MIRROR}/|g" \
            -e "s|https?://[^[:space:]/]*\.kernel\.org/ubuntu/?|${APT_MIRROR}/|g" \
            "${f}"
    done
    shopt -u nullglob
    printf 'Acquire::Retries "5";\nAcquire::http::Timeout "60";\nAcquire::https::Timeout "60";\n' > /etc/apt/apt.conf.d/99retry
    apt-get update
    if apt-get install --dry-run exa >/dev/null 2>&1; then
        ls_package=exa
    else
        ls_package=eza
    fi
    apt-get install -y --no-install-recommends \
        acl build-essential ca-certificates curl wget unzip \
        git git-lfs python3 python3-dev python3-venv python3-pip \
        python-is-python3 nodejs npm fd-find bat fzf ripgrep jq \
        "${ls_package}" golang-go postgresql-client \
        libssl-dev zlib1g-dev libffi-dev vim tree tzdata
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
    elif [[ ${MODE} == apply ]]; then
        useradd --create-home --shell /bin/bash "${SECOND_USERNAME}"
        passwd "${SECOND_USERNAME}"
    else
        die "агентский пользователь не найден: ${SECOND_USERNAME}"
    fi
}


remove_agent_sudo() {
    log "Удаление sudo-доступа у ${SECOND_USERNAME}"
    if [[ ${MODE} != apply ]]; then
        printf 'INFO: check mode; sudo-конфигурация не изменяется.\n'
        return
    fi
    if getent group sudo >/dev/null 2>&1; then
        gpasswd --delete "${SECOND_USERNAME}" sudo >/dev/null 2>&1 || true
    fi
    rm -f "/etc/sudoers.d/${SECOND_USERNAME}"
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
    set +e
    sudo_listing="$(sudo --non-interactive --list --user "${SECOND_USERNAME}" 2>&1)"
    sudo_status=$?
    set -e

    if [[ ${sudo_status} -eq 0 || ${sudo_listing} =~ 'may run sudo' || ${sudo_listing} =~ \([[:space:]]*ALL ]]; then
        printf '%s\n' "${sudo_listing}" >&2
        die "у ${SECOND_USERNAME} остался sudo-доступ"
    fi
}

ensure_share_group() {
    log 'Настройка группы доступа к выбранным каталогам C:'
    if [[ ${MODE} == apply ]]; then
        if ! getent group "${SHARE_GROUP}" >/dev/null 2>&1; then
            groupadd --system "${SHARE_GROUP}"
        fi
        usermod --append --groups "${SHARE_GROUP}" "${SECOND_USERNAME}"
    else
        getent group "${SHARE_GROUP}" >/dev/null 2>&1 ||
            die "группа не найдена: ${SHARE_GROUP}"
        [[ " $(id --groups --name "${SECOND_USERNAME}") " == *" ${SHARE_GROUP} "* ]] ||
            die "${SECOND_USERNAME} не состоит в ${SHARE_GROUP}"
    fi
}


require_c_mount() {
    log 'Проверка монтирования C:'

    mountpoint --quiet "${C_MOUNT}" ||
        die "${C_MOUNT} не смонтирован; сначала настройте /etc/fstab и перезапустите WSL"

    local fs_type options main_uid main_gid
    fs_type="$(findmnt --noheadings --output FSTYPE "${C_MOUNT}")"
    options="$(findmnt --noheadings --output OPTIONS "${C_MOUNT}")"

    [[ ${fs_type} == drvfs ]] ||
        die "${C_MOUNT} имеет тип ${fs_type}, ожидался drvfs"
    [[ ${options} == *metadata* ]] ||
        die "${C_MOUNT} смонтирован без metadata"

    main_uid="$(id --user "${MAIN_USERNAME}")"
    main_gid="$(id --group "${MAIN_USERNAME}")"
    [[ ",${options}," == *",uid=${main_uid},"* ]] ||
        die "uid монтирования ${C_MOUNT} не совпадает с UID ${MAIN_USERNAME} (${main_uid})"
    [[ ",${options}," == *",gid=${main_gid},"* ]] ||
        die "gid монтирования ${C_MOUNT} не совпадает с GID ${MAIN_USERNAME} (${main_gid})"
}

validate_allowed_paths() {
    log 'Проверка разрешённых каталогов C:'

    local base base_real resolved path
    base="${C_MOUNT}/Users/${WINDOWS_USERNAME}"
    [[ -d ${base} ]] || die "профиль Windows не найден: ${base}"
    base_real="$(realpath --canonicalize-existing "${base}")"

    for path in "${C_ALLOWED_PATHS[@]}"; do
        [[ -d ${path} ]] || die "каталог не найден: ${path}"
        [[ ! -L ${path} ]] || die "разрешённый source-путь не должен быть symlink: ${path}"

        resolved="$(realpath --canonicalize-existing "${path}")"
        [[ ${resolved} == "${base_real}"/* ]] ||
            die "каталог выходит за пределы профиля Windows: ${path}"

        if [[ -n "$(find "${path}" -xdev -type l -print -quit)" ]]; then
            die "разрешённый каталог содержит symlink/reparse point: ${path}"
        fi
    done
}

apply_share_acl() {
    log 'Настройка прав выбранных каталогов C:'
    if [[ ${MODE} != apply ]]; then
        printf 'INFO: check mode; права выбранных каталогов не изменяются.\n'
        return
    fi
    local path
    for path in "${C_ALLOWED_PATHS[@]}"; do
        find "${path}" -xdev -exec chown "${MAIN_USERNAME}:${SHARE_GROUP}" {} +
        find "${path}" -xdev -type d -exec chmod u+rwx,g+rwx,o-rwx {} +
        find "${path}" -xdev -type f -exec chmod u+rw,g+rw,o-rwx {} +
        find "${path}" -xdev -type d -exec chmod g+s {} +
    done
    chmod 700 "${C_MOUNT}"
}


unmount_existing_targets() {
    log 'Очистка старых bind-монтирований'
    if [[ ${MODE} != apply ]]; then
        printf 'INFO: check mode; существующие bind-монтирования не изменяются.\n'
        return
    fi
    local path
    for path in "${AGENT_MOUNT_TARGETS[@]}"; do
        if mountpoint --quiet "${path}"; then
            umount "${path}"
        fi
    done
}


prepare_agent_home() {
    log 'Подготовка домашнего каталога agent'
    [[ -d ${AGENT_HOME} ]] || die "домашний каталог не найден: ${AGENT_HOME}"
    if [[ ${MODE} != apply ]]; then
        printf 'INFO: check mode; домашний каталог не изменяется.\n'
        return
    fi
    local agent_group
    agent_group="$(id --group --name "${SECOND_USERNAME}")"
    chown root:"${agent_group}" "${AGENT_HOME}"
    chmod 710 "${AGENT_HOME}"
    setfacl --modify \
        "u:${MAIN_USERNAME}:rwx,g::--x,m::rwx,o::---" \
        "${AGENT_HOME}"
    setfacl --modify \
        "d:u:${MAIN_USERNAME}:rwx,d:g::--x,d:m::rwx,d:o::---" \
        "${AGENT_HOME}"
    find "${AGENT_HOME}" -xdev \
        -path "${AGENT_HOME}/.omp" -prune -o \
        -path "${AGENT_HOME}/.agents" -prune -o \
        -path "${AGENT_HOME}/shared" -prune -o \
        -exec setfacl --modify "u:${MAIN_USERNAME}:rwX,m::rwX,o::---" {} +
    local path
    install --directory --owner="${SECOND_USERNAME}" --group="${agent_group}" \
        --mode=700 \
        "${AGENT_HOME}/.config" "${AGENT_HOME}/.cache" "${AGENT_HOME}/.local" "${AGENT_HOME}/work"
    for path in "${AGENT_HOME}/.config" "${AGENT_HOME}/.cache" "${AGENT_HOME}/.local" "${AGENT_HOME}/work"; do
        setfacl --modify "u:${MAIN_USERNAME}:rwx,m::rwx" "${path}"
        setfacl --modify "d:u:${MAIN_USERNAME}:rwx,d:m::rwx,d:o::---" "${path}"
    done
    install --directory --owner=root --group=root --mode=700 \
        "${AGENT_HOME}/shared" "${AGENT_HOME}/.omp" "${AGENT_HOME}/.agents" \
        "${AGENT_HOME}/shared/downloads" "${AGENT_HOME}/shared/screenshots"
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
    log 'Установка root-скрипта bind-монтирования'
    if [[ ${MODE} != apply ]]; then
        [[ -x /usr/local/sbin/agent-wsl-mounts ]] ||
            printf 'WARNING: root-скрипт bind-монтирования ещё не установлен.\n' >&2
        return
    fi
    local script_path=/usr/local/sbin/agent-wsl-mounts
    cat > "${script_path}" <<EOF
#!/usr/bin/env bash

set -Eeuo pipefail
umask 027

SOURCE_PATHS=(
    "${C_ALLOWED_PATHS[0]}"
    "${C_ALLOWED_PATHS[1]}"
    "${C_ALLOWED_PATHS[2]}"
    "${C_ALLOWED_PATHS[3]}"
)

TARGET_PATHS=(
    "${AGENT_MOUNT_TARGETS[0]}"
    "${AGENT_MOUNT_TARGETS[1]}"
    "${AGENT_MOUNT_TARGETS[2]}"
    "${AGENT_MOUNT_TARGETS[3]}"
)

[[ \${#SOURCE_PATHS[@]} -eq \${#TARGET_PATHS[@]} ]] || exit 1

mount_one() {
    local source="\$1"
    local target="\$2"
    [[ -d "\$source" ]] || {
        printf 'Source directory does not exist: %s\\n' "\$source" >&2
        return 1
    }
    [[ -d "\$target" && ! -L "\$target" ]] || {
        printf 'Invalid mount target: %s\\n' "\$target" >&2
        return 1
    }
    if mountpoint --quiet "\$target"; then return 0; fi
    mount --bind "\$source" "\$target"
}

chmod 700 /mnt/c
for index in "\${!SOURCE_PATHS[@]}"; do
    mount_one "\${SOURCE_PATHS[\$index]}" "\${TARGET_PATHS[\$index]}"
done
EOF
    chown root:root "${script_path}"
    chmod 700 "${script_path}"
}


install_systemd_unit() {
    log 'Установка systemd-сервиса bind-монтирования'
    if [[ ${MODE} != apply ]]; then
        [[ -f /etc/systemd/system/agent-wsl-mounts.service ]] ||
            printf 'WARNING: systemd-сервис bind-монтирования ещё не установлен.\n' >&2
        return
    fi
    cat > /etc/systemd/system/agent-wsl-mounts.service <<'EOF'
[Unit]
Description=Mount selected Windows directories for agent
After=local-fs.target
RequiresMountsFor=/mnt/c

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/agent-wsl-mounts
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 /etc/systemd/system/agent-wsl-mounts.service
    if [[ -d /run/systemd/system ]]; then
        systemctl daemon-reload
        systemctl enable agent-wsl-mounts.service
    else
        printf 'INFO: systemd не запущен; сервис будет активирован после перезапуска WSL.\n'
    fi
}


start_mount_service_if_possible() {
    log 'Проверка bind-монтирований'
    if [[ ${MODE} != apply ]]; then
        printf 'INFO: check mode; mount-сервис не запускается.\n'
        return
    fi
    if [[ ! -d /run/systemd/system ]]; then
        printf 'INFO: systemd ещё не запущен; проверка mount-сервиса отложена до перезапуска WSL.\n'
        return
    fi
    systemctl start agent-wsl-mounts.service
    local path
    for path in "${AGENT_MOUNT_TARGETS[@]}"; do
        mountpoint --quiet "${path}" || die "каталог не смонтирован: ${path}"
    done
    if runuser --user "${SECOND_USERNAME}" -- test -x "${C_MOUNT}"; then
        die "${SECOND_USERNAME} может напрямую проходить в ${C_MOUNT}"
    fi
    for path in "${AGENT_MOUNT_TARGETS[@]}"; do
        runuser --user "${SECOND_USERNAME}" -- test -r "${path}" || die "${SECOND_USERNAME} не может читать разрешённый каталог: ${path}"
        runuser --user "${SECOND_USERNAME}" -- test -w "${path}" || die "${SECOND_USERNAME} не может писать в разрешённый каталог: ${path}"
    done
}


write_checks() {
    log 'Проверка итоговых прав'
    assert_no_privileged_groups
    assert_no_sudo_access
    start_mount_service_if_possible
    [[ " $(id --groups --name "${SECOND_USERNAME}") " == *" ${SHARE_GROUP} "* ]] ||
        die "${SECOND_USERNAME} не состоит в ${SHARE_GROUP}; нужна новая сессия"
    [[ $(stat --format='%a' "${C_MOUNT}") == 700 ]] ||
        die "${C_MOUNT} не закрыт режимом 700"
    local path
    for path in "${AGENT_MOUNT_TARGETS[@]}"; do
        [[ -d ${path} && ! -L ${path} ]] || die "некорректная точка монтирования: ${path}"
    done
    if [[ ${MODE} == apply ]]; then
        printf '\nНастройка выполнена.\n'
    else
        printf '\nПроверка завершена; изменения не выполнялись.\n'
    fi
    cat <<EOF

Проверьте /etc/fstab:

C: /mnt/c drvfs rw,nofail,noatime,metadata,uid=$(id --user "${MAIN_USERNAME}"),gid=$(id --group "${MAIN_USERNAME}"),umask=000 0 0
D: /mnt/d drvfs rw,nofail,noatime,umask=000 0 0

В /etc/wsl.conf должны быть:

[automount]
mountFsTab=true

[boot]
systemd=true

[user]
default=${MAIN_USERNAME}
Удалите старую строку command=/usr/local/sbin/agent-wsl-boot из /etc/wsl.conf, если она осталась.

После изменения конфигурации выполните в PowerShell:

    wsl --shutdown

После запуска WSL проверьте:

    id ${SECOND_USERNAME}
    sudo -l -U ${SECOND_USERNAME}
    systemctl status agent-wsl-mounts.service
    findmnt -R ${AGENT_HOME}

Затем от имени ${SECOND_USERNAME} запустите:

    ./second.sh

EOF
}


main() {
    require_root
    validate_identifiers
    install_dependencies
    ensure_users
    remove_agent_sudo
    assert_no_privileged_groups
    assert_no_sudo_access
    ensure_share_group
    require_c_mount
    validate_allowed_paths
    apply_share_acl
    unmount_existing_targets
    prepare_agent_home
    configure_git
    install_mount_script
    install_systemd_unit
    write_checks
}

main "$@"
agent-test
