# Docs MCP Server (grounded.tools) в Oh My Pi

## Назначение

Инструкция для агента, который должен установить и подключить `docs-mcp-server` (Grounded Docs, https://grounded.tools) в Oh My Pi (OMP).

Целевой результат:

- пакет `@arabold/docs-mcp-server` установлен глобально в пользовательский npm-префикс `~/.local`;
- сервер запущен постоянно (HTTP-режим) и подключён к OMP через `~/.omp/agent/mcp.json`;
- MCP-инструменты доступны в сессии под роутами `xd://mcp__docs_mcp_server_*`;
- скилы `docs-search`, `docs-manage`, `fetch-url` стоят в `~/.agents/skills/`;
- web-интерфейс доступен из Windows по IP WSL.

Исходники: https://github.com/arabold/docs-mcp-server

## Предварительные условия

Node.js 22+:

```bash
node --version
```

Ожидаемый результат: `v22.x` или выше.

Проверить, что `~/.local/bin` в PATH (туда попадёт бинарник):

```bash
echo $PATH | tr ':' '\n' | grep '.local/bin'
```

Проверить текущие MCP-серверы OMP:

```bash
cat ~/.omp/agent/mcp.json
```

Не устанавливать пакет системным `npm install -g` без префикса: системный префикс (`/usr/local/lib`) недоступен для записи без root (EACCES). Использовать пользовательский префикс `--prefix=$HOME/.local` — одноразово, без изменения глобального `npm config`.

## Установка

Установить пакет:

```bash
npm install -g --prefix=$HOME/.local @arabold/docs-mcp-server
```

Установка долгая (нативные модули, Playwright Chromium скачивается при первом запуске) — до 10 минут. Не прерывать: прерванная установка оставляет пакет в полуразобранном состоянии (`better-sqlite3` без `package.json`), лечится только полной переустановкой:

```bash
rm -rf ~/.local/lib/node_modules/@arabold
npm install -g --prefix=$HOME/.local @arabold/docs-mcp-server
```

Проверить нативный модуль:

```bash
node -e "require('$HOME/.local/lib/node_modules/@arabold/docs-mcp-server/node_modules/better-sqlite3'); console.log('sqlite ok')"
```

Ожидаемый результат: `sqlite ok`.

## Запуск сервера (HTTP-режим, рекомендуется)

Один постоянный процесс обслуживает всех клиентов и даёт Web UI:

```bash
docs-mcp-server
# по умолчанию: http://127.0.0.1:6280, MCP: http://127.0.0.1:6280/mcp
```

При первом запуске сервер скачает Playwright Chromium и применит миграции SQLite (~1–2 минуты). Готовность — строка `Grounded Docs available at http://127.0.0.1:6280`.

Вариант без демона — stdio (сервер стартует на каждую OMP-сессию): в записи `mcp.json` ниже заменить HTTP-запись на stdio (см. раздел «Диагностика → stdio-вариант»). Минус: нет Web UI, холодный старт на сессию.

## Подключение к OMP

В `~/.omp/agent/mcp.json` добавить в `mcpServers`:

```json
"docs-mcp-server": {
  "type": "http",
  "url": "http://127.0.0.1:6280/mcp"
}
```

После правки конфига в уже открытой сессии выполнить `/mcp reload` (или `/mcp reconnect docs-mcp-server`) — полный перезапуск OMP не обязателен. Новые сессии подхватывают сервер автоматически.

## Скилы агента

Из репозитория `arabold/docs-mcp-server` (каталог `skills/`) скопировать три скила в глобальный каталог скилов OMP:

```bash
for s in docs-manage docs-search fetch-url; do
  mkdir -p ~/.agents/skills/$s
  curl -sfL "https://raw.githubusercontent.com/arabold/docs-mcp-server/main/skills/$s/SKILL.md" \
    -o ~/.agents/skills/$s/SKILL.md
done
```

| Скил | Назначение |
|---|---|
| `docs-search` | поиск по индексу: список библиотек, поиск контента, резолв версий |
| `docs-manage` | управление индексом: scrape/refresh/remove, компактирование SQLite |
| `fetch-url` | одна страница → Markdown без индексации |

Скилы подхватываются при старте новой сессии. В `~/.agents-config` они лежат в `agents/skills/` и разъезжаются по машинам через `install.sh push`.

## Проверка установки

Проверка HTTP-рукопожатия напрямую, без OMP:

```bash
curl -s -X POST http://127.0.0.1:6280/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}'
```

Ожидаемый результат: `data: {"result":{...,"serverInfo":{"name":"docs-mcp-server",...}}}`.

Smoke-check MCP из OMP-сессии — вызвать инструмент:

```text
вызови xd://mcp__docs_mcp_server_list_libraries
```

Ожидаемый результат: `No libraries indexed yet.` (индекс пуст — это нормально сразу после установки).

Проверить, что запись есть в конфиге OMP:

```bash
grep -q '"docs-mcp-server"' ~/.omp/agent/mcp.json && echo OK
```

### Проверка скилов

Проверить наличие файлов и валидность фронтматтера (поле `name` должно совпадать с именем каталога):

```bash
for s in docs-manage docs-search fetch-url; do
  f=~/.agents/skills/$s/SKILL.md
  [ -f "$f" ] && grep -q "^name: $s" "$f" && echo "OK  $s" || echo "MISSING $s"
done
```

Ожидаемый результат: три строки `OK`.

Финальная верификация — в **новой** OMP-сессии скилы `docs-manage`, `docs-search`, `fetch-url` присутствуют в списке доступных скилов, а инструменты `xd://mcp__docs_mcp_server_*` — в списке MCP-роутов. Скилы монтируются только при старте сессии; MCP-серверы можно перемонтировать в текущей сессии через `/mcp reload`.

## Доступные инструменты

| Роут | Назначение |
|---|---|
| `mcp__docs_mcp_server_scrape_docs` | индексировать документацию с URL/GitHub/npm/PyPI/локальных файлов |
| `mcp__docs_mcp_server_search_docs` | поиск по проиндексированной документации |
| `mcp__docs_mcp_server_fetch_url` | одна страница → Markdown |
| `mcp__docs_mcp_server_find_version` | подобрать подходящую версию библиотеки |
| `mcp__docs_mcp_server_refresh_version` | повторный scrape изменённых страниц |
| `mcp__docs_mcp_server_remove_docs` | удалить версию из индекса |
| `mcp__docs_mcp_server_list_libraries` | список индексированных библиотек |
| `mcp__docs_mcp_server_list_jobs` / `get_job_info` / `cancel_job` | управление задачами скрейпинга |

## Web-интерфейс из Windows (WSL)

По умолчанию сервер слушает `127.0.0.1` — из Windows такой порт недоступен. Запускать на `0.0.0.0`:

```bash
docs-mcp-server --host 0.0.0.0
```

Узнать IP WSL:

```bash
ip -4 addr show eth0 | grep -oP 'inet \K[\d.]+'
```

В Windows открывать `http://<WSL-IP>:6280`.

Важные ограничения:

- IP WSL нестабилен: после перезагрузки WSL/Windows может смениться — узнавать заново.
- Интероп WSL↔Windows (`interop.enabled = false` в `/etc/wsl.conf`) выключен, поэтому привычный `localhost:6280` из Windows не работает: проброс портов localhost в WSL2 включается только при активном интеропе. Доступ только по IP.
- Без автозапуска процесс живёт до перезапуска WSL — настроить systemd user unit (см. «Автозапуск»). На эталонной машине автозапуск уже настроен (unit + linger).

Проверка из WSL:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://<WSL-IP>:6280/
```

Ожидаемый результат: `200`.

## Автозапуск (опционально)

systemd user unit `~/.config/systemd/user/docs-mcp-server.service`:

```ini
[Unit]
Description=Docs MCP Server (@arabold/docs-mcp-server)
After=network.target

[Service]
Type=simple
ExecStart=%h/.local/bin/docs-mcp-server server --protocol http --host 127.0.0.1 --port 6280 --quiet
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
```

Важно: голый `ExecStart=.../docs-mcp-server` (без `server --protocol http`) под systemd **не работает** — без TTY режим `--protocol auto` выбирает stdio, процесс получает EOF на stdin и сразу завершается с кодом 0 (`Restart=on-failure` при этом не срабатывает, сервис остаётся `inactive (dead)`). Проверено экспериментально. Флаги `server --protocol http` обязательны.

```bash
systemctl --user daemon-reload
systemctl --user enable --now docs-mcp-server
loginctl enable-linger $USER   # старт при загрузке WSL, без первого логина
```

Управление: `systemctl --user status|restart|stop docs-mcp-server`, логи — `journalctl --user -u docs-mcp-server -f`.

## Векторный поиск (опционально)

По умолчанию включён только полнотекстовый поиск (`Embeddings: disabled` при старте). Для семантического поиска нужен embedding-провайдер. В HTTP-режиме ключ передаётся в окружении **сервера** (не в `mcp.json`):

```bash
OPENAI_API_KEY="sk-proj-..." docs-mcp-server
```

Другие провайдеры (Ollama, Gemini, Azure): см. docs/guides/embedding-models.md в репозитории.

## Диагностика

### `Cannot find package '.../better-sqlite3'`

Прерванная установка. Лечится полной переустановкой (см. «Установка»).

### `npm ERR! EACCES` при `npm install -g`

Системный префикс недоступен без root. Использовать `--prefix=$HOME/.local`.

### Инструменты `docs_mcp_server` не появляются в сессии

1. Проверить валидность JSON: `python3 -m json.tool ~/.omp/agent/mcp.json`.
2. Проверить, что сервер запущен: `curl -s http://127.0.0.1:6280/`.
3. Выполнить `/mcp reload` в текущей сессии или перезапустить OMP.

### Web-интерфейс не открывается из Windows

1. Проверить, что слушается `0.0.0.0`, а не `127.0.0.1`: `ss -tln | grep 6280`.
2. Проверить, что IP WSL не сменился: `ip -4 addr show eth0`.
3. Помнить: `localhost` из Windows не работает при выключенном интеропе — только прямой IP.

### stdio-вариант (если не нужен постоянный сервер)

Запись в `mcp.json` вместо HTTP:

```json
"docs-mcp-server": {
  "type": "stdio",
  "command": "/home/abobapc/.local/bin/docs-mcp-server",
  "args": ["mcp", "--quiet"]
}
```

Проверка stdio-рукопожатия напрямую:

```bash
printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}\n' | timeout 20 node ~/.local/lib/node_modules/@arabold/docs-mcp-server/dist/index.js mcp --protocol stdio --quiet 2>/dev/null | head -2
```

## Удаление

Убрать запись из `~/.omp/agent/mcp.json`, удалить скилы, затем:

```bash
npm uninstall -g --prefix=$HOME/.local @arabold/docs-mcp-server
rm -rf ~/.agents/skills/{docs-manage,docs-search,fetch-url}
rm -rf ~/.local/share/docs-mcp-server   # индекс документов
rm -rf ~/.config/docs-mcp-server        # конфиг
```

## Источники

- [grounded.tools](https://grounded.tools)
- [arabold/docs-mcp-server](https://github.com/arabold/docs-mcp-server)
- [скилы](https://github.com/arabold/docs-mcp-server/tree/main/skills)
