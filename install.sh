#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

die() { echo "ОШИБКА: $*" >&2; exit 1; }

[ -f device.env ] || die "нет device.env — скопируй: cp device.env.example device.env"
# shellcheck disable=SC1091
source device.env
: "${AGENT_USER:?задай AGENT_USER в device.env}"
: "${AGENT_DATA_ROOT:?задай AGENT_DATA_ROOT в device.env}"

MASTER="${AGENT_CONFIG_MASTER:-$HOME}"
[[ ${MASTER} == "/home/${AGENT_USER}" ]] ||
  die "AGENT_CONFIG_MASTER должен указывать на локальный HOME агента: /home/${AGENT_USER}"
findmnt -nT "$MASTER/.agents" -o TARGET 2>/dev/null | grep -Fqx -- "$MASTER/.agents" ||
  die "$MASTER/.agents должен быть отдельным bind mount"

AGENT_HOME="/home/$AGENT_USER"


# Все файлы OMP и общие данные используются напрямую через bind mounts,
# созданные agent-user-setup/first.sh.
DIRS=(
  "agents/AGENTS.md .agents/AGENTS.md"
  "agents/skills .agents/skills"
)

push() {
  mkdir -p "$MASTER/.agents"

  local pair src dst
  for pair in "${DIRS[@]}"; do
    read -r src dst <<<"$pair"
    if [ -d "$src" ]; then
      mkdir -p "$MASTER/$dst"
      cp -a "$src/." "$MASTER/$dst/"
    else
      install -m 644 "$src" "$MASTER/$dst"
    fi
    echo "push  $dst"
  done
}

diff_run() {
  local pair src dst rc=0
  for pair in "${DIRS[@]}"; do
    read -r src dst <<<"$pair"
    if [ ! -e "$MASTER/$dst" ]; then echo "MISSING $dst"; rc=1; continue; fi
    if [ -d "$src" ]; then
      if ! diff -r -q --strip-trailing-cr --exclude=.git "$src" "$MASTER/$dst" 2>/dev/null; then
        echo "DIFF     $dst/"
        rc=1
      fi
    elif ! diff -q --strip-trailing-cr "$src" "$MASTER/$dst" >/dev/null 2>&1; then
      echo "DIFF     $dst"
      rc=1
    fi
  done
  [ "$rc" -eq 0 ] && echo "OK: мастер-папка соответствует репо"
  return "$rc"
}

case "${1:-}" in
  push) push ;;
  diff) diff_run ;;
  *)
    echo "использование: $0 {push|diff}" >&2
    exit 1
    ;;
esac
