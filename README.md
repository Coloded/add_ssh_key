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

Скрипт устанавливается системно:

```text
/usr/local/bin/add_key.sh
/usr/local/bin/add_key -> add_key.sh
```

При необходимости установщик запросит пароль `sudo`. Пользовательские
настройки хранятся отдельно в `~/.config/add_key/config`.

## Обновление

```bash
add_key -update
```

Команда скачивает `add_key.sh` из этого репозитория, проверяет Bash-синтаксис
и номер версии, сравнивает его с установленным файлом и устанавливает только
изменившуюся версию. Предыдущий файл сохраняется как
`/usr/local/bin/add_key.sh.update-backup`.
