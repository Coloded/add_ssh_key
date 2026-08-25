# add_ssh_key

Интерактивная установка существующего локального SSH-ключа на удалённые
Unix/Linux, OpenWrt/Dropbear и MikroTik RouterOS.

Установщик самого `add_key` поддерживает macOS и Linux, включая Ubuntu и
Debian. Поддерживаются оболочки Zsh, Bash, Fish и POSIX-совместимые shell.

## Новая установка

Через `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/Coloded/add_ssh_key/main/install.sh | bash
```

Или через `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/Coloded/add_ssh_key/main/install.sh | bash
```

Откройте новый терминал, затем:

```bash
add_key
```

Установщик спросит, куда поставить команду:

1. Только для текущего пользователя — без пароля, вариант по умолчанию:

```text
~/.local/bin/add_key.sh
~/.local/bin/add_key -> add_key.sh
```

2. Для всех пользователей — в `/usr/local/bin`, потребуется пароль `sudo`.

В обоих случаях команда работает из любого каталога. Пользовательские
настройки хранятся в `~/.config/add_key/config`.

Ссылка установки постоянная: установщик сам определяет текущий commit ветки
`main` через GitHub API и скачивает файлы по точному SHA, поэтому устаревший
кэш `raw.githubusercontent.com` не влияет на устанавливаемую версию.

## Обновление

```bash
add_key -update
```

Команда скачивает `add_key.sh` из этого репозитория, проверяет Bash-синтаксис
и номер версии. Актуальный commit ветки также определяется через GitHub API,
после чего обновление скачивается по точному SHA. Предыдущая версия сохраняется
рядом с установленным файлом под именем `add_key.sh.update-backup`.
