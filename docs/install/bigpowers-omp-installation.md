# Установка bigpowers в Oh My Pi

## Назначение

Эта инструкция описывает воспроизводимую установку `bigpowers` в OMP (Oh My Pi) с пользовательским scope. Она не устанавливает и не изменяет отдельную установку Pi в `~/.pi`.

Целевая версия: `bigpowers v2.88.7`.

## Предварительные условия

Проверить доступность OMP:

```bash
omp --version
```

Проверить, что GitHub доступен и установленный OMP поддерживает plugins:

```bash
omp plugin --help
```

Не использовать `npm install -g bigpowers` и `bigpowers setup`: эти команды предназначены для установки bigpowers в другие runtimes и могут создать вторую независимую установку.

## Безопасная предварительная проверка

Сначала выполнить dry-run:

```bash
omp plugin install \
  'github:danielvm-git/bigpowers#v2.88.7' \
  --dry-run
```

Для Git-источника ref указывается через `#`, а не через `@`.

Правильно:

```text
github:danielvm-git/bigpowers#v2.88.7
```

Также допустим полный URL:

```bash
omp plugin install \
  'https://github.com/danielvm-git/bigpowers.git#v2.88.7' \
  --dry-run
```

Неправильно:

```text
https://github.com/danielvm-git/bigpowers@v2.88.7
```

Такая запись передаётся Bun как некорректное имя зависимости и заканчивается ошибками `RepositoryNotFound` и `Invalid dependency name`.

Не передавать `--scope=user`: OMP поддерживает `--scope` для marketplace-плагинов. Git/npm-плагины устанавливаются в пользовательский каталог по умолчанию.

## Установка

После успешного dry-run выполнить:

```bash
omp plugin install \
  'github:danielvm-git/bigpowers#v2.88.7'
```

Ожидаемый результат — plugin `bigpowers` в пользовательском OMP-каталоге, обычно под:

```text
~/.omp/plugins/
```

## Проверка установки

Выполнить:

```bash
omp plugin list
omp plugin doctor
```

Ожидаемый результат:

```text
npm Plugins:

● bigpowers@2.88.7
```

`omp plugin doctor` должен закончиться без warnings и errors. Минимально должны быть подтверждены:

- `plugins_directory: Found`;
- `package_manifest: Found`;
- `node_modules: Found`;
- `plugin:bigpowers: v2.88.7`.

После установки полностью перезапустить OMP. Уже запущенный процесс не перечитывает extension автоматически.

## Что устанавливает bigpowers

Пакет содержит:

- skills bigpowers;
- prompt templates;
- OMP/Pi extension `extensions/omp-hooks.ts`;
- инструмент `bigpowers_skill`;
- Git safety guards;
- встроенный MCP manifest `.mcp.json`.

В `package.json` bigpowers ресурсы описаны через старый ключ `pi`. Текущий OMP принимает этот ключ для совместимости, поэтому отдельный ключ `omp` добавлять не требуется.

## Обязательная настройка MCP

В bigpowers v2.88.7 есть файл:

```text
~/.omp/plugins/node_modules/bigpowers/.mcp.json
```

Он запускает сервер так:

```json
{
  "mcpServers": {
    "bigpowers-mcp": {
      "command": "node",
      "args": ["${OMP_PLUGIN_ROOT}/bigpowers-mcp/build/index.js"],
      "cwd": "${OMP_PLUGIN_ROOT}"
    }
  }
}
```

В некоторых OMP/WSL окружениях MCP launcher не наследует shell `PATH`. Тогда появляется ошибка:

```text
ENOENT: no such file or directory, posix_spawn 'node'
```

Это не означает, что bigpowers установлен неправильно. `omp plugin doctor` при этом может завершаться успешно.

### Рекомендуемый вариант: отключить необязательный MCP

Для работы skills, prompts, extension и `bigpowers_skill` этот MCP-сервер не требуется. Отключить только сервер можно в пользовательской конфигурации OMP:

```bash
mkdir -p ~/.omp/agent
```

Создать или обновить `~/.omp/agent/mcp.json`, сохранив существующие настройки `mcpServers`, если они есть. Минимальный файл для чистой установки:

```json
{
  "disabledServers": ["bigpowers-mcp"]
}
```

После изменения полностью перезапустить OMP. Не редактировать файл внутри `~/.omp/plugins/node_modules/bigpowers`: обновление plugin перезапишет его.

### Если MCP действительно нужен

Сначала определить абсолютный путь к Node:

```bash
command -v node
node --version
```

Пример результата:

