#!/usr/bin/env bash

set -euo pipefail

SOURCE_URL="${ADD_KEY_SOURCE_URL:-https://raw.githubusercontent.com/Coloded/add_ssh_key/main/add_key.sh}"
INSTALL_DIR="${ADD_KEY_INSTALL_DIR:-${HOME}/script}"
TARGET_FILE="${INSTALL_DIR}/add_key.sh"
COMMAND_LINK="${INSTALL_DIR}/add_key"
SHELL_CONFIG="${HOME}/.zshrc"
PATH_LINE='export PATH="$HOME/script:$PATH"'

command -v curl >/dev/null 2>&1 || {
  echo "Ошибка: для установки нужен curl."
  exit 1
}

mkdir -p "$INSTALL_DIR"
tmp_file="$(mktemp "${INSTALL_DIR}/.add_key-install.XXXXXX")"
trap 'rm -f "$tmp_file"' EXIT

echo "Скачиваю add_key с GitHub..."
curl -fsSL --connect-timeout 10 --max-time 60 "$SOURCE_URL" -o "$tmp_file"

if ! head -n 1 "$tmp_file" | grep -Eq '^#!.*bash'; then
  echo "Ошибка: загруженный файл не похож на Bash-скрипт."
  exit 1
fi

if ! bash -n "$tmp_file"; then
  echo "Ошибка: загруженный add_key.sh не прошёл bash -n."
  exit 1
fi

version="$(awk -F'"' '/^ADD_KEY_VERSION=/{print $2; exit}' "$tmp_file")"
if [ -z "$version" ]; then
  echo "Ошибка: в загруженном файле отсутствует ADD_KEY_VERSION."
  exit 1
fi

if [ -f "$TARGET_FILE" ] && cmp -s "$TARGET_FILE" "$tmp_file"; then
  echo "Уже установлена последняя версия add_key: $version"
  rm -f "$tmp_file"
else
  if [ -f "$TARGET_FILE" ]; then
    cp "$TARGET_FILE" "${TARGET_FILE}.install-backup"
  fi
  chmod 755 "$tmp_file"
  mv "$tmp_file" "$TARGET_FILE"
fi

ln -sfn "add_key.sh" "$COMMAND_LINK"

touch "$SHELL_CONFIG"
if ! grep -Fqx "$PATH_LINE" "$SHELL_CONFIG"; then
  {
    echo
    echo '# add_key command'
    echo "$PATH_LINE"
  } >> "$SHELL_CONFIG"
fi

trap - EXIT
echo "add_key $version установлен в $INSTALL_DIR"
echo
echo "Открой новый терминал или выполни:"
echo "  source ~/.zshrc"
echo
echo "После этого доступны команды:"
echo "  add_key"
echo "  add_key -update"
