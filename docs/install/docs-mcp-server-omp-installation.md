# Docs MCP Server (grounded.tools) в Oh My Pi

## Назначение

Инструкция для агента, который должен установить и подключить `docs-mcp-server` (Grounded Docs, https://grounded.tools) в Oh My Pi (OMP).

Целевой результат:

- пакет `@arabold/docs-mcp-server` установлен глобально в пользовательский npm-префикс;
- сервер подключён к OMP через stdio в `~/.omp/agent/mcp.json`;
- MCP-инструменты доступны в сессии под роутами `xd://mcp__docs_mcp_server_*`;
- web-интерфейс доступен из Windows по IP WSL.

Исходники: https://github.com/arabold/docs-mcp-server

## Предварительные условия

Node.js 22+:

```bash
node --version
```

Ожидаемый результат: `v22.x` или выше.

Проверить текущие MCP-серверы OMP:

```bash
cat ~/.omp/agent/mcp.json
```

Не устанавливать пакет системным `npm install -g` без префикса: системный префикс (`/usr/local/lib`) недоступен для записи без root. Использовать пользовательский префикс (см. ниже).

## Установка

Настроить пользовательский npm-префикс:

```bash
mkdir -p ~/.local/npm
npm config set prefix ~/.local/npm
```

Установить пакет:

```bash
npm install -g @arabold/docs-mcp-server
```

Установка долгая (нативные модули, Playwright) — до 10 минут. Не прерывать: прерванная установка оставляет пакет в полуразобранном состоянии (`better-sqlite3` без `package.json`), лечится только полной переустановкой:

```bash
npm uninstall -g @arabold/docs-mcp-server
rm -rf ~/.local/npm/lib/node_modules/@arabold
npm install -g @arabold/docs-mcp-server
```

Проверить нативный модуль:

```bash
node -e "require('/home/agent/.local/npm/lib/node_modules/@arabold/docs-mcp-server/node_modules/better-sqlite3'); console.log('sqlite ok')"
```

Ожидаемый результат: `sqlite ok`.

## Подключение к OMP

В `~/.omp/agent/mcp.json` добавить в `mcpServers`:

```json
"docs-mcp-server": {
  "type": "stdio",
  "command": "/usr/bin/node",
  "args": [
    "/home/agent/.local/npm/lib/node_modules/@arabold/docs-mcp-server/dist/index.js",
    "mcp",
    "--protocol",
    "stdio",
    "--quiet"
  ]
}
```

После правки конфига перезапустить OMP: MCP-серверы монтируются при старте сессии, в уже открытой сессии их не будет.

## Проверка установки

Smoke-check MCP из OMP-сессии — вызвать инструмент:

```text
вызови xd://mcp__docs_mcp_server_list_libraries
```

Ожидаемый результат: `No libraries indexed yet.` (индекс пуст — это нормально сразу после установки).

Проверка stdio-рукопожатия напрямую, без OMP:

```bash
printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}\n' | timeout 20 node /home/agent/.local/npm/lib/node_modules/@arabold/docs-mcp-server/dist/index.js mcp --protocol stdio --quiet 2>/dev/null | head -2
```

Ожидаемый результат: JSON с `"serverInfo":{"name":"docs-mcp-server",...}`.

## Доступные инструменты

| Роут | Назначение |
|---|---|
| `mcp__docs_mcp_server_scrape_docs` | индексировать документацию с URL/GitHub/npm/PyPI/локальных файлов |
| `mcp__docs_mcp_server_search_docs` | поиск по проиндексированной документации |
| `mcp__docs_mcp_server_fetch_url` | одна страница → Markdown |
| `mcp__docs_mcp_server_find_version` | подобрать подходящую версию библиотеки |
| `mcp__docs_mcp_server_refresh_version` | перев scrape изменённых страниц |
| `mcp__docs_mcp_server_remove_docs` | удалить версию из индекса |
| `mcp__docs_mcp_server_list_libraries` | список индексированных библиотек |
| `mcp__docs_mcp_server_list_jobs` / `get_job_info` / `cancel_job` | управление задачами скрейпинга |

## Web-интерфейс из Windows (WSL)

Сервер по умолчанию слушает `127.0.0.1` — из Windows такой порт недоступен. Запускать на `0.0.0.0`:

```bash
nohup node /home/agent/.local/npm/lib/node_modules/@arabold/docs-mcp-server/dist/index.js web --port 6280 --host 0.0.0.0 > /tmp/dms-web.log 2>&1 &
```

Узнать IP WSL:

```bash
ip -4 addr show eth0 | grep -oP 'inet \K[\d.]+'
```

В Windows открывать `http://<WSL-IP>:6280`.

Важные ограничения:

- IP WSL нестабилен: после перезагрузки WSL/Windows может смениться — узнавать заново.
- Интероп WSL↔Windows (`interop.enabled = false` в `/etc/wsl.conf`) выключен, поэтому привычный `localhost:6280` из Windows не работает: проброс портов localhost в WSL2 включается только при активном интеропе. Доступ только по IP.
- Процесс, запущенный через `nohup` из агентской сессии, живёт до перезапуска WSL. Автозапуск не настроен — после рестарта запускать вручную.

Проверка из WSL:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://<WSL-IP>:6280/
```

Ожидаемый результат: `200`.

## Векторный поиск (опционально)

По умолчанию включён только полнотекстовый поиск. Для семантического поиска нужен embedding-провайдер (по умолчанию OpenAI). Передать ключ через `env` в записи `mcp.json`:

```json
"env": { "OPENAI_API_KEY": "sk-proj-..." }
```

Другие провайдеры (Ollama, Gemini, Azure): см. docs/guides/embedding-models.md в репозитории.

## Диагностика

### `Cannot find package '.../better-sqlite3'`

Прерванная установка. Лечится полной переустановкой (см. «Установка»).

### Инструменты `docs_mcp_server` не появляются в сессии

1. Проверить валидность JSON: `python3 -m json.tool ~/.omp/agent/mcp.json`.
2. Полностью перезапустить OMP — серверы монтируются только при старте сессии.

### Web-интерфейс не открывается из Windows

1. Проверить, что слушается `0.0.0.0`, а не `127.0.0.1`: `ss -tln | grep 6280`.
2. Проверить, что IP WSL не сменился: `ip -4 addr show eth0`.
3. Помнить: `localhost` из Windows не работает при выключенном интеропе — только прямой IP.

## Удаление

Убрать запись из `~/.omp/agent/mcp.json`, затем:

```bash
npm uninstall -g @arabold/docs-mcp-server
rm -rf ~/.local/share/docs-mcp-server   # индекс документов
rm -rf ~/.config/docs-mcp-server        # конфиг
```

## Источники

- [grounded.tools](https://grounded.tools)
- [arabold/docs-mcp-server](https://github.com/arabold/docs-mcp-server)
