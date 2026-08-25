#!/usr/bin/env bash

set -euo pipefail

SOURCE_URL="${ADD_KEY_SOURCE_URL:-https://raw.githubusercontent.com/Coloded/add_ssh_key/main/add_key.sh}"
INSTALL_DIR="${ADD_KEY_INSTALL_DIR:-/usr/local/bin}"
TARGET_FILE="${INSTALL_DIR}/add_key.sh"
COMMAND_LINK="${INSTALL_DIR}/add_key"
LEGACY_LINK="${HOME}/script/add_key"
LEGACY_CONFIG="${HOME}/script/add_server_ssh.conf"
USER_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/add_key"
USER_CONFIG_FILE="${USER_CONFIG_DIR}/config"
USE_SUDO=0

run_install() {
  if [ "$USE_SUDO" -eq 1 ]; then
    sudo "$@"
  else
    "$@"
  fi
}

tmp_file="$(mktemp "${TMPDIR:-/tmp}/add_key-install.XXXXXX")"
trap 'rm -f "$tmp_file"' EXIT

echo "Скачиваю add_key с GitHub..."
if command -v curl >/dev/null 2>&1; then
  curl -fsSL --connect-timeout 10 --max-time 60 "$SOURCE_URL" -o "$tmp_file"
elif command -v wget >/dev/null 2>&1; then
  wget -q --timeout=60 -O "$tmp_file" "$SOURCE_URL"
else
  echo "Ошибка: для установки нужен curl или wget."
  exit 1
fi

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

if [ ! -d "$INSTALL_DIR" ] || [ ! -w "$INSTALL_DIR" ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "Ошибка: для системной установки в $INSTALL_DIR нужен sudo."
    exit 1
  fi
  USE_SUDO=1
fi

run_install mkdir -p "$INSTALL_DIR"

if [ -f "$TARGET_FILE" ] && cmp -s "$TARGET_FILE" "$tmp_file"; then
  echo "Уже установлена последняя версия add_key: $version"
  rm -f "$tmp_file"
else
  if [ -f "$TARGET_FILE" ]; then
    run_install cp "$TARGET_FILE" "${TARGET_FILE}.install-backup"
  fi
  run_install install -m 755 "$tmp_file" "$TARGET_FILE"
  rm -f "$tmp_file"
fi

run_install ln -sfn "add_key.sh" "$COMMAND_LINK"

if [ -f "$LEGACY_CONFIG" ] && [ ! -e "$USER_CONFIG_FILE" ]; then
  mkdir -p "$USER_CONFIG_DIR"
  cp "$LEGACY_CONFIG" "$USER_CONFIG_FILE"
  chmod 600 "$USER_CONFIG_FILE"
  echo "Настройки перенесены в $USER_CONFIG_FILE"
fi

if [ -L "$LEGACY_LINK" ] && [ "$(readlink "$LEGACY_LINK" 2>/dev/null || true)" = "add_key.sh" ]; then
  rm -f "$LEGACY_LINK"
  echo "Удалена старая пользовательская команда: $LEGACY_LINK"
fi

trap - EXIT
echo "add_key $version установлен в $INSTALL_DIR"
echo
echo "Системная команда установлена: $COMMAND_LINK"
echo "Если shell запомнил старый путь, открой новый терминал или выполни: hash -r"
echo
echo "Доступны команды:"
echo "  add_key"
echo "  add_key -update"
