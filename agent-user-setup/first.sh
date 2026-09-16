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

declare -p AGENT_MOUNT_SOURCES >/dev/null 2>&1 ||
    fail 'AGENT_MOUNT_SOURCES должен быть Bash-массивом'
declare -p AGENT_MOUNT_TARGETS >/dev/null 2>&1 ||
    fail 'AGENT_MOUNT_TARGETS должен быть Bash-массивом'

AGENT_HOME="/home/${SECOND_USERNAME}"
AGENT_CONFIG_ROOT="${AGENT_HOME}/omp-configs"
C_MOUNT="/mnt/c"
WINDOWS_PROFILE="${C_MOUNT}/Users/${WINDOWS_USERNAME}"
SECOND_USER_MISSING=0


[[ ${#AGENT_MOUNT_SOURCES[@]} -eq ${#AGENT_MOUNT_TARGETS[@]} ]] ||
    fail 'AGENT_MOUNT_SOURCES и AGENT_MOUNT_TARGETS должны иметь одинаковую длину'

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

    local apt_files f ls_package icu_package package status missing_packages=()
    local required_packages=(
        acl build-essential ca-certificates curl wget unzip
        git git-lfs python3 python3-dev python3-venv python3-pip
        python-is-python3 nodejs npm fd-find bat fzf ripgrep jq
        golang-go postgresql-client libssl-dev zlib1g-dev libffi-dev vim tree tzdata
    )
    APT_MIRROR="${APT_MIRROR%/}"
    if apt-cache show exa >/dev/null 2>&1; then
        ls_package=eza
    else
        ls_package=eza
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
    elif [[ ${MODE} == apply ]]; then
        useradd --create-home --shell /bin/bash "${SECOND_USERNAME}"
        printf 'INFO: пользователь создан; следующий шаг — единственная интерактивная операция: задайте ему пароль.\n'
        passwd "${SECOND_USERNAME}"
    else
        printf 'WARNING: агентский пользователь не найден: %s\n' "${SECOND_USERNAME}"
        SECOND_USER_MISSING=1
        return
    fi
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

	if [[ ${fs_type} != drvfs ]] &&
	   [[ ${fs_type} != 9p || ${options} != *"aname=drvfs"* ]]; then
		die "${C_MOUNT} имеет тип ${fs_type}, ожидался drvfs или WSL 9p/DrvFs"
	fi
	
    [[ ${options} == *metadata* ]] ||
    die "${C_MOUNT} смонтирован без metadata"

	main_uid="$(id --user "${MAIN_USERNAME}")"
	main_gid="$(id --group "${MAIN_USERNAME}")"

	[[ ";${options};" == *";uid=${main_uid};"* ]] ||
		die "uid монтирования ${C_MOUNT} не совпадает с UID ${MAIN_USERNAME} (${main_uid}) \n${options}"

	[[ ";${options};" == *";gid=${main_gid};"* ]] ||
		die "gid монтирования ${C_MOUNT} не совпадает с GID ${MAIN_USERNAME} (${main_gid}) \n${options}"
}

validate_mount_paths() {
    log 'Проверка источников и точек bind-монтирования'

    local config_real windows_real source source_real target target_real index
    local -A seen_targets=()

    [[ -d ${WINDOWS_PROFILE} ]] || die "профиль Windows не найден: ${WINDOWS_PROFILE}"
    [[ -d ${AGENT_CONFIG_ROOT} ]] || die "репозиторий конфигурации не найден: ${AGENT_CONFIG_ROOT}"

    windows_real="$(realpath --canonicalize-existing "${WINDOWS_PROFILE}")"
    config_real="$(realpath --canonicalize-existing "${AGENT_CONFIG_ROOT}")"

    for index in "${!AGENT_MOUNT_SOURCES[@]}"; do
        source="${AGENT_MOUNT_SOURCES[index]}"
        target="${AGENT_MOUNT_TARGETS[index]}"

        [[ -e ${source} && ! -L ${source} && ( -d ${source} || -f ${source} ) ]] ||
            die "source отсутствует или имеет неподдерживаемый тип: ${source}"

        source_real="$(realpath --canonicalize-existing "${source}")"

        #case "${source_real}" in
        #    "${windows_real}"/*|"${config_real}"/*) ;;
        #    *) die "source находится вне разрешённых корней: ${source}" ;;
        #esac

        case "${target}" in
            "${AGENT_HOME}/.agents"|"${AGENT_HOME}/.omp/"*|"${AGENT_HOME}/shared/"*) ;;
            *) die "недопустимая точка монтирования: ${target}" ;;
        esac

        [[ ! -L ${target} ]] || die "точка монтирования не должна быть symlink: ${target}"

        target_real="$(realpath --canonicalize-missing "${target}")"

        #case "${target_real}" in
        #    "${AGENT_HOME}/.agents"|"${AGENT_HOME}/.omp/"*|"${AGENT_HOME}/shared/"*) ;;
        #    *) die "точка монтирования выходит за пределы разрешённых каталогов: ${target}" ;;
        #esac

        [[ -z ${seen_targets["${target}"]+x} ]] ||
            die "точка монтирования указана повторно: ${target}"

        seen_targets["${target}"]=1

        #if [[ ${source_real} != "${windows_real}"/* ]]; then
        #    runuser --user "${SECOND_USERNAME}" -- test -r "${source}" ||
        #        die "${SECOND_USERNAME} не может читать source: ${source}"
        #fi
    done
}