```text
/usr/bin/node
v22.x.x
```

Затем необходимо сделать OMP-конфигурацию, которая переопределяет сервер с абсолютным `command`:

```json
{
  "mcpServers": {
    "bigpowers-mcp": {
      "command": "/usr/bin/node",
      "args": ["/home/abobapc/.omp/plugins/node_modules/bigpowers/bigpowers-mcp/build/index.js"],
      "cwd": "/home/abobapc/.omp/plugins/node_modules/bigpowers"
    }
  }
}
```

Путь к plugin нужно сверить с фактическим путём установки. Не копировать этот пример вслепую при другой учётной записи, профиле OMP или версии plugin.

Предпочтительный вариант остаётся отключением MCP: native OMP extension уже предоставляет функциональность bigpowers без отдельного MCP-процесса.

## Инициализация проекта

Пакетные skills могут ссылаться на проектные пути `scripts/` и `specs/`. Для каждого проекта, где будут выполняться такие workflow, один раз запустить:

```bash
npx bigpowers@2.88.7 init
```

Команда должна выполняться из корня проекта. Она:

- создаёт managed-ссылку проекта на `scripts/` из пакета;
- создаёт `specs/bugs/`;
- создаёт `specs/verifications/`;
- не должна перезаписывать пользовательский `scripts/`.

Если `scripts/` уже принадлежит проекту, команда остановится и потребует ручного решения. Не удалять существующий каталог автоматически.

Эта команда не нужна только для проверки загрузки skills в OMP; она нужна перед выполнением workflow, которым требуются project-local scripts/specs.

## Runtime smoke-check

После перезапуска OMP проверить фактическую загрузку, а не только наличие файлов:

1. В startup output присутствует bigpowers.
2. Доступен skill `survey-context` или `using-bigpowers`.
3. Доступен инструмент `bigpowers_skill`.
4. Запрос к skill возвращает его инструкции.
5. Запрос на `git reset --hard` блокируется safety guard.
6. Существующий plugin `i-have-adhd` не удалён и продолжает работать.

В интерактивной сессии OMP можно обновить плагины командой:

```text
/reload-plugins
```

Для новой extension, hook или executable tool надёжнее полностью перезапустить OMP.

## Обновление

Git/npm plugin обновляется повторной установкой с новым фиксированным tag или commit:

```bash
omp plugin install \
  'github:danielvm-git/bigpowers#v2.88.8'
```

После обновления выполнить:

```bash
omp plugin doctor
```

Не использовать плавающий `main`, если нужна воспроизводимость.

## Удаление

Сначала проверить точное имя в списке:

```bash
omp plugin list
```

Затем удалить plugin:

```bash
omp plugin uninstall bigpowers
```

После удаления перезапустить OMP. Удаление plugin не должно изменять `~/.pi` или пользовательские файлы проекта.

## Короткий runbook для агента

```bash
# 1. Проверить OMP
omp --version

# 2. Предпросмотр установки
omp plugin install 'github:danielvm-git/bigpowers#v2.88.7' --dry-run

# 3. Установить в user scope
omp plugin install 'github:danielvm-git/bigpowers#v2.88.7'

# 4. Проверить plugin
omp plugin list
omp plugin doctor

# 5. Отключить необязательный MCP, если появляется ENOENT для node
mkdir -p ~/.omp/agent
# затем сохранить disabledServers в ~/.omp/agent/mcp.json

# 6. Перезапустить OMP и выполнить runtime smoke-check
```

## Источники

