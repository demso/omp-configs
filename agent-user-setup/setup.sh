#!/usr/bin/env bash

# setup.sh устанавливает пользовательские инструменты в HOME текущего пользователя.
set -euo pipefail

CONFIG_FILE="/etc/agent-setup.conf"
if [ ! -r "${CONFIG_FILE}" ]; then
  printf 'ERROR: конфигурация не найдена: %s\n' "${CONFIG_FILE}" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "${CONFIG_FILE}"

: "${SECOND_USERNAME:?SECOND_USERNAME не задан}"
: "${APT_MIRROR:?APT_MIRROR не задан}"
: "${PYPI_MIRROR:?PYPI_MIRROR не задан}"
: "${NPM_REGISTRY:?NPM_REGISTRY не задан}"
: "${TZ_VALUE:?TZ_VALUE не задан}"

if [ "$(id -u)" -eq 0 ]; then
  echo "ERROR: setup.sh нужно запускать от ${SECOND_USERNAME}, не от root." >&2
  exit 1
fi

if [ "$(id -un)" != "${SECOND_USERNAME}" ]; then
  echo "ERROR: setup.sh нужно запускать от ${SECOND_USERNAME}; текущий пользователь: $(id -un)." >&2
  exit 1
fi

# ===== Настройки =====
APT_MIRROR="${APT_MIRROR%/}"   # защита от двойного слеша

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
mkdir -p ~/.config/pip ~/.config/uv
cat > ~/.config/pip/pip.conf <<EOF
[global]
index-url = ${PYPI_MIRROR}
EOF
cat > ~/.config/uv/uv.toml <<EOF
[[index]]
url = "${PYPI_MIRROR}"
default = true
EOF

git lfs install

# ---------- 6. ~/.bashrc: PATH, TZ, prompt (идемпотентно) ----------

# ---------- 8. ~/.bashrc: PATH, TZ, prompt (идемпотентно) ----------
BASHRC="$HOME/.bashrc"
if ! grep -q "DEV ENV BLOCK" "$BASHRC" 2>/dev/null; then
  {
    echo ''
    echo '# ===== DEV ENV BLOCK ====='
    echo "export TZ=\"${TZ_VALUE}\""
    echo 'export DOTNET_ROOT="$HOME/.dotnet"'
    echo 'export PATH="$HOME/.bun/bin:$HOME/.local/bin:$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"'
    echo 'PS1="\[\033[01;32m\][agent]\[\033[00m\] \[\033[01;34m\]\[\u@\h\]\[\033[00m\]\$ "'
    printf '%s\n' 'export WINDOWS_HOST=$(ip route | grep default | awk '\''{print $3}'\'')'
    #echo export http_proxy=http://$WINDOWS_HOST:55366 
    #echo export https_proxy=http://$WINDOWS_HOST:55366
    #echo export no_proxy=localhost,127.0.0.1,*.local,10.*,172.*,192.168.*,*.keysystems.ru
    echo '# ===== END DEV ENV BLOCK ====='
  } >> "$BASHRC"
fi

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