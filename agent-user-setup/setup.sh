#!/usr/bin/env bash

# setup.sh устанавливает пользовательские инструменты в HOME текущего пользователя.
set -euo pipefail
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
if [ ! -r "${CONFIG_FILE}" ]; then
  printf 'ERROR: конфигурация не найдена: %s\n' "${CONFIG_FILE}" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "${CONFIG_FILE}"

: "${SECOND_USERNAME:?SECOND_USERNAME не задан}"
: "${PYPI_MIRROR:?PYPI_MIRROR не задан}"
: "${NPM_REGISTRY:?NPM_REGISTRY не задан}"
: "${TZ_VALUE:?TZ_VALUE не задан}"
PS1_LINE='PS1="\[\033[01;32m\][agent]\[\033[00m\] \[\033[01;34m\][\u@\h]\[\033[00m\]\$ "'

if [ "$(id -u)" -eq 0 ]; then
  echo "ERROR: setup.sh нужно запускать от ${SECOND_USERNAME}, не от root." >&2
  exit 1
fi

if [ "$(id -un)" != "${SECOND_USERNAME}" ]; then
  echo "ERROR: setup.sh нужно запускать от ${SECOND_USERNAME}; текущий пользователь: $(id -un)." >&2
  exit 1
fi

# ===== Настройки =====

# APT и системные пакеты устанавливаются отдельным root-скриптом.
# setup.sh работает только в HOME пользователя ${SECOND_USERNAME}.
# ---------- 1. Проверка системных инструментов ----------
# Системные пакеты устанавливаются root-скриптом first.sh.
if command -v exa >/dev/null 2>&1; then
  LS_PKG=exa
elif command -v eza >/dev/null 2>&1; then
  LS_PKG=eza
else
  LS_PKG=eza
  echo "WARNING: exa/eza не найден; установите системные пакеты через first.sh"
fi

echo "→ ls-инструмент: ${LS_PKG}"

# In check mode, report the expected user tools and config contents without
# invoking installers or changing any files.
if [[ ${MODE} == check ]]; then
  export PATH="$HOME/.bun/bin:$HOME/.local/bin:$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"
  for c in python fd bat fzf rg "${LS_PKG}" jq git go psql node npm pnpm bun uv dotnet dotnet-ef csharp-ls; do
    p="$(command -v "$c" 2>/dev/null || true)"
    printf '  %-24s %s\n' "$c" "${p:-НЕ НАЙДЕН}"
  done

  PIP_CONF="$HOME/.config/pip/pip.conf"
  if [[ ! -f "$PIP_CONF" ]] ||
     ! grep -Fqx -- '[global]' "$PIP_CONF" 2>/dev/null ||
     ! grep -Fqx -- "index-url = ${PYPI_MIRROR}" "$PIP_CONF" 2>/dev/null; then
    printf 'WARNING: отсутствует или отличается %s\n' "$PIP_CONF" >&2
  fi

  UV_CONF="$HOME/.config/uv/uv.toml"
  if [[ ! -f "$UV_CONF" ]] ||
     ! grep -Fqx -- '[[index]]' "$UV_CONF" 2>/dev/null ||
     ! grep -Fqx -- "url = \"${PYPI_MIRROR}\"" "$UV_CONF" 2>/dev/null ||
     ! grep -Fqx -- 'default = true' "$UV_CONF" 2>/dev/null; then
    printf 'WARNING: отсутствует или отличается %s\n' "$UV_CONF" >&2
  fi

  BASHRC="$HOME/.bashrc"
  if [[ ! -f "$BASHRC" ]] ||
     ! grep -Fqx -- '# ===== DEV ENV BLOCK =====' "$BASHRC" 2>/dev/null ||
     ! grep -Fqx -- "export TZ=\"${TZ_VALUE}\"" "$BASHRC" 2>/dev/null ||
     ! grep -Fqx -- 'export DOTNET_ROOT="$HOME/.dotnet"' "$BASHRC" 2>/dev/null ||
     ! grep -Fqx -- 'export PATH="$HOME/.bun/bin:$HOME/.local/bin:$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"' "$BASHRC" 2>/dev/null ||
     ! grep -Fqx -- "${PS1_LINE}" "$BASHRC" 2>/dev/null ||
     ! grep -Fqx -- 'export WINDOWS_HOST=$(ip route | grep default | awk '\''{print $3}'\'')' "$BASHRC" 2>/dev/null ||
     ! grep -Fqx -- '# ===== END DEV ENV BLOCK =====' "$BASHRC" 2>/dev/null; then
    printf 'WARNING: отсутствует или отличается DEV ENV BLOCK в %s\n' "$BASHRC" >&2
  fi
  exit 0
fi

