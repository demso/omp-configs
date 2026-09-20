# i-have-adhd в Oh My Pi

## Назначение

Инструкция для агента, который должен установить и настроить `i-have-adhd` в Oh My Pi (OMP).

Целевой результат:

- plugin установлен в user scope;
- extension загружается после перезапуска OMP;
- режим можно включать командой `/i-have-adhd`;
- режим включён по умолчанию во всех новых сессиях;
- установка проверена через CLI и runtime smoke-check.

Правки в исходниках plugin не нужны.

## Предварительные условия

Проверить OMP:

```bash
omp --version
omp plugin --help
```

Проверить текущие плагины:

```bash
omp plugin list
```

Не устанавливать этот plugin через `npm install`, `pi install` или ручное копирование файлов. Для OMP используется marketplace installation.

## Установка

Добавить официальный marketplace GitHub-репозитория:

```bash
omp plugin marketplace add ayghri/i-have-adhd
```

Установить plugin в user scope:

```bash
omp plugin install --scope user i-have-adhd@i-have-adhd
```


После установки полностью перезапустить OMP. Plugin index и extension загружаются при старте процесса.

## Проверка установки

Выполнить:

```bash
omp plugin list
```

Ожидаемый результат:

```text
Marketplace Plugins:

  i-have-adhd@i-have-adhd (0.3.0) (user)
```


## Включение в текущей сессии

В новой OMP-сессии выполнить:

```text
/i-have-adhd on
```

Проверить результат:

```text
● ADHD ON
```


Выключить режим в текущей сессии:

```text
/i-have-adhd off
```

или:

```text
stop adhd mode
```

Фразы выключения действуют только на текущую сессию. Они не удаляют plugin и не меняют постоянную конфигурацию.

## Включение по умолчанию

Создать каталог конфигурации OMP, если его ещё нет:

```bash
mkdir -p ~/.omp/agent
```

Создать файл:

```text
~/.omp/agent/i-have-adhd.json
```

Содержимое:

```json
{
  "alwaysOn": true
}
```

После этого полностью перезапустить OMP.

Extension читает `alwaysOn` из `~/.omp/agent/i-have-adhd.json` при запуске сессии. При включённом значении новая сессия стартует с активным ADHD-режимом.

Проверка:

```text
● ADHD ON
```


## Runtime smoke-check

После полного перезапуска OMP выполнить проверку поведения:

1. Убедиться, что отображается `● ADHD ON`.
2. Отправить обычный многошаговый запрос.
3. Проверить, что ответ начинается с действия или команды.
4. Проверить нумерацию шагов.
5. Отправить `stop adhd mode` и убедиться, что режим выключен.

Это важнее, чем один только вывод `omp plugin list`: список доказывает установку, а smoke-check доказывает загрузку extension и применение правил.

## Диагностика

### Команда `/i-have-adhd` отсутствует

1. Полностью закрыть OMP.
2. Запустить OMP заново.
3. Проверить plugin:

```bash
omp plugin list
```

4. Убедиться, что plugin находится в `user` scope и включён.

### `● ADHD ON` не появляется

Проверить файл конфигурации:

```bash
cat ~/.omp/agent/i-have-adhd.json
```

Ожидаемый JSON:

```json
{
  "alwaysOn": true
}
```

Проверить валидность JSON без изменения файлов:

```bash
node -e 'JSON.parse(require("fs").readFileSync(process.env.HOME + "/.omp/agent/i-have-adhd.json", "utf8")); console.log("valid JSON")'
```

Затем полностью перезапустить OMP.


### Конфликт project и user plugin

Проверить:

```bash
omp plugin list
```

Если один и тот же plugin показан как `project` и `user [shadowed]`, активен project-вариант. Его манифест и состояние имеют приоритет.

Не удалять project-вариант вслепую. Сначала запускать OMP из нужного каталога проекта и проверить фактический runtime.


## Удаление

Удалить plugin:

```bash
omp plugin uninstall --scope user i-have-adhd@i-have-adhd
```

Удалить marketplace только если он больше не нужен:

```bash
omp plugin marketplace remove i-have-adhd
```

Удаление marketplace без удаления plugin сначала может оставить неконсистентную установку. Для отключения без удаления используй настройку plugin, если она доступна в установленной версии OMP, или убери `alwaysOn` и не запускай `/i-have-adhd`.

## Короткий runbook для агента

```bash
# Проверить OMP
omp --version

# Добавить marketplace
omp plugin marketplace add ayghri/i-have-adhd

# Установить plugin
omp plugin install --scope user i-have-adhd@i-have-adhd

# Проверить установку
omp plugin list
omp plugin doctor

# Включить по умолчанию
mkdir -p ~/.omp/agent
printf '{\n  "alwaysOn": true\n}\n' > ~/.omp/agent/i-have-adhd.json

# После этого полностью перезапустить OMP
```

## Источники

- [Официальный репозиторий i-have-adhd](https://github.com/ayghri/i-have-adhd)
- Локальная инструкция установленной версии: `~/.omp/plugins/cache/plugins/i-have-adhd___i-have-adhd___0.3.0/INSTALL.md`
- Локальный manifest: `~/.omp/plugins/cache/plugins/i-have-adhd___i-have-adhd___0.3.0/package.json`
