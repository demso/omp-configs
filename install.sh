#!/usr/bin/env bash
set -euo pipefail

# agent-config: синхронизация конфигов агентов между git-репо (мастер между
# устройствами) и живыми ~/.omp / ~/.agents, которые на настроенном устройстве
# являются bind-mount'ами Windows-папки основного пользователя
# (C:\Users\<MAIN>\{.omp,.agents}). Запись через точки монтирования = запись
# в Windows-мастер; прямой доступ к /mnt/c не нужен (обычно закрыт для агента).
#
#   ./install.sh push   — отрендерить шаблоны и скопировать конфиги в мастер
#   ./install.sh diff   — показать расхождения мастера с репо
#
# По-устройственные значения — в device.env (шаблон: device.env.example).

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

die() { echo "ОШИБКА: $*" >&2; exit 1; }

[ -f device.env ] || die "нет device.env — скопируй: cp device.env.example device.env"
# shellcheck disable=SC1091
source device.env
: "${AGENT_USER:?задай AGENT_USER в device.env}"
: "${AGENT_DATA_ROOT:?задай AGENT_DATA_ROOT в device.env}"

MASTER="${AGENT_CONFIG_MASTER:-$HOME}"
for m in .omp .agents; do
  fs="$(findmnt -nT "$MASTER/$m" -o FSTYPE 2>/dev/null || true)"
  case "$fs" in
    9p|drvfs) ;;
    *) echo "ПРЕДУПРЕЖДЕНИЕ: $MASTER/$m не bind-mount с Windows (${fs:-нет монтирования}) — push запишет в локальный каталог" >&2 ;;
  esac
done

AGENT_HOME="/home/$AGENT_USER"

render() { # render <file.tmpl> — рендер в stdout
  sed -e "s|@AGENT_HOME@|$AGENT_HOME|g" -e "s|@AGENT_DATA_ROOT@|$AGENT_DATA_ROOT|g" "$1"
}

# пары: "путь-в-репо путь-внутри-мастер-папки"
TEMPLATED=(
  "omp/agent/config.yml.tmpl .omp/agent/config.yml"
  "omp/agent/mcp.json.tmpl   .omp/agent/mcp.json"
)
PLAIN=(
  "omp/agent/models.yml .omp/agent/models.yml"
  "omp/agent/RULES.md   .omp/agent/RULES.md"
)
DIRS=(
  "omp/agent/managed-skills .omp/agent/managed-skills"
  "agents/AGENTS.md         .agents/AGENTS.md"
  "agents/skills            .agents/skills"
)
# git-клон: переносится целиком вместе с .git
CLONE_SRC="omp/extensions/superpowers"
CLONE_DST=".omp/extensions/superpowers"

push() {
  mkdir -p "$MASTER/.omp/agent" "$MASTER/.omp/extensions" "$MASTER/.agents"

  local pair src dst tmp
  for pair in "${TEMPLATED[@]}"; do
    read -r src dst <<<"$pair"
    tmp="$(mktemp)"
    render "$src" >"$tmp"
    install -m 644 "$tmp" "$MASTER/$dst"
    rm -f "$tmp"
    echo "push  $dst (шаблон)"
  done
  for pair in "${PLAIN[@]}"; do
    read -r src dst <<<"$pair"
    install -m 644 "$src" "$MASTER/$dst"
    echo "push  $dst"
  done
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

  # superpowers: самостоятельный git-клон в мастере. Локальный clone из
  # submodule (без сети) даёт собственный .git — cp -a не годится: у submodule
  # .git — файл-указатель в суперрепо. Если omp запущен и держит файлы,
  # rm на 9p упадёт: перезапусти при закрытом omp.
  rm -rf "$MASTER/$CLONE_DST"
  git clone -q "$CLONE_SRC" "$MASTER/$CLONE_DST"
  echo "push  $CLONE_DST/"

  # .env с реальным ключом в репо НЕ хранится
  if [ ! -f "$MASTER/.omp/agent/.env" ]; then
    install -m 600 .env.example "$MASTER/.omp/agent/.env"
    echo "создан .omp/agent/.env — впиши ZAI_API_KEY и перезапусти omp"
  fi
}

# Сравнение игнорирует CRLF/LF: репо хранит LF, Windows-мастер может держать CRLF.
diff_run() {
  local pair src dst tmp rc=0
  for pair in "${TEMPLATED[@]}"; do
    read -r src dst <<<"$pair"
    if [ ! -f "$MASTER/$dst" ]; then echo "MISSING  $dst"; rc=1; continue; fi
    tmp="$(mktemp)"
    render "$src" >"$tmp"
    if ! diff -q --strip-trailing-cr "$tmp" "$MASTER/$dst" >/dev/null; then
      echo "DIFF     $dst"
      diff -u "$MASTER/$dst" "$tmp" || true
      rc=1
    fi
    rm -f "$tmp"
  done
  for pair in "${PLAIN[@]}"; do
    read -r src dst <<<"$pair"
    if ! diff -q --strip-trailing-cr "$src" "$MASTER/$dst" >/dev/null 2>&1; then
      echo "DIFF     $dst"
      diff -u "$MASTER/$dst" "$src" 2>/dev/null || true
      rc=1
    fi
  done
  for pair in "${DIRS[@]}"; do
    read -r src dst <<<"$pair"
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
  # superpowers — git-клон: сравниваем HEAD с пином submodule, а не файлы
  # (в Windows-чекине симлинки превращаются в текстовые файлы-указатели)
  pin="$(git -C "$CLONE_SRC" rev-parse HEAD 2>/dev/null || true)"
  live_head="$(git -C "$MASTER/$CLONE_DST" rev-parse HEAD 2>/dev/null || true)"
  live_dirty="$(git -C "$MASTER/$CLONE_DST" status --porcelain 2>/dev/null | head -1)"
  if [ "$pin" != "$live_head" ] || [ -n "$live_dirty" ]; then
    echo "DIFF     $CLONE_DST/ (репо=${pin:-?}, мастер=${live_head:-?}${live_dirty:+, есть локальные правки})"
    rc=1
  fi
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