- [bigpowers repository](https://github.com/danielvm-git/bigpowers)
- [bigpowers v2.88.7 release](https://github.com/danielvm-git/bigpowers/releases/tag/v2.88.7)
- [OMP plugin documentation](https://aieguu.github.io/omp-docs-cn/guide/plugins)
- [OMP MCP configuration](https://github.com/can1357/oh-my-pi/blob/main/docs/mcp-config.md)

**Установка** **bigpowers v2.88.7** в отдельный проект OMP

 OMP поддерживает project scope только для marketplace-плагинов. Для Git-источника параметр --scope project игнорируется. Поэтому нужен небольшой локальный marketplace внутри проекта.

 **### 1. Перейти в корень проекта**

 ```bash
cd /path/to/project
 ```

 Проверьте OMP:

 ```bash
omp --version
omp plugin --help
 ```

 **### 2. Создать локальный marketplace**

 ```bash
mkdir -p .omp/marketplace/.omp-plugin
 ```

 Создайте файл:

 ```text
.omp/marketplace/.omp-plugin/marketplace.json
 ```

 Содержимое:

 ```json
{
  "name": "project-local",
  "owner": {
    "name": "Local project"
  },
  "metadata": {
    "description": "Project-local OMP plugins"
  },
  "plugins": [
    {
      "name": "bigpowers",
      "description": "Agent skills and workflow guards for software development",
      "version": "2.88.7",
      "source": {
        "source": "github",
        "repo": "danielvm-git/bigpowers",
        "ref": "v2.88.7"
      },
      "author": {
        "name": "Daniel"
      },
      "homepage": "https://github.com/danielvm-git/bigpowers",
      "repository": "https://github.com/danielvm-git/bigpowers",
      "license": "MIT"
    }
  ]
}
 ```

 Имя marketplace можно изменить. Далее в командах используйте выбранное имя вместо project-local.

 **### 3. Зарегистрировать marketplace**

 ```bash
omp plugin marketplace add ./.omp/marketplace
 ```

 Проверьте регистрацию:

 ```bash
omp plugin marketplace list
omp plugin discover project-local
 ```

 Ожидаемый результат:

 ```text
Available Plugins (project-local):

  bigpowers@2.88.7
 ```

 Регистрация marketplace хранится в пользовательской конфигурации OMP. Сам plugin при следующем шаге будет установлен только для текущего проекта.

 **### 4. Установить plugin в project scope**

 ```bash
omp plugin install \
  --scope project \
  bigpowers@project-local
 ```

 Ожидаемый результат:

 ```text
Installed bigpowers from project-local (2.88.7)
 ```

 OMP создаст проектный registry:

 ```text
.omp/plugins/installed_plugins.json
 ```

 Код plugin будет находиться в общем кэше OMP, но OMP загрузит эту установку только в данном проекте.

 **### 5. Проверить установку**

 ```bash
omp plugin list --json
omp plugin doctor
 ```

 В списке должна быть запись:

 ```json
{
  "id": "bigpowers@project-local",
  "scope": "project"
}
 ```

 Важно проверить именно:

 ```text
"scope": "project"
 ```

 У bigpowers не должно быть отдельной записи в секции npm.

 **### 6. Перезапустить OMP**

 Для полной загрузки skills можно выполнить:

 ```text
/reload-plugins
 ```

 Но bigpowers также содержит extension и hooks. Поэтому после первой установки рекомендуется полностью завершить и снова запустить OMP из корня проекта.

 После перезапуска проверьте:

 \- доступен skill survey-context;
 \- доступен skill using-bigpowers;
 \- доступен инструмент bigpowers_skill;
 \- i-have-adhd и другие пользовательские plugins продолжают загружаться.

 **Инициализация workflow-файлов**

 Сама установка plugin не создаёт scripts/ и specs/ в проекте.

 Если нужны workflow, которые обращаются к этим каталогам, выполните из корня проекта:

 ```bash
node \
  ~/.omp/plugins/cache/plugins/project-local___bigpowers___2.88.7/bin/bigpowers.js \
  init
 ```

 Команда создаёт:

 ```text
scripts/
specs/bugs/
specs/verifications/
 ```

 Она не заменяет существующий пользовательский каталог scripts/. Если такой каталог уже существует, команда остановится с ошибкой.

 Этот шаг не нужен только для загрузки skills, prompts и extension.

 **Обновление**

 Измените version и ref в marketplace-файле, например:

 ```json
"version": "2.88.8",
"ref": "v2.88.8"
 ```

 Затем выполните:

 ```bash
omp plugin marketplace update project-local
omp plugin upgrade \
  --scope project \
  bigpowers@project-local
 ```

 После обновления:

 ```bash
omp plugin list
omp plugin doctor
 ```

 Затем перезапустите OMP.

 **Удаление**

 ```bash
omp plugin uninstall \
  --scope project \
  bigpowers@project-local
 ```

 После удаления перезапустите OMP.

 Если marketplace больше не нужен:

 ```bash
omp plugin marketplace remove project-local
 ```

 Удаление marketplace само по себе не удаляет установленный plugin. Сначала выполните plugin uninstall.

 **Неправильный способ**

 Не используйте:

 ```bash
omp plugin install \
  'github:danielvm-git/bigpowers#v2.88.7' \
  --scope project
 ```

 OMP выведет предупреждение и установит Git-plugin в пользовательский scope:

 ```text
Warning: --scope is only supported for marketplace installs
 ```

 Также не используйте:

 ```bash
npm install -g bigpowers
bigpowers setup
 ```

 Эти команды создадут отдельную глобальную установку вне project-scoped plugin registry.
