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

## Обновление

```bash
add_key -update
```

Команда скачивает `add_key.sh` из этого репозитория, проверяет Bash-синтаксис
и номер версии, сравнивает его с установленным файлом и устанавливает только
изменившуюся версию. Предыдущий файл сохраняется как
рядом с установленным `add_key.sh` с именем `add_key.sh.update-backup`.
