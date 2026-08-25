#!/usr/bin/env bash

set -euo pipefail

SOURCE_URL="${ADD_KEY_SOURCE_URL:-}"
GITHUB_REPOSITORY="${ADD_KEY_GITHUB_REPOSITORY:-Coloded/add_ssh_key}"
INSTALL_SCOPE="${ADD_KEY_INSTALL_SCOPE:-}"
LEGACY_LINK="${HOME}/script/add_key"
LEGACY_CONFIG="${HOME}/script/add_server_ssh.conf"
PERSONAL_LINK="${HOME}/.local/bin/add_key"
USER_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/add_key"
USER_CONFIG_FILE="${USER_CONFIG_DIR}/config"
SHELL_NAME="$(basename "${SHELL:-sh}")"
FORCE_INSTALL="${ADD_KEY_FORCE_INSTALL:-0}"
USE_SUDO=0

choose_install_scope() {
  local choice

  case "$INSTALL_SCOPE" in
    user|personal|1) INSTALL_SCOPE="user"; return 0 ;;
    system|all|2) INSTALL_SCOPE="system"; return 0 ;;
    "") ;;
    *)
      echo "Ошибка: ADD_KEY_INSTALL_SCOPE должен быть user или system."
      exit 1
      ;;
  esac

  if { exec 3<>/dev/tty; } 2>/dev/null; then
    while :; do
      {
        echo "Куда установить add_key?"
        echo "  1) Только для текущего пользователя — без пароля [по умолчанию]"
        echo "  2) Для всех пользователей — потребуется пароль sudo"
        printf "Выберите [1/2]: "
      } >&3
      IFS= read -r choice <&3 || choice=""
      case "$choice" in
        ""|1) INSTALL_SCOPE="user"; exec 3>&-; return 0 ;;
        2) INSTALL_SCOPE="system"; exec 3>&-; return 0 ;;
        *) echo "Введите 1 или 2." >&3 ;;
      esac
    done
  else
    INSTALL_SCOPE="user"
    echo "Интерактивный терминал недоступен; выбрана установка для текущего пользователя."
    return 0
  fi
}

run_install() {
  if [ "$USE_SUDO" -eq 1 ]; then
    sudo "$@"
  else
    "$@"
  fi
}

add_path_line() {
  local config_file="$1"
  local path_line='export PATH="$HOME/.local/bin:$PATH"'

  mkdir -p "$(dirname "$config_file")"
  touch "$config_file"
  if ! grep -Fqx "$path_line" "$config_file"; then
    {
      echo
      echo '# add_key command'
      echo "$path_line"
    } >> "$config_file"
  fi
}

download_file() {
  local url="$1"
  local destination="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$destination"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=60 -O "$destination" "$url"
  else
    echo "Ошибка: для установки нужен curl или wget."
    return 1
  fi
}

confirm_overwrite() {
  local choice

  if [ "$FORCE_INSTALL" = "1" ]; then
    return 0
  fi
  if ! { exec 3<>/dev/tty; } 2>/dev/null; then
    echo "Ошибка: существующая установка требует подтверждения в терминале."
    echo "Для автоматической перезаписи задайте ADD_KEY_FORCE_INSTALL=1."
    return 1
  fi
  while :; do
    printf "Перезаписать существующую установку? [y/N]: " >&3
    IFS= read -r choice <&3 || choice=""
    case "$choice" in
      y|Y|yes|YES|Yes|д|Д|да|ДА|Да) exec 3>&-; return 0 ;;
      ""|n|N|no|NO|No|н|Н|нет|НЕТ|Нет) exec 3>&-; return 1 ;;
      *) echo "Введите y или n." >&3 ;;
    esac
  done
}

choose_install_scope

if [ -n "${ADD_KEY_INSTALL_DIR:-}" ]; then
  INSTALL_DIR="$ADD_KEY_INSTALL_DIR"
elif [ "$INSTALL_SCOPE" = "system" ]; then
  INSTALL_DIR="/usr/local/bin"
else
  INSTALL_DIR="${HOME}/.local/bin"
fi
TARGET_FILE="${INSTALL_DIR}/add_key.sh"
COMMAND_LINK="${INSTALL_DIR}/add_key"

