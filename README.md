# add_ssh_key

Интерактивная установка существующего локального SSH-ключа на Unix/Linux,
OpenWrt/Dropbear и MikroTik RouterOS.

## Установка на новый Mac

```bash
curl -fsSL https://raw.githubusercontent.com/Coloded/add_ssh_key/main/install.sh | bash
source ~/.zshrc
```

Затем:

```bash
add_key
```

## Обновление

```bash
add_key -update
```

Команда скачивает `add_key.sh` из этого репозитория, проверяет Bash-синтаксис
и номер версии, сравнивает его с установленным файлом и устанавливает только
изменившуюся версию. Предыдущий файл сохраняется как
`~/script/add_key.sh.update-backup`.
