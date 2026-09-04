#!/usr/bin/env bash

#`wsl -u <user>` или `su <user>`
set -euo pipefail

# ---------- 0. Защита от запуска под root ----------
if [ "$(id -u)" -eq 0 ]; then
  echo
  echo "⚠️  Скрипт запущен от root!"
  echo
  echo "Системная часть (apt, зеркала, npm -g) отработает нормально,"
  echo "но пользовательские компоненты (bun, uv, .NET, конфиги pip/uv/npm,"
  echo "блок ~/.bashrc) установятся в /root — и пользователь их не увидит."
  if [ -n "${SUDO_USER:-}" ]; then
    echo
    echo "Похоже, был вызов 'sudo bash wsl-setup.sh' от пользователя ${SUDO_USER}."
    echo "Правильный запуск:  exit          # выйти из root-сессии"
    echo "                    ./wsl-setup.sh"
  fi
  echo
  if [ ! -t 0 ]; then
    echo "stdin — не терминал, подтвердить невозможно. Отмена."
    exit 1
  fi
  read -rp "Всё равно продолжить? [y/N]: " answer || { echo "Отменено."; exit 1; }
  case "$answer" in
    [yY]|[yY][eE][sS]) echo "Продолжаю — ты предупреждён." ;;
    *)                 echo "Отменено. Запусти без sudo: ./wsl-setup.sh"; exit 1 ;;
  esac
fi

# ===== Настройки =====
APT_MIRROR="http://mirror.yandex.ru/ubuntu"
PYPI_MIRROR="https://mirror.yandex.ru/pypi/web/simple/"
NPM_REGISTRY="https://registry.npmmirror.com"
APT_MIRROR="${APT_MIRROR%/}"   # защита от двойного слеша

# ---------- 1. Зеркала APT (deb822 и старый формат, с бэкапом .orig) ----------
shopt -s nullglob
apt_files=(
  /etc/apt/sources.list
  /etc/apt/sources.list.d/*.sources
  /etc/apt/sources.list.d/*.list
)

for f in "${apt_files[@]}"; do
  # правим только файлы, где реально встречаются зеркала Ubuntu
  # (2>/dev/null: на 26.04 sources.list не существует, grep шумел бы в stderr)
  sudo grep -qE '(ubuntu\.com|kernel\.org)/ubuntu' "$f" 2>/dev/null || continue

  # разовый бэкап оригинала (не затирается при повторных запусках;
  # apt игнорирует файлы без суффикса .list/.sources)
  sudo test -e "$f.orig" || sudo cp "$f" "$f.orig"

  sudo sed -i -E \
    -e "s|https?://[^[:space:]/]*\.ubuntu\.com/ubuntu-ports/?|${APT_MIRROR}-ports/|g" \
    -e "s|https?://[^[:space:]/]*\.kernel\.org/ubuntu-ports/?|${APT_MIRROR}-ports/|g" \
    -e "s|https?://[^[:space:]/]*\.ubuntu\.com/ubuntu/?|${APT_MIRROR}/|g" \
    -e "s|https?://[^[:space:]/]*\.kernel\.org/ubuntu/?|${APT_MIRROR}/|g" \
    "$f"
done
shopt -u nullglob

# universe нужен для fd-find/bat/fzf/ripgrep/eza — в дефолтном WSL включён
if sudo test -f /etc/apt/sources.list.d/ubuntu.sources && \
   ! sudo grep -qiE '^Components:.*universe' /etc/apt/sources.list.d/ubuntu.sources; then
  echo "⚠ 'universe' не найден в Components — добавь, иначе eza/fzf/ripgrep не встанут"
fi

printf 'Acquire::Retries "5";\nAcquire::http::Timeout "60";\nAcquire::https::Timeout "60";\n' \
  | sudo tee /etc/apt/apt.conf.d/99retry >/dev/null

sudo apt-get update

# ---------- 2. Системные пакеты ----------
# apt-cache show врёт: пакет может быть "известен" (referred to by another
# package), но неустанавливаем. Достоверный тест — симуляция установки:
if apt-get install --dry-run exa >/dev/null 2>&1; then
  LS_PKG=exa
else
  LS_PKG=eza
fi
echo "→ ls-инструмент: ${LS_PKG}"

# sudo env DEBIAN_FRONTEND=... : новый sudo в 26.04 отклоняет запись
# "sudo VAR=value cmd" для переменных не из sudoers и не запускает команду
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  build-essential ca-certificates curl wget unzip \
  git git-lfs \
  python3 python3-dev python3-venv python3-pip python-is-python3 \
  nodejs npm \
  fd-find bat fzf ripgrep jq "${LS_PKG}" \
  golang-go \
  postgresql-client \
  libssl-dev zlib1g-dev libffi-dev \
  vim tree tzdata

# libicu: автодетект версии (26.04 -> libicu76+), с dry-run-проверкой
ICU_PKG="$(apt-cache search --names-only '^libicu[0-9]+$' | awk '{print $1}' | sort -V | tail -n1)"
if [ -n "$ICU_PKG" ] && apt-get install --dry-run "$ICU_PKG" >/dev/null 2>&1; then
  sudo apt-get install -y "$ICU_PKG"
fi

# На 26.04 apt даёт Node 22/24 LTS — достаточно. Проверим на всякий случай:
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
[ "${NODE_MAJOR}" -lt 20 ] && \
  echo "⚠ Node ${NODE_MAJOR} староват для LSP — раскомментируй NodeSource и перезапусти скрипт"
# curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
# sudo apt-get install -y nodejs

sudo apt-get clean   # vhdx WSL не сжимается сам — не храним кэш apt в образе

# ---------- 3. Симлинки и время (только если бинари на месте) ----------
command -v fdfind >/dev/null 2>&1 && sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
command -v batcat >/dev/null 2>&1 && sudo ln -sf "$(command -v batcat)" /usr/local/bin/bat

sudo ln -snf "/usr/share/zoneinfo/${TZ_VALUE}" /etc/localtime
echo "${TZ_VALUE}" | sudo tee /etc/timezone >/dev/null

# ---------- 4. Bun и UV (в $HOME, без sudo) ----------
# установщики сами допишут PATH в ~/.bashrc — дубли с нашим блоком безвредны
curl -fsSL https://bun.sh/install | bash
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"

# ---------- 5. .NET 10 (в ~/.dotnet, без sudo) ----------
curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 10.0 --install-dir "$HOME/.dotnet"
export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"
export DOTNET_ROOT="$HOME/.dotnet"

# update || install: при повторном запуске "install" падает с "already installed"
dotnet tool update  --global dotnet-ef 2>/dev/null || dotnet tool install --global dotnet-ef
dotnet tool update  --global csharp-ls 2>/dev/null || dotnet tool install --global csharp-ls
dotnet nuget locals all --clear

# ---------- 6. NPM ----------
# registry ФЛАГОМ: `sudo npm config set` писал бы в /root/.npmrc
# -H: HOME=/root под sudo, иначе npm насоздаёт root-owned файлов в ~/.npm (EACCES)
sudo -H npm install -g --registry="${NPM_REGISTRY}" \
  yaml-language-server pnpm vscode-langservers-extracted

npm config set registry "${NPM_REGISTRY}"   # пользовательский ~/.npmrc

# ---------- 7. Зеркала pip/uv (конфиги пользователя вместо ENV) ----------
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
    echo 'export WINDOWS_HOST=$(ip route | grep default | awk \'{print $3}\')'
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