if [ "$INSTALL_SCOPE" = "system" ] && [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "Ошибка: для установки всем пользователям нужна команда sudo."
    exit 1
  fi
  USE_SUDO=1
fi

tmp_file="$(mktemp "${TMPDIR:-/tmp}/add_key-install.XXXXXX")"
api_file="$(mktemp "${TMPDIR:-/tmp}/add_key-api.XXXXXX")"
trap 'rm -f "$tmp_file" "$api_file"' EXIT

if [ -z "$SOURCE_URL" ]; then
  api_url="https://api.github.com/repos/${GITHUB_REPOSITORY}/commits/main"
  if ! download_file "$api_url" "$api_file"; then
    echo "Ошибка: не удалось определить актуальную версию add_key на GitHub."
    exit 1
  fi
  commit_sha="$(awk -F'"' '/^[[:space:]]*"sha"[[:space:]]*:/ {print $4; exit}' "$api_file")"
  rm -f "$api_file"
  if ! [[ "$commit_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
    echo "Ошибка: GitHub вернул некорректный commit SHA."
    exit 1
  fi
  SOURCE_URL="https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/${commit_sha}/add_key.sh"
fi

echo "Скачиваю add_key с GitHub..."
if ! download_file "$SOURCE_URL" "$tmp_file"; then
  echo "Ошибка: не удалось скачать add_key с GitHub."
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

if { [ -e "$INSTALL_DIR" ] || [ -L "$INSTALL_DIR" ]; } && [ ! -d "$INSTALL_DIR" ]; then
  echo "Ошибка: $INSTALL_DIR существует, но не является каталогом."
  exit 1
fi
if [ ! -d "$INSTALL_DIR" ]; then
  run_install mkdir -p "$INSTALL_DIR"
fi

NEEDS_CONFIRM=0
TARGET_UNCHANGED=0
if [ -f "$TARGET_FILE" ] && cmp -s "$TARGET_FILE" "$tmp_file"; then
  echo "Уже установлена последняя версия add_key: $version"
  TARGET_UNCHANGED=1
else
  if [ -e "$TARGET_FILE" ] || [ -L "$TARGET_FILE" ]; then
    if [ -d "$TARGET_FILE" ]; then
      echo "Ошибка: вместо файла обнаружен каталог: $TARGET_FILE"
      exit 1
    fi
    existing_version="$(awk -F'"' '/^ADD_KEY_VERSION=/{print $2; exit}' "$TARGET_FILE" 2>/dev/null || true)"
    echo "Обнаружена существующая установка: $TARGET_FILE"
    if [ -n "$existing_version" ]; then
      echo "Установлена версия: $existing_version; новая версия: $version"
    fi
    NEEDS_CONFIRM=1
  fi
fi
if { [ -e "$COMMAND_LINK" ] || [ -L "$COMMAND_LINK" ]; } && \
   { [ ! -L "$COMMAND_LINK" ] || [ "$(readlink "$COMMAND_LINK" 2>/dev/null || true)" != "add_key.sh" ]; }; then
  echo "Также существует другая команда: $COMMAND_LINK"
  NEEDS_CONFIRM=1
fi
if [ "$NEEDS_CONFIRM" -eq 1 ] && ! confirm_overwrite; then
  echo "Установка отменена: существующие файлы не изменены."
  exit 0
fi
if [ "$TARGET_UNCHANGED" -eq 0 ]; then
  if [ -f "$TARGET_FILE" ]; then
    run_install cp "$TARGET_FILE" "${TARGET_FILE}.install-backup"
  fi
  run_install install -m 755 "$tmp_file" "$TARGET_FILE"
fi
rm -f "$tmp_file"

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

if [ "$INSTALL_SCOPE" = "user" ]; then
  case "$SHELL_NAME" in
    zsh)
      SHELL_CONFIG="${HOME}/.zshrc"
      add_path_line "$SHELL_CONFIG"
      ;;
    bash)
      if [ "$(uname -s 2>/dev/null || true)" = "Darwin" ]; then
        SHELL_CONFIG="${HOME}/.bash_profile"
      else
        SHELL_CONFIG="${HOME}/.bashrc"
      fi
      add_path_line "$SHELL_CONFIG"
      ;;
    fish)
      SHELL_CONFIG="${HOME}/.config/fish/config.fish"
      mkdir -p "$(dirname "$SHELL_CONFIG")"
      touch "$SHELL_CONFIG"
      FISH_PATH_LINE='fish_add_path "$HOME/.local/bin"'
      grep -Fqx "$FISH_PATH_LINE" "$SHELL_CONFIG" || printf '\n# add_key command\n%s\n' "$FISH_PATH_LINE" >> "$SHELL_CONFIG"
      ;;
    *)
      SHELL_CONFIG="${HOME}/.profile"
      add_path_line "$SHELL_CONFIG"
      ;;
  esac
elif [ -L "$PERSONAL_LINK" ] && [ "$(readlink "$PERSONAL_LINK" 2>/dev/null || true)" = "add_key.sh" ]; then
  rm -f "$PERSONAL_LINK"
  echo "Удалена персональная команда: $PERSONAL_LINK"
fi

trap - EXIT
echo "add_key $version установлен в $INSTALL_DIR"
echo
if [ "$INSTALL_SCOPE" = "system" ]; then
  echo "Команда установлена для всех пользователей: $COMMAND_LINK"
  echo "Если shell запомнил старый путь, открой новый терминал или выполни: hash -r"
else
  echo "Команда установлена для текущего пользователя: $COMMAND_LINK"
  echo "Открой новый терминал или выполни:"
  if [ "$SHELL_NAME" = "fish" ]; then
    echo "  source $SHELL_CONFIG"
  else
    echo "  . $SHELL_CONFIG"
  fi
fi
echo
echo "Доступны команды:"
echo "  add_key"
echo "  add_key -update"