apply_share_acl() {
    log 'Настройка прав источников из профиля Windows'
    local source owner
    for source in "${AGENT_MOUNT_SOURCES[@]}"; do
        [[ ${source} == "${WINDOWS_PROFILE}"/* ]] || continue
        owner="$(stat --format='%U:%G' "${source}")"
        if [[ ${MODE} != apply ]]; then
            if [[ ${owner} != "${MAIN_USERNAME}:${SHARE_GROUP}" ]]; then
                printf 'WARNING: drift ownership для %s (owner=%s)\n' "${source}" "${owner}"
            else
                printf 'INFO: ownership в порядке: %s\n' "${source}"
            fi
            continue
        fi
        find "${source}" -xdev -exec chown "${MAIN_USERNAME}:${SHARE_GROUP}" {} +
        find "${source}" -xdev -type d -exec chmod u+rwx,g+rwx,o-rwx,g+s {} +
        find "${source}" -xdev -type f -exec chmod u+rw,g+rw,o-rwx {} +
    done
}


unmount_existing_targets() {
    log 'Проверка старых bind-монтирований'
    local path
    local paths=("${AGENT_MOUNT_TARGETS[@]}" "${AGENT_HOME}/.omp")
    for path in "${paths[@]}"; do
        if mountpoint --quiet "${path}"; then
            if [[ ${MODE} == apply ]]; then
                umount "${path}"
                printf 'INFO: размонтировано: %s\n' "${path}"
            else
                printf 'WARNING: точка уже смонтирована (будет перепроверена сервисом): %s\n' "${path}"
            fi
        else
            printf 'INFO: точка не смонтирована: %s\n' "${path}"
        fi
    done
}


prepare_agent_home() {
    log 'Подготовка домашнего каталога agent'
    [[ -d ${AGENT_HOME} ]] || die "домашний каталог не найден: ${AGENT_HOME}"
    if [[ ${MODE} != apply ]]; then
        [[ $(stat --format='%a' "${AGENT_HOME}") == 710 ]] ||
            printf 'WARNING: режим домашнего каталога отличается от 710: %s\n' "${AGENT_HOME}"
        printf 'INFO: check mode; домашний каталог не изменяется.\n'
        return
    fi

    local agent_group index legacy_env path source target
    agent_group="$(id --group --name "${SECOND_USERNAME}")"
    chown root:"${agent_group}" "${AGENT_HOME}"
    chmod 710 "${AGENT_HOME}"
	setfacl -m "u:${SECOND_USERNAME}:rwx" "${AGENT_HOME}"
	setfacl -m "u:${MAIN_USERNAME}:rwx" "${AGENT_HOME}"
	setfacl -m "d:u:${SECOND_USERNAME}:rwx" "${AGENT_HOME}"
	setfacl -m "d:u:${MAIN_USERNAME}:rwx" "${AGENT_HOME}"
    find "${AGENT_HOME}" -xdev \
        -path "${AGENT_HOME}/.omp" -prune -o \
        -path "${AGENT_HOME}/.agents" -prune -o \
        -path "${AGENT_HOME}/shared" -prune -o \
        -exec setfacl --modify "u:${MAIN_USERNAME}:rwX,m::rwX,o::---" {} +

    install --directory --owner="${SECOND_USERNAME}" --group="${agent_group}" --mode=700 \
        "${AGENT_HOME}/.config" "${AGENT_HOME}/.cache" "${AGENT_HOME}/.local" \
        "${AGENT_HOME}/work" "${AGENT_HOME}/shared" "${AGENT_HOME}/.omp"
    for path in "${AGENT_HOME}/.config" "${AGENT_HOME}/.cache" "${AGENT_HOME}/.local" "${AGENT_HOME}/work"; do
        setfacl --modify "u:${MAIN_USERNAME}:rwx,m::rwx" "${path}"
        setfacl --modify "d:u:${MAIN_USERNAME}:rwx,d:m::rwx,d:o::---" "${path}"
    done

    for index in "${!AGENT_MOUNT_SOURCES[@]}"; do
        source="${AGENT_MOUNT_SOURCES[index]}"
        target="${AGENT_MOUNT_TARGETS[index]}"
        if [[ ! -d $(dirname -- "${target}") ]]; then
            install --directory --owner="${SECOND_USERNAME}" --group="${agent_group}" --mode=700 \
                "$(dirname -- "${target}")"
        fi
        if [[ -d ${source} ]]; then
            [[ ! -e ${target} || -d ${target} ]] || die "target должен быть каталогом: ${target}"
            install --directory --owner="${SECOND_USERNAME}" --group="${agent_group}" --mode=700 "${target}"
        else
            [[ ! -e ${target} || -f ${target} ]] || die "target должен быть обычным файлом: ${target}"
            if [[ ! -e ${target} ]]; then
                install --owner="${SECOND_USERNAME}" --group="${agent_group}" --mode=600 /dev/null "${target}"
            fi
        fi
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
    log 'Установка root-скрипта bind-монтирования'
    local script_path=/usr/local/sbin/agent-wsl-mounts tmp path
    tmp="$(mktemp)"

    # Шапка: значения, известные только инсталлятору, подставляем сразу
    {
        printf '#!/usr/bin/env bash\n\n'
        printf 'set -Eeuo pipefail\n'
        printf 'umask 027\n\n'
        printf 'AGENT_UID=%q\n' "$(id -u "${SECOND_USERNAME}")"
        printf 'AGENT_GID=%q\n' "$(id -g "${SECOND_USERNAME}")"
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
[[ ${#SOURCE_PATHS[@]} -eq ${#TARGET_PATHS[@]} ]] || exit 1

mount_one() {
    local source="$1" target="$2" win_source

    [[ -e "$source" && ! -L "$source" ]] || {
        printf 'Invalid mount source: %s\n' "$source" >&2
        return 1
    }
    [[ -e "$target" && ! -L "$target" ]] || {
        printf 'Invalid mount target: %s\n' "$target" >&2
        return 1
    }

    if [[ -d "$source" ]]; then
        [[ -d "$target" ]] || { printf 'Mount target is not a directory: %s\n' "$target" >&2; return 1; }
    else
        [[ -f "$target" ]] || { printf 'Mount target is not a file: %s\n' "$target" >&2; return 1; }
    fi

    if mountpoint --quiet "$target"; then return 0; fi

    case "$source" in
        /mnt/c/*) win_source="C:${source#/mnt/c}" ;;
        /mnt/d/*) win_source="D:${source#/mnt/d}" ;;
        *) printf 'Unsupported mount source: %s\n' "$source" >&2; return 1 ;;
    esac

    mount -t drvfs "$win_source" "$target" \
        -o metadata,uid="${AGENT_UID}",gid="${AGENT_GID}",umask=000
}

for index in "${!SOURCE_PATHS[@]}"; do
    mount_one "${SOURCE_PATHS[$index]}" "${TARGET_PATHS[$index]}"
done
EOF

    if [[ ${MODE} == check ]]; then
        if [[ -f ${script_path} ]] && cmp -s "${tmp}" "${script_path}"; then
            printf 'INFO: root-скрипт актуален.\n'
        else
            printf 'WARNING: root-скрипт отсутствует или требует обновления: %s\n' "${script_path}"
        fi
    elif [[ ! -f ${script_path} ]] || ! cmp -s "${tmp}" "${script_path}"; then
        install -o root -g root -m 700 "${tmp}" "${script_path}"
    fi
    rm -f "${tmp}"
}


install_systemd_unit() {
    log 'Установка systemd-сервиса bind-монтирования'
    local unit_path=/etc/systemd/system/agent-wsl-mounts.service tmp
    tmp="$(mktemp)"
    cat > "${tmp}" <<'EOF'
[Unit]
Description=Mount shared configuration and Windows directories for agent
After=local-fs.target
RequiresMountsFor=/mnt/c

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/agent-wsl-mounts
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    if [[ -f ${unit_path} ]] && cmp -s "${tmp}" "${unit_path}"; then
        printf 'INFO: systemd unit актуален.\n'
    elif [[ ${MODE} == apply ]]; then
        install -o root -g root -m 644 "${tmp}" "${unit_path}"
    else
        printf 'WARNING: systemd unit отсутствует или требует обновления.\n'
    fi
    rm -f "${tmp}"
    if [[ ${MODE} == apply && -d /run/systemd/system ]]; then
        systemctl daemon-reload
        systemctl enable agent-wsl-mounts.service
    elif [[ ${MODE} == check ]]; then
        systemctl is-enabled agent-wsl-mounts.service >/dev/null 2>&1 ||
            printf 'WARNING: systemd unit не включён.\n'
    else
        printf 'INFO: systemd не запущен; сервис будет активирован после перезапуска WSL.\n'
    fi
}


start_mount_service_if_possible() {
    log 'Проверка bind-монтирований'
    local path
    if [[ ${MODE} != apply ]]; then
        if [[ -d /run/systemd/system ]]; then
            systemctl is-enabled agent-wsl-mounts.service >/dev/null 2>&1 ||
                printf 'WARNING: mount-сервис не включён.\n'
        fi
        for path in "${AGENT_MOUNT_TARGETS[@]}"; do
            mountpoint --quiet "${path}" || printf 'WARNING: точка не смонтирована: %s\n' "${path}"
        done
        return
    fi
    if [[ ! -d /run/systemd/system ]]; then
        printf 'INFO: systemd ещё не запущен; проверка mount-сервиса отложена до перезапуска WSL.\n'
        return
    fi
    systemctl restart agent-wsl-mounts.service
    for path in "${AGENT_MOUNT_TARGETS[@]}"; do
        mountpoint --quiet "${path}" || die "точка не смонтирована: ${path}"
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
    local index path source
    for index in "${!AGENT_MOUNT_TARGETS[@]}"; do
        source="${AGENT_MOUNT_SOURCES[index]}"
        path="${AGENT_MOUNT_TARGETS[index]}"
        [[ -e ${path} && ! -L ${path} ]] || die "некорректная точка монтирования: ${path}"
        if [[ -d ${source} ]]; then
            [[ -d ${path} ]] || die "точка монтирования должна быть каталогом: ${path}"
        else
            [[ -f ${path} ]] || die "точка монтирования должна быть файлом: ${path}"
        fi
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
    if (( SECOND_USER_MISSING )); then
        printf 'WARNING: проверки, требующие пользователя %s, пропущены.\n' "${SECOND_USERNAME}"
        return
    fi
    remove_agent_sudo
    assert_no_privileged_groups
    assert_no_sudo_access
    ensure_share_group
    require_c_mount
    validate_mount_paths
    apply_share_acl
    unmount_existing_targets
    prepare_agent_home
    configure_git
    install_mount_script
    install_systemd_unit
    write_checks
}

main "$@"
