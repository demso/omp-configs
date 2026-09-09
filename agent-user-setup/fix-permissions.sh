#!/usr/bin/env bash

set -Eeuo pipefail
umask 022

SCRIPT_NAME="$(basename "$0")"
APPLY=0
ROOT_PATH=""

usage() {
    cat <<EOF
Исправляет права каталогов и обычных файлов рекурсивно.

По умолчанию работает в режиме dry-run.

Использование:
  ${SCRIPT_NAME} PATH
  ${SCRIPT_NAME} --dry-run PATH
  sudo ${SCRIPT_NAME} --apply PATH

Результат:
  каталоги:      добавляются rwx для всех пользователей;
  обычные файлы: добавляются rw для всех пользователей;
  executable-биты файлов сохраняются;
  владельцы, группы и symlink-и не изменяются;
  другие файловые системы не обходятся.
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

log() {
    printf '%s\n' "$*"
}

parse_args() {
    local arg

    while (($# > 0)); do
        arg="$1"
        shift

        case "$arg" in
            --apply)
                APPLY=1
                ;;
            --dry-run)
                APPLY=0
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -* )
                die "неизвестный параметр: ${arg}"
                ;;
            *)
                [[ -z "$ROOT_PATH" ]] || die "указано несколько путей"
                ROOT_PATH="$arg"
                ;;
        esac
    done

    [[ -n "$ROOT_PATH" ]] || {
        usage >&2
        exit 2
    }
}

validate_path() {
    [[ "$ROOT_PATH" = /* ]] ||
        die "путь должен быть абсолютным: ${ROOT_PATH}"
    [[ -d "$ROOT_PATH" ]] ||
        die "каталог не существует: ${ROOT_PATH}"
    [[ ! -L "$ROOT_PATH" ]] ||
        die "корневой путь не должен быть symlink: ${ROOT_PATH}"

    # Refuse the filesystem root and virtual/system trees. Use an explicit
    # narrower path instead. This prevents an accidental chmod over the OS.
    case "$ROOT_PATH" in
        /|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/run|/run/*|/boot|/boot/*)
            die "опасный системный путь: ${ROOT_PATH}"
            ;;
    esac

    if ((APPLY == 1)) && [[ "$EUID" -ne 0 ]]; then
        log "INFO: запуск не от root; будут исправлены только доступные вам объекты"
    fi
}

chmod_directory() {
    local path="$1"

    if ((APPLY == 0)); then
        printf 'DIR  chmod a+rwx -- %q\n' "$path"
        return 0
    fi

    chmod a+rwx -- "$path"
}

chmod_file() {
    local path="$1"

    if ((APPLY == 0)); then
        printf 'FILE chmod a+rw  -- %q\n' "$path"
        return 0
    fi

    # Symbolic mode preserves existing executable bits.
    chmod a+rw -- "$path"
}

main() {
    parse_args "$@"
    validate_path

    local directories=0
    local files=0
    local skipped=0
    local errors=0
    local path

    if ((APPLY == 0)); then
        log "DRY-RUN: права не изменяются"
    else
        log "APPLY: изменяются права внутри ${ROOT_PATH}"
    fi

    # -P prevents find from following symlinks. NUL-delimited output handles
    # spaces and newlines in path names safely.
    while IFS= read -r -d '' path; do
        if [[ -L "$path" ]]; then
            ((skipped++)) || true
            continue
        fi

        if [[ -d "$path" ]]; then
            ((directories++)) || true
            if ! chmod_directory "$path"; then
                printf 'ERROR: не удалось изменить каталог: %s\n' "$path" >&2
                ((errors++)) || true
            fi
        elif [[ -f "$path" ]]; then
            ((files++)) || true
            if ! chmod_file "$path"; then
                printf 'ERROR: не удалось изменить файл: %s\n' "$path" >&2
                ((errors++)) || true
            fi
        else
            ((skipped++)) || true
        fi
    done < <(
        find -P "$ROOT_PATH" -xdev -print0
    )

    printf '\nКаталоги: %d\nФайлы: %d\nПропущено: %d\nОшибки: %d\n' \
        "$directories" "$files" "$skipped" "$errors"

    ((errors == 0)) || exit 1
}

main "$@"
