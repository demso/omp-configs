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

AGENT_HOME="/home/$AGENT_USER"

render() {
  sed -e "s|@AGENT_HOME@|$AGENT_HOME|g" -e "s|@AGENT_DATA_ROOT@|$AGENT_DATA_ROOT|g" "$1"
}

# Приватные конфиги: рендерятся из шаблонов прямо в HOME агента.
TEMPLATED=(
  "omp/agent/config.yml.tmpl .omp/agent/config.yml"
  "omp/agent/mcp.json.tmpl .omp/agent/mcp.json"
)

# Общие артефакты: копируются как есть. Остальное состояние .omp не затрагивается,
# поэтому credentials, базы, сессии и логи остаются локальными для агента.
SHARED=(
  "agents/AGENTS.md .agents/AGENTS.md"
  "agents/skills .agents/skills"
  "omp/agent/models.yml .omp/agent/models.yml"
  "omp/agent/RULES.md .omp/agent/RULES.md"
  "omp/agent/managed-skills .omp/agent/managed-skills"
)

# Копирует дерево без шаблонов и без скрытых файлов (.git, .gitignore).
copy_tree() {
  local src="$1" dst="$2" item name
  mkdir -p "$dst"
  for item in "$src"/*; do
    [ -e "$item" ] || continue
    name="$(basename -- "$item")"
    case "$name" in
      *.tmpl) continue ;;
    esac
    if [ -d "$item" ]; then
      copy_tree "$item" "$dst/$name"
    else
      cp -a -- "$item" "$dst/$name"
    fi
  done
}

push() {
  mkdir -p "$MASTER/.omp/agent" "$MASTER/.agents"

  local pair src dst tmp
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN
  for pair in "${TEMPLATED[@]}"; do
    read -r src dst <<<"$pair"
    render "$src" >"$tmp"
    install -m 644 "$tmp" "$MASTER/$dst"
    echo "push  $dst (шаблон)"
  done

  for pair in "${SHARED[@]}"; do
    read -r src dst <<<"$pair"
    mkdir -p "$(dirname -- "$MASTER/$dst")"
    if [ -d "$src" ]; then
      copy_tree "$src" "$MASTER/$dst"
    else
      install -m 644 "$src" "$MASTER/$dst"
    fi
    echo "push  $dst"
  done
}

diff_run() {
  local pair src dst rc=0
  for pair in "${SHARED[@]}"; do
    read -r src dst <<<"$pair"
    if [ ! -e "$MASTER/$dst" ]; then echo "MISSING $dst"; rc=1; continue; fi
    if [ -d "$src" ]; then
      if ! diff -r -q --strip-trailing-cr --exclude=.* --exclude='*.tmpl' \
        "$src" "$MASTER/$dst" 2>/dev/null; then
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