# The remaining operations are apply-only.  Temporary files are created in
# HOME so every write remains user-scoped, and unchanged files keep their
# existing contents and timestamps.
write_if_changed() {
  local target="$1" tmp
  tmp="$(mktemp "${target}.tmp.XXXXXX")"
  cat > "$tmp"
  if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
    rm -f "$tmp"
    return 0
  fi
  if [[ -e "$target" ]]; then
    chmod --reference="$target" "$tmp"
  else
    chmod 0644 "$tmp"
  fi
  mv -f "$tmp" "$target"
}

write_bashrc_if_changed() {
  local target="$HOME/.bashrc" block candidate
  block="$(mktemp "$HOME/.dev-env-block.XXXXXX")"
  candidate="$(mktemp "$HOME/.bashrc.tmp.XXXXXX")"

  cat > "$block" <<EOF
# ===== DEV ENV BLOCK =====
export TZ="${TZ_VALUE}"
export DOTNET_ROOT="\$HOME/.dotnet"
export PATH="\$HOME/.bun/bin:\$HOME/.local/bin:\$HOME/.dotnet:\$HOME/.dotnet/tools:\$PATH"
${PS1_LINE}
export WINDOWS_HOST=\$(ip route | grep default | awk '{print \$3}')
#echo export http_proxy=http://\$WINDOWS_HOST:55366
#echo export https_proxy=http://\$WINDOWS_HOST:55366
#echo export no_proxy=localhost,127.0.0.1,*.local,10.*,172.*,192.168.*,*.keysystems.ru
# ===== END DEV ENV BLOCK =====
EOF

  if [[ -f "$target" ]]; then
    awk '
      $0 == "# ===== DEV ENV BLOCK =====" { in_block = 1; next }
      in_block && $0 == "# ===== END DEV ENV BLOCK =====" { in_block = 0; next }
      !in_block { print }
    ' "$target" > "$candidate"
  fi
  if [[ -s "$candidate" ]] && [[ "$(tail -c 1 "$candidate")" != $'\n' ]]; then
    printf '\n' >> "$candidate"
  fi
  cat "$block" >> "$candidate"

  if [[ -f "$target" ]] && cmp -s "$candidate" "$target"; then
    rm -f "$block" "$candidate"
    return 0
  fi
  if [[ -e "$target" ]]; then
    chmod --reference="$target" "$candidate"
  else
    chmod 0644 "$candidate"
  fi
  rm -f "$block"
  mv -f "$candidate" "$target"
}
# ---------- 2. Bun и UV (в $HOME, без sudo) ----------
# установщики сами допишут PATH в ~/.bashrc.
curl -fsSL https://bun.sh/install | bash
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"

# ---------- 3. .NET 10 (в ~/.dotnet, без sudo) ----------
curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 10.0 --install-dir "$HOME/.dotnet"
export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"
export DOTNET_ROOT="$HOME/.dotnet"

# update || install: при повторном запуске install падает с already installed.
dotnet tool update --global dotnet-ef 2>/dev/null || dotnet tool install --global dotnet-ef
dotnet tool update --global csharp-ls 2>/dev/null || dotnet tool install --global csharp-ls
dotnet nuget locals all --clear

# ---------- 4. NPM в домашнем каталоге пользователя ----------
npm config set prefix "$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
npm install --global --registry="${NPM_REGISTRY}" \
  yaml-language-server pnpm vscode-langservers-extracted

# ---------- 5. Зеркала pip/uv (конфиги пользователя вместо ENV) ----------
mkdir -p "$HOME/.config/pip" "$HOME/.config/uv"
write_if_changed "$HOME/.config/pip/pip.conf" <<EOF
[global]
index-url = ${PYPI_MIRROR}
EOF
write_if_changed "$HOME/.config/uv/uv.toml" <<EOF
[[index]]
url = "${PYPI_MIRROR}"
default = true
EOF

git lfs install

# ---------- 8. ~/.bashrc: PATH, TZ, prompt (идемпотентно) ----------
write_bashrc_if_changed

bun install -g @oh-my-pi/pi-coding-agent

# ---------- 9. Проверка ----------
echo
echo "===== Проверка (по завершении открой новое окно терминала или: source ~/.bashrc) ====="
for c in python fd bat fzf rg "${LS_PKG}" jq git go psql node npm pnpm bun uv dotnet dotnet-ef csharp-ls; do
  p="$(command -v "$c" 2>/dev/null || true)"
  printf '  %-10s %s\n' "$c" "${p:-НЕ НАЙДЕН}"
done
echo
echo "command -v python fd bat eza fzf rg jq git go psql node npm pnpm bun uv dotnet dotnet-ef csharp-ls"
echo
echo "ℹ Python на 26.04 externally-managed (PEP 668): pip — только в venv,"
echo "  утилиты ставь через 'uv tool install'."