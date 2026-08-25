#!/usr/bin/env bash

set -euo pipefail

ADD_KEY_VERSION="2026.08.25.1"

# Remember explicit environment values so that the precedence remains:
# command line > environment > config file > built-in defaults.
ENV_SERVER_INPUT_SET="${SERVER_INPUT+x}"; ENV_SERVER_INPUT_VALUE="${SERVER_INPUT-}"
ENV_SERVER_IP_SET="${SERVER_IP+x}"; ENV_SERVER_IP_VALUE="${SERVER_IP-}"
ENV_SERVER_HOST_SET="${SERVER_HOST+x}"; ENV_SERVER_HOST_VALUE="${SERVER_HOST-}"
ENV_SERVER_PORT_SET="${SERVER_PORT+x}"; ENV_SERVER_PORT_VALUE="${SERVER_PORT-}"
ENV_USERNAME_SET="${USERNAME+x}"; ENV_USERNAME_VALUE="${USERNAME-}"
ENV_EMAIL_SET="${EMAIL+x}"; ENV_EMAIL_VALUE="${EMAIL-}"
ENV_EXTRA_KNOWN_HOSTS_SET="${EXTRA_KNOWN_HOSTS+x}"; ENV_EXTRA_KNOWN_HOSTS_VALUE="${EXTRA_KNOWN_HOSTS-}"
ENV_REMOTE_SYSTEM_SET="${REMOTE_SYSTEM+x}"; ENV_REMOTE_SYSTEM_VALUE="${REMOTE_SYSTEM-}"
ENV_KEY_PATH_SET="${KEY_PATH+x}"; ENV_KEY_PATH_VALUE="${KEY_PATH-}"
ENV_CONNECT_TIMEOUT_SET="${CONNECT_TIMEOUT+x}"; ENV_CONNECT_TIMEOUT_VALUE="${CONNECT_TIMEOUT-}"
ENV_STRICT_HOST_KEY_CHECKING_SET="${STRICT_HOST_KEY_CHECKING+x}"; ENV_STRICT_HOST_KEY_CHECKING_VALUE="${STRICT_HOST_KEY_CHECKING-}"
ENV_EXPECTED_HOST_KEY_SHA256_SET="${EXPECTED_HOST_KEY_SHA256+x}"; ENV_EXPECTED_HOST_KEY_SHA256_VALUE="${EXPECTED_HOST_KEY_SHA256-}"
ENV_BULK_CONFIG_FILE_SET="${BULK_CONFIG_FILE+x}"; ENV_BULK_CONFIG_FILE_VALUE="${BULK_CONFIG_FILE-}"
ENV_BULK_STRICT_EXIT_SET="${BULK_STRICT_EXIT+x}"; ENV_BULK_STRICT_EXIT_VALUE="${BULK_STRICT_EXIT-}"
ENV_BULK_KEY_FILE_SET="${BULK_KEY_FILE+x}"; ENV_BULK_KEY_FILE_VALUE="${BULK_KEY_FILE-}"
ENV_UPDATE_URL_SET="${UPDATE_URL+x}"; ENV_UPDATE_URL_VALUE="${UPDATE_URL-}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/add_server_ssh.conf}"
BULK_CONFIG_FILE="${BULK_CONFIG_FILE:-${SCRIPT_DIR}/passwords/servers.json}"
BULK_STRICT_EXIT="${BULK_STRICT_EXIT:-0}"
BULK_KEY_FILE="${BULK_KEY_FILE:-}"
UPDATE_URL="${UPDATE_URL:-https://raw.githubusercontent.com/Coloded/add_ssh_key/main/add_key.sh}"
KEY_PATH="${KEY_PATH:-${HOME}/.ssh/id_ed25519}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-8}"
STRICT_HOST_KEY_CHECKING="${STRICT_HOST_KEY_CHECKING:-accept-new}"
EXPECTED_HOST_KEY_SHA256="${EXPECTED_HOST_KEY_SHA256:-}"
SERVER_IP="${SERVER_IP:-}"
SERVER_HOST="${SERVER_HOST:-}"
SERVER_PORT="${SERVER_PORT:-}"
USERNAME="${USERNAME:-}"
EMAIL="${EMAIL:-}"
EXTRA_KNOWN_HOSTS="${EXTRA_KNOWN_HOSTS:-}"
REMOTE_SYSTEM="${REMOTE_SYSTEM:-auto}"
SERVER_INPUT="${SERVER_INPUT:-}"
SERVER_PASSWORD="${SERVER_PASSWORD:-}"
BULK_MODE=0
UPDATE_MODE=0
PARSED_PORT=""
PARSED_USERNAME=0
HOST_ALIASES=""

SSH_TARGET=""
SSH_OPTS=()
SCP_OPTS=()
REMOTE_DETECT_LAST_OUTPUT=""
BULK_CURRENT_SERVER_B64=""
BULK_FAILED_SERVERS_B64=()
BULK_KEY_CANDIDATES=()
BULK_FAILED_SERVERS_COUNT=0
BULK_KEY_CANDIDATES_COUNT=0

load_config_file() {
  local line key value

  [ -f "$CONFIG_FILE" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] || continue
    [[ "$line" == *=* ]] || continue

    key="${line%%=*}"
    value="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    case "$value" in
      \"*\") value="${value#\"}"; value="${value%\"}" ;;
      \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac

    case "$key" in
      SERVER_INPUT|SERVER_IP|SERVER_HOST|SERVER_PORT|USERNAME|EMAIL|EXTRA_KNOWN_HOSTS|REMOTE_SYSTEM|KEY_PATH|CONNECT_TIMEOUT|STRICT_HOST_KEY_CHECKING|EXPECTED_HOST_KEY_SHA256|BULK_CONFIG_FILE|BULK_STRICT_EXIT|BULK_KEY_FILE|UPDATE_URL)
        printf -v "$key" '%s' "$value"
        ;;
      *)
        echo "Игнорирую неизвестный параметр в $CONFIG_FILE: $key"
        ;;
    esac
  done < "$CONFIG_FILE"
}

restore_environment_overrides() {
  [ -n "$ENV_SERVER_INPUT_SET" ] && SERVER_INPUT="$ENV_SERVER_INPUT_VALUE"
  [ -n "$ENV_SERVER_IP_SET" ] && SERVER_IP="$ENV_SERVER_IP_VALUE"
  [ -n "$ENV_SERVER_HOST_SET" ] && SERVER_HOST="$ENV_SERVER_HOST_VALUE"
  [ -n "$ENV_SERVER_PORT_SET" ] && SERVER_PORT="$ENV_SERVER_PORT_VALUE"
  [ -n "$ENV_USERNAME_SET" ] && USERNAME="$ENV_USERNAME_VALUE"
  [ -n "$ENV_EMAIL_SET" ] && EMAIL="$ENV_EMAIL_VALUE"
  [ -n "$ENV_EXTRA_KNOWN_HOSTS_SET" ] && EXTRA_KNOWN_HOSTS="$ENV_EXTRA_KNOWN_HOSTS_VALUE"
  [ -n "$ENV_REMOTE_SYSTEM_SET" ] && REMOTE_SYSTEM="$ENV_REMOTE_SYSTEM_VALUE"
  [ -n "$ENV_KEY_PATH_SET" ] && KEY_PATH="$ENV_KEY_PATH_VALUE"
  [ -n "$ENV_CONNECT_TIMEOUT_SET" ] && CONNECT_TIMEOUT="$ENV_CONNECT_TIMEOUT_VALUE"
  [ -n "$ENV_STRICT_HOST_KEY_CHECKING_SET" ] && STRICT_HOST_KEY_CHECKING="$ENV_STRICT_HOST_KEY_CHECKING_VALUE"
  [ -n "$ENV_EXPECTED_HOST_KEY_SHA256_SET" ] && EXPECTED_HOST_KEY_SHA256="$ENV_EXPECTED_HOST_KEY_SHA256_VALUE"
  [ -n "$ENV_BULK_CONFIG_FILE_SET" ] && BULK_CONFIG_FILE="$ENV_BULK_CONFIG_FILE_VALUE"
  [ -n "$ENV_BULK_STRICT_EXIT_SET" ] && BULK_STRICT_EXIT="$ENV_BULK_STRICT_EXIT_VALUE"
  [ -n "$ENV_BULK_KEY_FILE_SET" ] && BULK_KEY_FILE="$ENV_BULK_KEY_FILE_VALUE"
  [ -n "$ENV_UPDATE_URL_SET" ] && UPDATE_URL="$ENV_UPDATE_URL_VALUE"
  return 0
}

usage() {
  cat <<EOF
Usage:
  $(basename "$0")
  $(basename "$0") user@host[:port]
  $(basename "$0") -conf [path/to/servers.json]
  $(basename "$0") -update [GitHub URL]

Options:
  -conf, --conf   Read servers from JSON and install the local public key on each one.
                  In -conf mode, if SSH on port 22 is unavailable, try port 122.
  -update         Download, verify and install the latest add_key.sh from GitHub.
  -h, --help      Show this help.

Environment:
  BULK_CONFIG_FILE   JSON path for -conf mode. Default: ${BULK_CONFIG_FILE}
  BULK_STRICT_EXIT   Return exit code 1 when some servers fail. Default: ${BULK_STRICT_EXIT}
  BULK_KEY_FILE      Private key to try for failed servers in -conf mode.
  KEY_PATH           Private key path. Default: ${KEY_PATH}
  CONNECT_TIMEOUT    SSH timeout in seconds. Default: ${CONNECT_TIMEOUT}
EOF
}

parse_args() {
  local server_arg_seen=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -conf|--conf)
        BULK_MODE=1
        if [ "${2:-}" != "" ] && [[ "${2:-}" != -* ]]; then
          BULK_CONFIG_FILE="$2"
          shift
        fi
        ;;
      -update|--update)
        UPDATE_MODE=1
        if [ "${2:-}" != "" ] && [[ "${2:-}" != -* ]]; then
          UPDATE_URL="$2"
          shift
        fi
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        if [ "$server_arg_seen" -eq 0 ]; then
          SERVER_INPUT="$1"
          server_arg_seen=1
        else
          echo "Ошибка: неизвестный или лишний аргумент: $1"
          usage
          exit 1
        fi
        ;;
    esac
    shift
  done
}

load_config_file
restore_environment_overrides
parse_args "$@"

SERVER_INPUT="${SERVER_INPUT:-${SERVER_IP:-${SERVER_HOST:-}}}"

confirm() {
  local prompt="${1:-Продолжить? [y/N]: }"
  local answer

  read -r -p "$prompt" answer
  case "$answer" in
    y|Y|yes|YES|д|Д|да|ДА) return 0 ;;
    *) return 1 ;;
  esac
}

ask_required() {
  local var_name="$1"
  local prompt_text="$2"
  local input_value
  local current_value="${!var_name:-}"

  while [ -z "$current_value" ]; do
    read -r -p "${prompt_text}: " input_value
    current_value="$input_value"
  done

  printf -v "$var_name" '%s' "$current_value"
}

ask_with_default() {
  local var_name="$1"
  local prompt_text="$2"
  local default_value="$3"
  local input_value
  local current_value="${!var_name:-}"

  if [ -n "$current_value" ]; then
    return 0
  fi

  if [ -n "$default_value" ]; then
    read -r -p "${prompt_text} [${default_value}]: " input_value
    if [ -z "$input_value" ]; then
      input_value="$default_value"
    fi
  else
    read -r -p "${prompt_text}: " input_value
  fi

  printf -v "$var_name" '%s' "$input_value"
}

ask_password() {
  local input_value

  [ -n "${SERVER_PASSWORD:-}" ] && return 0
  [ -t 0 ] || return 0

  while [ -z "${SERVER_PASSWORD:-}" ]; do
    read -r -s -p "Введите пароль пользователя ${USERNAME:-root} на сервере: " input_value
    echo
    SERVER_PASSWORD="$input_value"
  done
}

ask_password_again() {
  SERVER_PASSWORD=""
  echo "Пароль не подошёл или парольный вход запрещён."
  ask_password
}

ask_new_port() {
  local input_value

  while true; do
    read -r -p "SSH на порту ${SERVER_PORT} недоступен. Введите другой порт: " input_value
    if [[ "$input_value" =~ ^[0-9]+$ ]] && [ "$input_value" -ge 1 ] && [ "$input_value" -le 65535 ]; then
      SERVER_PORT="$input_value"
      return 0
    fi
    echo "SSH-порт должен быть числом от 1 до 65535."
  done
}

default_email() {
  local local_user
  local local_host

  local_user="$(id -un 2>/dev/null || printf '%s' "${USER:-user}")"
  local_host="$(hostname -f 2>/dev/null || hostname 2>/dev/null || printf 'local')"
  local_host="${local_host%% *}"

  if [[ "$local_host" != *.* ]]; then
    local_host="${local_host}.local"
  fi

  printf '%s@%s' "$local_user" "$local_host"
}

normalize_server_input() {
  local value="$1"

  value="${value#ssh://}"
  value="${value#http://}"
  value="${value#https://}"
  value="${value%%/*}"

  printf '%s' "$value"
}

parse_server_input() {
  local raw="$1"

  raw="$(normalize_server_input "$raw")"

  if [[ "$raw" =~ [[:space:]] ]]; then
    echo "Ошибка: адрес сервера содержит пробелы: $raw"
    exit 1
  fi

  if [[ "$raw" == *@* ]]; then
    if [[ "${raw#*@}" == *@* ]]; then
      echo "Ошибка: адрес содержит больше одного символа @: $raw"
      exit 1
    fi
    USERNAME="${raw%@*}"
    PARSED_USERNAME=1
    if [ -z "$USERNAME" ]; then
      echo "Ошибка: пустое имя пользователя в адресе: $raw"
      exit 1
    fi
    raw="${raw#*@}"
  fi

  if [[ "$raw" =~ ^\[([^]]+)\]:([0-9]+)$ ]]; then
    SERVER_HOST="${BASH_REMATCH[1]}"
    PARSED_PORT="${BASH_REMATCH[2]}"
  elif [[ "$raw" =~ ^\[([^]]+)\]$ ]]; then
    SERVER_HOST="${BASH_REMATCH[1]}"
  elif [[ "$raw" =~ ^([^:]+):([0-9]+)$ ]]; then
    SERVER_HOST="${BASH_REMATCH[1]}"
    PARSED_PORT="${BASH_REMATCH[2]}"
  else
    SERVER_HOST="$raw"
  fi
}

save_config_value() {
  local config_key="$1"
  local config_value="$2"
  local escaped_value
  local tmp_file

  escaped_value="${config_value//\\/\\\\}"
  escaped_value="${escaped_value//\"/\\\"}"
  if ! tmp_file="$(mktemp "${CONFIG_FILE}.tmp.XXXXXX" 2>/dev/null)"; then
    echo "Предупреждение: не удалось сохранить $config_key в $CONFIG_FILE" >&2
    return 0
  fi

  if [ -f "$CONFIG_FILE" ]; then
    if ! awk -v key="$config_key" -v replacement="${config_key}=\"${escaped_value}\"" '
      BEGIN { replaced=0 }
      $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
        if (!replaced) print replacement
        replaced=1
        next
      }
      { print }
      END { if (!replaced) print replacement }
    ' "$CONFIG_FILE" > "$tmp_file"; then
      rm -f "$tmp_file"
      echo "Предупреждение: не удалось сохранить $config_key в $CONFIG_FILE" >&2
      return 0
    fi
  else
    printf '%s="%s"\n' "$config_key" "$escaped_value" > "$tmp_file"
  fi

  if ! mv "$tmp_file" "$CONFIG_FILE"; then
    rm -f "$tmp_file"
    echo "Предупреждение: не удалось сохранить $config_key в $CONFIG_FILE" >&2
  fi
  return 0
}

ask_email() {
  local default_value="${EMAIL:-admin@${SERVER_HOST}}"
  local input_value

  if [ -t 0 ]; then
    read -r -p "Email/comment для ключа [${default_value}]: " input_value
    EMAIL="${input_value:-$default_value}"
    save_config_value EMAIL "$EMAIL"
  else
    EMAIL="$default_value"
  fi
}

normalize_update_url() {
  local value="$1"
  local rest
  local path
  local i
  local parts=()

  value="${value%.git}"
  value="${value%/}"
  if [[ "$value" == git@github.com:* ]]; then
    value="https://github.com/${value#git@github.com:}"
  fi

  case "$value" in
    https://raw.githubusercontent.com/*)
      printf '%s' "$value"
      ;;
    https://github.com/*)
      rest="${value#https://github.com/}"
      IFS=/ read -r -a parts <<< "$rest"
      if [ "${#parts[@]}" -eq 2 ]; then
        printf 'https://raw.githubusercontent.com/%s/%s/main/add_key.sh' "${parts[0]}" "${parts[1]}"
      elif [ "${#parts[@]}" -ge 5 ] && [ "${parts[2]}" = "blob" ]; then
        path="${parts[4]}"
        i=5
        while [ "$i" -lt "${#parts[@]}" ]; do
          path="${path}/${parts[$i]}"
          i=$((i + 1))
        done
        printf 'https://raw.githubusercontent.com/%s/%s/%s/%s' "${parts[0]}" "${parts[1]}" "${parts[3]}" "$path"
      else
        return 1
      fi
      ;;
    *) return 1 ;;
  esac
}

main_update() {
  local input_url="$UPDATE_URL"
  local download_url
  local target_file="${SCRIPT_DIR}/add_key.sh"
  local tmp_file
  local file_mode
  local remote_version

  if [ -z "$input_url" ]; then
    if [ ! -t 0 ]; then
      echo "Ошибка: UPDATE_URL не задан. Используй: add_key -update https://github.com/OWNER/REPO"
      return 1
    fi
    read -r -p "GitHub URL репозитория или add_key.sh: " input_url
  fi

  if ! download_url="$(normalize_update_url "$input_url")"; then
    echo "Ошибка: нужна ссылка github.com или raw.githubusercontent.com"
    return 1
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "Ошибка: для обновления нужен curl."
    return 1
  fi

  if ! tmp_file="$(mktemp "${SCRIPT_DIR}/.add_key-update.XXXXXX" 2>/dev/null)"; then
    echo "Ошибка: нет прав на обновление в ${SCRIPT_DIR}"
    return 1
  fi

  echo "Проверяю обновление: $download_url"
  if ! curl -fsSL --connect-timeout 10 --max-time 60 "$download_url" -o "$tmp_file"; then
    rm -f "$tmp_file"
    echo "Ошибка: не удалось скачать add_key.sh с GitHub."
    return 1
  fi

  if ! head -n 1 "$tmp_file" | grep -Eq '^#!.*bash'; then
    rm -f "$tmp_file"
    echo "Ошибка: загруженный файл не похож на Bash-скрипт."
    return 1
  fi
  if ! bash -n "$tmp_file"; then
    rm -f "$tmp_file"
    echo "Ошибка: загруженный скрипт не прошёл bash -n."
    return 1
  fi

  remote_version="$(awk -F'"' '/^ADD_KEY_VERSION=/{print $2; exit}' "$tmp_file")"
  if [ -z "$remote_version" ]; then
    rm -f "$tmp_file"
    echo "Ошибка: в загруженном скрипте нет ADD_KEY_VERSION."
    return 1
  fi
  if [[ "$remote_version" < "$ADD_KEY_VERSION" ]]; then
    rm -f "$tmp_file"
    echo "На GitHub версия старее: $remote_version; установлена: $ADD_KEY_VERSION."
    return 1
  fi

  save_config_value UPDATE_URL "$download_url"
  if cmp -s "$target_file" "$tmp_file"; then
    rm -f "$tmp_file"
    echo "У вас уже последняя версия add_key: $ADD_KEY_VERSION"
    return 0
  fi

  file_mode="$(stat -f '%Lp' "$target_file" 2>/dev/null || stat -c '%a' "$target_file" 2>/dev/null || printf '755')"
  chmod "$file_mode" "$tmp_file"
  cp "$target_file" "${target_file}.update-backup"
  if ! mv "$tmp_file" "$target_file"; then
    rm -f "$tmp_file"
    echo "Ошибка: не удалось установить обновление."
    return 1
  fi

  echo "add_key обновлён: $ADD_KEY_VERSION → $remote_version"
  echo "Backup: ${target_file}.update-backup"
}

validate_inputs() {
  if [ -z "$SERVER_HOST" ]; then
    echo "Ошибка: пустой адрес сервера"
    exit 1
  fi

  if [[ "$SERVER_HOST" =~ [[:space:]] ]]; then
    echo "Ошибка: адрес сервера содержит пробелы: $SERVER_HOST"
    exit 1
  fi

  if ! [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; then
    echo "Ошибка: SSH-порт должен быть числом от 1 до 65535"
    exit 1
  fi

  if [ -z "$USERNAME" ]; then
    echo "Ошибка: пустое имя пользователя"
    exit 1
  fi

  if [ -z "$EMAIL" ]; then
    echo "Ошибка: пустой email/comment для ключа"
    exit 1
  fi
}

ensure_ssh_dir() {
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
}

build_connection_options() {
  SSH_TARGET="${USERNAME}@${SERVER_HOST}"
  SSH_OPTS=(
    -p "$SERVER_PORT"
    -o "ConnectTimeout=${CONNECT_TIMEOUT}"
    -o "StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING}"
    -o "UserKnownHostsFile=${HOME}/.ssh/known_hosts"
    -i "$KEY_PATH"
    -o IdentitiesOnly=yes
  )
  SCP_OPTS=(
    -P "$SERVER_PORT"
    -o "ConnectTimeout=${CONNECT_TIMEOUT}"
    -o "StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING}"
    -o "UserKnownHostsFile=${HOME}/.ssh/known_hosts"
    -i "$KEY_PATH"
    -o IdentitiesOnly=yes
  )
}

known_host_name_for() {
  local host="$1"

  if [ "$SERVER_PORT" = "22" ]; then
    printf '%s' "$host"
  else
    printf '[%s]:%s' "$host" "$SERVER_PORT"
  fi
}

add_host_alias() {
  local host="$1"
  local existing

  [ -n "$host" ] || return 0
  [[ "$host" =~ [[:space:]] ]] && return 0

  for existing in $HOST_ALIASES; do
    [ "$existing" = "$host" ] && return 0
  done

  HOST_ALIASES="${HOST_ALIASES:+$HOST_ALIASES }$host"
}

add_extra_host_aliases() {
  local value="$EXTRA_KNOWN_HOSTS"
  local host

  value="${value//,/ }"
  for host in $value; do
    add_host_alias "$host"
  done
}

build_host_aliases() {
  local alias
  local alias_count=0

  HOST_ALIASES=""
  add_host_alias "$SERVER_HOST"
  add_extra_host_aliases

  for alias in $HOST_ALIASES; do
    alias_count=$((alias_count + 1))
  done

  if [ "$alias_count" -gt 1 ]; then
    echo "Дополнительные имена known_hosts:"
    for alias in $HOST_ALIASES; do
      echo "  - $(known_host_name_for "$alias")"
    done
  fi
}

remove_known_host_entry() {
  local host="$1"

  ssh-keygen -R "$host" >/dev/null 2>&1 || true
  ssh-keygen -R "[$host]:$SERVER_PORT" >/dev/null 2>&1 || true
}

scan_host_key() {
  local host="$1"
  local action="${2:-add}"
  local tmp_file
  local fingerprints

  ensure_ssh_dir
  tmp_file="$(mktemp "${TMPDIR:-/tmp}/add-keyscan.XXXXXX")"
  ssh-keyscan -T "$CONNECT_TIMEOUT" -p "$SERVER_PORT" "$host" > "$tmp_file" 2>/dev/null || true

  if [ -s "$tmp_file" ]; then
    fingerprints="$(ssh-keygen -l -E sha256 -f "$tmp_file" 2>/dev/null || ssh-keygen -l -f "$tmp_file" 2>/dev/null || true)"
    echo
    echo "Новые SSH host key для $(known_host_name_for "$host"):"
    echo "$fingerprints"
    echo

    if [ -n "$EXPECTED_HOST_KEY_SHA256" ]; then
      if ! printf '%s\n' "$fingerprints" | grep -Fq "$EXPECTED_HOST_KEY_SHA256"; then
        echo "Ошибка: host key не совпал с EXPECTED_HOST_KEY_SHA256=$EXPECTED_HOST_KEY_SHA256"
        rm -f "$tmp_file"
        return 1
      fi
    elif [ "$action" = "replace" ]; then
      if ! confirm "Очистить старую запись known_hosts и записать этот новый ключ? [y/N]: "; then
        rm -f "$tmp_file"
        return 1
      fi
    elif ! confirm "Доверять этому host key и добавить его? [y/N]: "; then
      rm -f "$tmp_file"
      return 1
    fi

    if [ "$action" = "replace" ]; then
      remove_known_host_entry "$host"
    fi
    cat "$tmp_file" >> "${HOME}/.ssh/known_hosts"
    rm -f "$tmp_file"
    chmod 600 "${HOME}/.ssh/known_hosts" 2>/dev/null || true
    return 0
  fi

  rm -f "$tmp_file"
  return 1
}

check_one_host_key() {
  local host="$1"
  local output
  local rc
  local target

  target="${USERNAME}@${host}"

  set +e
  output=$(ssh \
    -p "$SERVER_PORT" \
    -o BatchMode=yes \
    -o PreferredAuthentications=publickey \
    -o PasswordAuthentication=no \
    -o KbdInteractiveAuthentication=no \
    -o StrictHostKeyChecking=yes \
    -o "ConnectTimeout=3" \
    "$target" "exit" 2>&1)
  rc=$?
  set -e

  if echo "$output" | grep -q "REMOTE HOST IDENTIFICATION HAS CHANGED"; then
    echo
    echo "Обнаружено изменение host key у сервера $(known_host_name_for "$host"):"
    echo "$output"
    echo

    if scan_host_key "$host" replace; then
      echo "Host key заменён в known_hosts."
    else
      echo "Операция отменена."
      return 1
    fi
  elif echo "$output" | grep -Eqi "No .* host key is known|Host key verification failed|The authenticity of host"; then
    echo "Host key для $(known_host_name_for "$host") ещё не записан."
    if scan_host_key "$host" add; then
      echo "Host key добавлен в known_hosts для домена/IP."
    else
      echo "ssh-keyscan не получил или не подтвердил host key."
      if confirm "Продолжить через StrictHostKeyChecking=accept-new? [y/N]: "; then
        STRICT_HOST_KEY_CHECKING="accept-new"
      else
        echo "Операция отменена."
        exit 1
      fi
    fi
  fi

  if [ "$rc" -eq 255 ]; then
    if echo "$output" | grep -Eqi "no route to host|operation timed out|connection timed out|connection refused|connection closed|connection reset|kex_exchange_identification|invalid format|banner line"; then
      echo
      echo "Ошибка SSH-подключения:"
      echo "$output"
      return 2
    fi
    if echo "$output" | grep -Eqi "could not resolve hostname"; then
      echo "Ошибка: hostname не резолвится: $host"
      return 1
    fi
  fi
}

check_host_key_conflict() {
  local host
  local rc

  for host in $HOST_ALIASES; do
    if check_one_host_key "$host"; then
      rc=0
    else
      rc=$?
    fi
    [ "$rc" -eq 0 ] || return "$rc"
  done
}

prepare_existing_key() {
  local derived_key
  local derived_key_raw
  local public_key
  local timestamp

  ensure_ssh_dir

  if [ ! -f "$KEY_PATH" ]; then
    echo "Ошибка: локальный приватный ключ не найден: $KEY_PATH"
    echo "Скрипт не создаёт новые ключи автоматически."
    exit 1
  fi

  if ! derived_key_raw="$(ssh-keygen -y -f "$KEY_PATH" 2>/dev/null)"; then
    echo "Ошибка: ssh-keygen не может прочитать локальный ключ: $KEY_PATH"
    exit 1
  fi
  derived_key="$(printf '%s\n' "$derived_key_raw" | awk 'NR==1 {print $1 " " $2}')"
  if [ -z "$derived_key" ]; then
    echo "Ошибка: из приватного ключа не удалось получить публичную часть."
    exit 1
  fi

  if [ ! -f "${KEY_PATH}.pub" ]; then
    echo "Публичного ключа нет, восстанавливаю из приватного..."
    printf '%s %s\n' "$derived_key" "$EMAIL" > "${KEY_PATH}.pub"
  else
    public_key="$(awk 'NR==1 {print $1 " " $2}' "${KEY_PATH}.pub" 2>/dev/null || true)"
    if [ "$public_key" != "$derived_key" ]; then
      timestamp="$(date +%Y%m%d-%H%M%S)"
      mv "${KEY_PATH}.pub" "${KEY_PATH}.pub.backup.${timestamp}"
      echo "Публичный ключ не соответствовал приватному и был восстановлен."
    fi
    printf '%s %s\n' "$derived_key" "$EMAIL" > "${KEY_PATH}.pub"
  fi

  echo "Использую локальный ключ: $KEY_PATH"
  chmod 600 "$KEY_PATH"
  chmod 644 "${KEY_PATH}.pub"
}

public_key_line() {
  local line

  IFS= read -r line < "${KEY_PATH}.pub"
  case "$line" in
    ssh-*|ecdsa-*|sk-*) printf '%s' "$line" ;;
    *)
      echo "Ошибка: ${KEY_PATH}.pub не похож на SSH public key"
      exit 1
      ;;
  esac
}

shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

password_command() {
  local binary="$1"
  local timeout

  shift

  if [ -z "${SERVER_PASSWORD:-}" ]; then
    "$binary" "$@"
    return $?
  fi

  if command -v sshpass >/dev/null 2>&1; then
    SSHPASS="$SERVER_PASSWORD" sshpass -e "$binary" "$@"
    return $?
  fi

  if ! command -v expect >/dev/null 2>&1; then
    echo "Ошибка: для -conf нужен sshpass или expect, чтобы передать пароль из JSON без ручного ввода."
    return 127
  fi

  timeout=$((CONNECT_TIMEOUT + 20))
  ADD_KEY_PASSWORD="$SERVER_PASSWORD" ADD_KEY_EXPECT_TIMEOUT="$timeout" expect -f - -- "$binary" "$@" <<'EXPECT'
set timeout $env(ADD_KEY_EXPECT_TIMEOUT)
set password $env(ADD_KEY_PASSWORD)
set password_prompts 0
set captured ""

# The password was already read by the shell. Hide expect's copy of the
# interactive password prompt so it does not look like a second request.
log_user 0

spawn -noecho {*}$argv
expect {
  -re "(?i)are you sure you want to continue connecting.*" {
    append captured $expect_out(buffer)
    send -- "yes\r"
    exp_continue
  }
  -re "(?i)(password|passphrase).*:" {
    set chunk $expect_out(buffer)
    regsub -all -nocase {[^\r\n]*(password|passphrase)[^\r\n]*:[ ]*} $chunk "" chunk
    append captured $chunk
    incr password_prompts
    if {$password_prompts > 3} {
      puts -nonewline $captured
      exit 124
    }
    send -- "$password\r"
    exp_continue
  }
  eof {
    append captured $expect_out(buffer)
    puts -nonewline $captured
    set wait_result [wait]
    exit [lindex $wait_result 3]
  }
  timeout {
    append captured $expect_out(buffer)
    puts -nonewline $captured
    exit 124
  }
}
EXPECT
}

password_ssh() {
  password_command ssh "$@"
}

password_ssh_capture() {
  local result_var="$1"
  local stdout_file
  local stderr_file
  local stderr_pipe
  local tee_pid
  local captured_text
  local rc
  local had_errexit=0

  shift
  stdout_file="$(mktemp "${TMPDIR:-/tmp}/add-key-ssh-out.XXXXXX")"
  stderr_file="$(mktemp "${TMPDIR:-/tmp}/add-key-ssh-err.XXXXXX")"
  stderr_pipe=""
  tee_pid=""

  [[ "$-" == *e* ]] && had_errexit=1
  set +e
  if [ -z "${SERVER_PASSWORD:-}" ]; then
    stderr_pipe="$(mktemp "${TMPDIR:-/tmp}/add-key-ssh-err-pipe.XXXXXX")"
    rm -f "$stderr_pipe"
    if mkfifo "$stderr_pipe"; then
      tee "$stderr_file" < "$stderr_pipe" >&2 &
      tee_pid=$!
      password_ssh "$@" >"$stdout_file" 2>"$stderr_pipe"
      rc=$?
      wait "$tee_pid" 2>/dev/null || true
      rm -f "$stderr_pipe"
    else
      password_ssh "$@" >"$stdout_file" 2>"$stderr_file"
      rc=$?
      cat "$stderr_file" >&2
    fi
  else
    password_ssh "$@" >"$stdout_file" 2>"$stderr_file"
    rc=$?
  fi
  if [ "$had_errexit" -eq 1 ]; then
    set -e
  else
    set +e
  fi

  captured_text="$(cat "$stdout_file" "$stderr_file" 2>/dev/null || true)"
  rm -f "$stdout_file" "$stderr_file"
  printf -v "$result_var" '%s' "$captured_text"
  return "$rc"
}

verify_key_login_quiet() {
  local system_type="$1"
  local command
  local output
  local rc

  if [ "$system_type" = "routeros" ]; then
    command=':put "KEY_LOGIN_OK"'
  else
    command='printf "%s\n" KEY_LOGIN_OK'
  fi

  set +e
  output=$(ssh \
    -n \
    -p "$SERVER_PORT" \
    -o "ConnectTimeout=${CONNECT_TIMEOUT}" \
    -o "StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING}" \
    -o "UserKnownHostsFile=${HOME}/.ssh/known_hosts" \
    -i "$KEY_PATH" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o PasswordAuthentication=no \
    -o KbdInteractiveAuthentication=no \
    -o PreferredAuthentications=publickey \
    "$SSH_TARGET" "$command" 2>&1)
  rc=$?
  set -e

  [ "$rc" -eq 0 ] && echo "$output" | grep -q "KEY_LOGIN_OK"
}

detect_unix_output() {
  local output
  output="$1"

  if echo "$output" | grep -q "__UNIX__"; then
    REMOTE_SYSTEM="unix"
    if echo "$output" | grep -q "__DROPBEAR__"; then
      echo "Тип системы: Unix/Linux + Dropbear/OpenWrt."
    else
      echo "Тип системы: Unix/Linux/OpenSSH."
    fi
    return 0
  fi

  return 1
}

detect_routeros_output() {
  local output
  output="$1"

  if echo "$output" | grep -q "__ROUTEROS__"; then
    REMOTE_SYSTEM="routeros"
    echo "Тип системы: MikroTik RouterOS."
    return 0
  fi

  return 1
}

detect_remote_system_with_key() {
  local output
  local rc

  set +e
  output=$(ssh \
    -n \
    -p "$SERVER_PORT" \
    -o "ConnectTimeout=${CONNECT_TIMEOUT}" \
    -o "StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING}" \
    -o "UserKnownHostsFile=${HOME}/.ssh/known_hosts" \
    -i "$KEY_PATH" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o PasswordAuthentication=no \
    -o KbdInteractiveAuthentication=no \
    -o PreferredAuthentications=publickey \
    "$SSH_TARGET" 'printf "__UNIX__ "; uname -s 2>/dev/null; [ -d /etc/dropbear ] && printf " __DROPBEAR__"; true' 2>&1)
  rc=$?
  set -e

  if [ "$rc" -eq 0 ] && detect_unix_output "$output"; then
    return 0
  fi

  set +e
  output=$(ssh \
    -n \
    -p "$SERVER_PORT" \
    -o "ConnectTimeout=${CONNECT_TIMEOUT}" \
    -o "StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING}" \
    -o "UserKnownHostsFile=${HOME}/.ssh/known_hosts" \
    -i "$KEY_PATH" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o PasswordAuthentication=no \
    -o KbdInteractiveAuthentication=no \
    -o PreferredAuthentications=publickey \
    "$SSH_TARGET" ':put ("__ROUTEROS__" . [/system resource get version])' 2>&1)
  rc=$?
  set -e

  if [ "$rc" -eq 0 ] && detect_routeros_output "$output"; then
    return 0
  fi

  return 1
}

detect_remote_system_with_password() {
  local output
  local rc

  REMOTE_DETECT_LAST_OUTPUT=""

  set +e
  password_ssh_capture output \
    -p "$SERVER_PORT" \
    -o "ConnectTimeout=${CONNECT_TIMEOUT}" \
    -o "StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING}" \
    -o "UserKnownHostsFile=${HOME}/.ssh/known_hosts" \
    -o PubkeyAuthentication=no \
    -o PreferredAuthentications=password,keyboard-interactive \
    -o NumberOfPasswordPrompts=1 \
    "$SSH_TARGET" 'printf "__UNIX__ "; uname -s 2>/dev/null; [ -d /etc/dropbear ] && printf " __DROPBEAR__"; true'
  rc=$?
  set -e
  REMOTE_DETECT_LAST_OUTPUT="$output"

  if [ "$rc" -eq 0 ] && detect_unix_output "$output"; then
    return 0
  fi

  if printf '%s\n' "$output" | grep -Eqi "Connection closed|Permission denied|Too many authentication failures"; then
    return 1
  fi

  if should_try_port_122 "$output"; then
    return 1
  fi

  set +e
  password_ssh_capture output \
    -p "$SERVER_PORT" \
    -o "ConnectTimeout=${CONNECT_TIMEOUT}" \
    -o "StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING}" \
    -o "UserKnownHostsFile=${HOME}/.ssh/known_hosts" \
    -o PubkeyAuthentication=no \
    -o PreferredAuthentications=password,keyboard-interactive \
    -o NumberOfPasswordPrompts=1 \
    "$SSH_TARGET" ':put ("__ROUTEROS__" . [/system resource get version])'
  rc=$?
  set -e
  REMOTE_DETECT_LAST_OUTPUT="${REMOTE_DETECT_LAST_OUTPUT}
$output"

  if [ "$rc" -eq 0 ] && detect_routeros_output "$output"; then
    return 0
  fi

  return 1
}

detect_remote_system() {
  local choice

  case "$REMOTE_SYSTEM" in
    auto|"") ;;
    mikrotik|routeros|ros)
      REMOTE_SYSTEM="routeros"
      return 0
      ;;
    unix|linux|openssh|dropbear)
      REMOTE_SYSTEM="unix"
      return 0
      ;;
    *)
      echo "Ошибка: неизвестный REMOTE_SYSTEM=$REMOTE_SYSTEM"
      exit 1
      ;;
  esac

  echo "Определяю тип удалённой системы..."

  # Сначала входим паролем и проверяем ОС внутри системы. Это одновременно
  # даёт быструю и понятную диагностику неверного порта.
  if detect_remote_system_with_password; then
    return 0
  fi

  if should_try_port_122 "$REMOTE_DETECT_LAST_OUTPUT" || \
     printf '%s\n' "$REMOTE_DETECT_LAST_OUTPUT" | grep -Eqi "Connection closed|Connection reset|kex_exchange_identification|invalid format|banner line"; then
    return 2
  fi

  if printf '%s\n' "$REMOTE_DETECT_LAST_OUTPUT" | grep -Eqi "Permission denied|Authentication failed"; then
    if detect_remote_system_with_key; then
      return 0
    fi
    return 3
  fi

  # Если парольный вход запрещён, но текущий ключ уже работает, ОС всё ещё
  # можно надёжно определить командой внутри удалённой системы.
  if detect_remote_system_with_key; then
    return 0
  fi

  echo
  echo "Не удалось автоматически определить тип удалённой системы."
  echo "1) unix     - Debian/Ubuntu/CentOS/FreeBSD/OpenWrt/Dropbear и похожие"
  echo "2) mikrotik - MikroTik RouterOS"

  while true; do
    if ! read -r -p "Введите тип [unix/mikrotik]: " choice; then
      echo
      echo "Нет интерактивного ввода для выбора типа системы."
      return 1
    fi
    case "$choice" in
      1|unix|linux|openssh|dropbear)
        REMOTE_SYSTEM="unix"
        return 0
        ;;
      2|mikrotik|routeros|ros)
        REMOTE_SYSTEM="routeros"
        return 0
        ;;
      *)
        echo "Введите unix или mikrotik."
        ;;
    esac
  done
}

install_unix_key_with_password() {
  local key_q
  local remote_script

  key_q="$(shell_quote "$(public_key_line)")"
  remote_script='set -eu
KEY_LINE='"$key_q"'

append_key() {
  dest="$1"
  dir_mode="${2:-}"
  dir=$(dirname "$dest")

  mkdir -p "$dir" 2>/dev/null || return 1
  touch "$dest" 2>/dev/null || return 1

  [ -z "$dir_mode" ] || chmod "$dir_mode" "$dir" 2>/dev/null || true
  chmod 600 "$dest" 2>/dev/null || true

  KEY_DATA=$(printf "%s\n" "$KEY_LINE" | awk "{print \$2}")
  if awk -v data="$KEY_DATA" '\''{ for (i=1; i<=NF; i++) if ($i==data) found=1 } END { exit !found }'\'' "$dest" 2>/dev/null; then
    echo "already:$dest"
  else
    printf "%s\n" "$KEY_LINE" >> "$dest"
    echo "added:$dest"
  fi
}

USER_NAME=$(id -un 2>/dev/null || printf "%s" "${USER:-root}")
HOME_DIR="${HOME:-}"

if [ -z "$HOME_DIR" ] || [ ! -d "$HOME_DIR" ]; then
  HOME_DIR=$(awk -F: -v u="$USER_NAME" "\$1==u {print \$6; exit}" /etc/passwd 2>/dev/null || true)
fi

if [ -z "$HOME_DIR" ] && [ "$(id -u 2>/dev/null || echo 1)" = "0" ]; then
  HOME_DIR=/root
fi

if [ -z "$HOME_DIR" ]; then
  HOME_DIR=.
fi

installed=0

if append_key "$HOME_DIR/.ssh/authorized_keys" 700; then
  installed=1
fi

if [ -f "$HOME_DIR/.ssh/authorized_keys2" ]; then
  append_key "$HOME_DIR/.ssh/authorized_keys2" 700 && installed=1 || true
fi

if [ -d /etc/dropbear ]; then
  append_key "/etc/dropbear/authorized_keys" && installed=1 || true
fi

if [ -d /etc/ssh/authorized_keys ]; then
  append_key "/etc/ssh/authorized_keys/$USER_NAME" && installed=1 || true
fi

if [ -d /etc/ssh/authorized_keys.d ]; then
  append_key "/etc/ssh/authorized_keys.d/$USER_NAME" && installed=1 || true
fi

if [ "$installed" -ne 1 ]; then
  echo "Не нашёл доступного места для authorized_keys."
  exit 1
fi'

  password_ssh \
    -p "$SERVER_PORT" \
    -o "ConnectTimeout=${CONNECT_TIMEOUT}" \
    -o "StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING}" \
    -o "UserKnownHostsFile=${HOME}/.ssh/known_hosts" \
    -o PubkeyAuthentication=no \
    -o PreferredAuthentications=password,keyboard-interactive \
    -o NumberOfPasswordPrompts=1 \
    "$SSH_TARGET" "$remote_script"
}

install_unix_key_with_key_file() {
  local key_file="$1"
  local key_q
  local remote_script

  key_q="$(shell_quote "$(public_key_line)")"
  remote_script='set -eu
KEY_LINE='"$key_q"'

append_key() {
  dest="$1"
  dir_mode="${2:-}"
  dir=$(dirname "$dest")

  mkdir -p "$dir" 2>/dev/null || return 1
  touch "$dest" 2>/dev/null || return 1

  [ -z "$dir_mode" ] || chmod "$dir_mode" "$dir" 2>/dev/null || true
  chmod 600 "$dest" 2>/dev/null || true

  KEY_DATA=$(printf "%s\n" "$KEY_LINE" | awk "{print \$2}")
  if awk -v data="$KEY_DATA" '\''{ for (i=1; i<=NF; i++) if ($i==data) found=1 } END { exit !found }'\'' "$dest" 2>/dev/null; then
    echo "already:$dest"
  else
    printf "%s\n" "$KEY_LINE" >> "$dest"
    echo "added:$dest"
  fi
}

USER_NAME=$(id -un 2>/dev/null || printf "%s" "${USER:-root}")
HOME_DIR="${HOME:-}"

if [ -z "$HOME_DIR" ] || [ ! -d "$HOME_DIR" ]; then
  HOME_DIR=$(awk -F: -v u="$USER_NAME" "\$1==u {print \$6; exit}" /etc/passwd 2>/dev/null || true)
fi

if [ -z "$HOME_DIR" ] && [ "$(id -u 2>/dev/null || echo 1)" = "0" ]; then
  HOME_DIR=/root
fi

if [ -z "$HOME_DIR" ]; then
  HOME_DIR=.
fi

installed=0

if append_key "$HOME_DIR/.ssh/authorized_keys" 700; then
  installed=1
fi

if [ -f "$HOME_DIR/.ssh/authorized_keys2" ]; then
  append_key "$HOME_DIR/.ssh/authorized_keys2" 700 && installed=1 || true
fi

if [ -d /etc/dropbear ]; then
  append_key "/etc/dropbear/authorized_keys" && installed=1 || true
fi

if [ -d /etc/ssh/authorized_keys ]; then
  append_key "/etc/ssh/authorized_keys/$USER_NAME" && installed=1 || true
fi

if [ -d /etc/ssh/authorized_keys.d ]; then
  append_key "/etc/ssh/authorized_keys.d/$USER_NAME" && installed=1 || true
fi

if [ "$installed" -ne 1 ]; then
  echo "Не нашёл доступного места для authorized_keys."
  exit 1
fi'

  ssh \
    -n \
    -i "$key_file" \
    -p "$SERVER_PORT" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o PasswordAuthentication=no \
    -o KbdInteractiveAuthentication=no \
    -o PreferredAuthentications=publickey \
    -o "ConnectTimeout=${CONNECT_TIMEOUT}" \
    -o "StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING}" \
    -o "UserKnownHostsFile=${HOME}/.ssh/known_hosts" \
    "$SSH_TARGET" "$remote_script"
}

copy_with_ssh_copy_id() {
  if ! command -v ssh-copy-id >/dev/null 2>&1; then
    return 1
  fi

  echo "Пробую запасной способ через ssh-copy-id..."
  password_command ssh-copy-id \
    -i "${KEY_PATH}.pub" \
    -p "$SERVER_PORT" \
    -o "StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING}" \
    -o "UserKnownHostsFile=${HOME}/.ssh/known_hosts" \
    "$SSH_TARGET"
}

routeros_quote() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

routeros_import_command() {
  local file_q
  local user_q

  file_q="$(routeros_quote "$1")"
  user_q="$(routeros_quote "$USERNAME")"
  printf '/user ssh-keys import public-key-file=%s user=%s' "$file_q" "$user_q"
}

routeros_add_key_command() {
  local key_q
  local user_q

  key_q="$(routeros_quote "$(public_key_line)")"
  user_q="$(routeros_quote "$USERNAME")"
  printf '/user ssh-keys add key=%s user=%s' "$key_q" "$user_q"
}

routeros_remove_file_command() {
  local file_q

  file_q="$(routeros_quote "$1")"
  printf '/file remove [find name=%s]' "$file_q"
}

routeros_remove_user_keys_command() {
  local user_q

  user_q="$(routeros_quote "$USERNAME")"
  printf '/user ssh-keys remove [find user=%s]' "$user_q"
}

scp_target_path() {
  local remote_path="$1"
  local host="$SERVER_HOST"

  if [[ "$host" == *:* ]]; then
    host="[$host]"
  fi

  printf '%s@%s:%s' "$USERNAME" "$host" "$remote_path"
}

scp_upload() {
  local src="$1"
  local remote_path="$2"

  if password_command scp -O "${SCP_OPTS[@]}" "$src" "$(scp_target_path "$remote_path")"; then
    return 0
  fi

  echo "Legacy scp не сработал, пробую обычный scp..."
  password_command scp "${SCP_OPTS[@]}" "$src" "$(scp_target_path "$remote_path")"
}

install_routeros_key_once() {
  local remote_file="$1"
  local output
  local rc

  scp_upload "${KEY_PATH}.pub" "$remote_file"

  set +e
  output=$(password_command ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$(routeros_import_command "$remote_file")" 2>&1)
  rc=$?
  set -e

  password_command ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$(routeros_remove_file_command "$remote_file")" >/dev/null 2>&1 || true

  if [ -n "$output" ]; then
    echo "$output"
  fi

  return "$rc"
}

install_routeros_key_direct() {
  local output
  local rc

  set +e
  output=$(password_command ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$(routeros_add_key_command)" 2>&1)
  rc=$?
  set -e

  if [ -n "$output" ]; then
    echo "$output"
  fi

  return "$rc"
}

install_routeros_key_direct_with_password() {
  local output
  local rc

  set +e
  password_ssh_capture output \
    -p "$SERVER_PORT" \
    -o "ConnectTimeout=${CONNECT_TIMEOUT}" \
    -o "StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING}" \
    -o "UserKnownHostsFile=${HOME}/.ssh/known_hosts" \
    -o PubkeyAuthentication=no \
    -o PreferredAuthentications=password,keyboard-interactive \
    -o NumberOfPasswordPrompts=1 \
    "$SSH_TARGET" "$(routeros_add_key_command)"
  rc=$?
  set -e

  if [ -n "$output" ]; then
    echo "$output"
  fi

  return "$rc"
}

install_routeros_key() {
  local local_user
  local remote_file

  echo "Копирую ключ на MikroTik RouterOS..."
  local_user="$(id -un 2>/dev/null || printf '%s' "${USER:-user}")"
  local_user="$(printf '%s' "$local_user" | tr -cd 'A-Za-z0-9_.-')"
  remote_file="add_key_${local_user:-user}.pub"

  if install_routeros_key_direct; then
    return 0
  fi

  if verify_key_login "routeros"; then
    return 0
  fi

  echo "Прямое добавление ключа не прошло, пробую импорт через файл..."

  if install_routeros_key_once "$remote_file"; then
    return 0
  fi

  echo
  echo "MikroTik не импортировал ключ с первого раза."
  echo "Если старый ключ уже записан на роутере, он может мешать повторному импорту."

  if verify_key_login "routeros"; then
    return 0
  fi

  if confirm "Удалить SSH-ключи пользователя '$USERNAME' на MikroTik и импортировать заново? [y/N]: "; then
    password_command ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$(routeros_remove_user_keys_command)"
    install_routeros_key_once "$remote_file"
  else
    return 1
  fi
}

verify_key_login() {
  local system_type="$1"
  local command
  local output
  local rc

  echo "Проверяю вход по ключу..."

  if [ "$system_type" = "routeros" ]; then
    command=':put "KEY_LOGIN_OK"'
  else
    command='printf "%s\n" KEY_LOGIN_OK'
  fi

  set +e
  output=$(ssh \
    -p "$SERVER_PORT" \
    -o "ConnectTimeout=${CONNECT_TIMEOUT}" \
    -o "StrictHostKeyChecking=${STRICT_HOST_KEY_CHECKING}" \
    -o "UserKnownHostsFile=${HOME}/.ssh/known_hosts" \
    -i "$KEY_PATH" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o PasswordAuthentication=no \
    -o KbdInteractiveAuthentication=no \
    -o PreferredAuthentications=publickey \
    "$SSH_TARGET" "$command" 2>&1)
  rc=$?
  set -e

  if [ "$rc" -eq 0 ] && echo "$output" | grep -q "KEY_LOGIN_OK"; then
    echo "Ключ установлен и работает."
    return 0
  fi

  echo
  echo "Не удалось подтвердить вход по ключу."
  echo "$output"
  echo
  return 1
}

install_key_with_password_for_detected_system() {
  case "$REMOTE_SYSTEM" in
    unix)
      echo "Копирую ключ через парольный SSH..."
      install_unix_key_with_password
      ;;
    routeros)
      echo "Копирую ключ на MikroTik RouterOS через парольный SSH..."
      install_routeros_key_direct_with_password
      ;;
    *)
      echo "Ошибка: неизвестный тип системы: $REMOTE_SYSTEM"
      exit 1
      ;;
  esac
}

bulk_requirements() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "Ошибка: для -conf нужен jq."
    exit 1
  fi

  if [ ! -r "$BULK_CONFIG_FILE" ]; then
    echo "Ошибка: JSON-файл не найден или не читается: $BULK_CONFIG_FILE"
    exit 1
  fi

  if ! jq -e '.servers | type == "array"' "$BULK_CONFIG_FILE" >/dev/null; then
    echo "Ошибка: в $BULK_CONFIG_FILE должен быть объект с массивом servers."
    exit 1
  fi

}

json_value() {
  local json="$1"
  local filter="$2"

  printf '%s' "$json" | jq -r "$filter"
}

compact_error() {
  local text="$1"

  if printf '%s\n' "$text" | grep -q "REMOTE HOST IDENTIFICATION HAS CHANGED"; then
    echo "host key изменился, нужно проверить known_hosts"
    return 0
  fi

  if printf '%s\n' "$text" | grep -qi "Permission denied"; then
    echo "доступ запрещён: пароль не подошёл или парольный вход отключён"
    return 0
  fi

  if printf '%s\n' "$text" | grep -qi "Could not resolve hostname"; then
    echo "SSH недоступен: hostname не резолвится"
    return 0
  fi

  if printf '%s\n' "$text" | grep -qi "Connection closed"; then
    echo "соединение закрыто сервером: проверь порт или способ входа"
    return 0
  fi

  if printf '%s\n' "$text" | grep -Eqi "Connection refused|Operation timed out|Connection timed out|No route to host|Network is unreachable"; then
    echo "SSH недоступен: проверь IP/порт"
    return 0
  fi

  if printf '%s\n' "$text" | grep -qi "password:"; then
    echo "парольный вход не прошёл"
    return 0
  fi

  printf '%s\n' "$text" \
    | sed -e '/^[[:space:]]*$/d' \
          -e '/^Warning: Permanently added/d' \
          -e '/^spawn /d' \
          -e '/password:/Id' \
    | head -n 1 \
    | cut -c 1-180
}

should_try_port_122() {
  local text="$1"

  printf '%s\n' "$text" | grep -Eqi "Connection refused|Operation timed out|Connection timed out|No route to host|Network is unreachable|Connection closed|Connection reset|kex_exchange_identification|invalid format|banner line"
}

bulk_record_failed_server() {
  local existing
  local i

  [ -n "$BULK_CURRENT_SERVER_B64" ] || return 0

  if [ "$BULK_FAILED_SERVERS_COUNT" -gt 0 ]; then
    i=0
    while [ "$i" -lt "$BULK_FAILED_SERVERS_COUNT" ]; do
      existing="${BULK_FAILED_SERVERS_B64[$i]}"
      [ "$existing" = "$BULK_CURRENT_SERVER_B64" ] && return 0
      i=$((i + 1))
    done
  fi

  BULK_FAILED_SERVERS_B64[$BULK_FAILED_SERVERS_COUNT]="$BULK_CURRENT_SERVER_B64"
  BULK_FAILED_SERVERS_COUNT=$((BULK_FAILED_SERVERS_COUNT + 1))
}

bulk_fail() {
  local detail="$1"

  [ -n "$detail" ] || detail="ошибка без сообщения"
  echo "FAIL ($detail)"
  BULK_FAILED=$((BULK_FAILED + 1))
  bulk_record_failed_server
}

bulk_skip() {
  local detail="$1"

  echo "SKIP ($detail)"
  BULK_SKIPPED=$((BULK_SKIPPED + 1))
}

bulk_ok() {
  local detail="$1"

  echo "OK ($detail)"
  BULK_OK=$((BULK_OK + 1))
}

bulk_process_server() {
  local index="$1"
  local total="$2"
  local server_json="$3"
  local label
  local domain
  local ip
  local host
  local output
  local rc
  local detail

  label="$(json_value "$server_json" '.name // .tariff_plan // .domain // .ip // "unknown"')"
  domain="$(json_value "$server_json" '.domain // ""')"
  ip="$(json_value "$server_json" '.ip // ""')"
  host="$(json_value "$server_json" '.host // .ip // .domain // empty')"
  SERVER_HOST="$host"
  SERVER_PORT="$(json_value "$server_json" '(.port // 22 | tostring)')"
  USERNAME="$(json_value "$server_json" '.user // .username // "root"')"
  SERVER_PASSWORD="$(json_value "$server_json" '.password // empty')"
  REMOTE_SYSTEM="$(json_value "$server_json" '.remote_system // "unix"')"

  case "$REMOTE_SYSTEM" in
    ""|unix|linux|openssh|dropbear)
      REMOTE_SYSTEM="unix"
      ;;
    mikrotik|routeros|ros)
      printf '[%d/%d] %s (%s:%s) ... ' "$index" "$total" "$label" "${SERVER_HOST:-?}" "${SERVER_PORT:-?}"
      bulk_skip "bulk-режим пока ставит ключи только на Unix/Linux"
      return 0
      ;;
    *)
      printf '[%d/%d] %s (%s:%s) ... ' "$index" "$total" "$label" "${SERVER_HOST:-?}" "${SERVER_PORT:-?}"
      bulk_skip "неизвестный remote_system=$REMOTE_SYSTEM"
      return 0
      ;;
  esac

  printf '[%d/%d] %s' "$index" "$total" "$label"
  if [ -n "$domain" ] && [ "$domain" != "$label" ]; then
    printf ' / %s' "$domain"
  fi
  printf ' (%s:%s) ... ' "${SERVER_HOST:-?}" "${SERVER_PORT:-?}"

  if [ -z "$SERVER_HOST" ]; then
    bulk_fail "нет host/ip/domain"
    return 0
  fi

  if [[ "$SERVER_HOST" =~ [[:space:]] ]]; then
    bulk_fail "адрес содержит пробелы"
    return 0
  fi

  if ! [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; then
    bulk_fail "порт должен быть числом 1..65535"
    return 0
  fi

  if [ -z "$USERNAME" ]; then
    bulk_fail "нет пользователя"
    return 0
  fi

  build_connection_options

  if verify_key_login_quiet "$REMOTE_SYSTEM"; then
    bulk_ok "ключ уже работает"
    return 0
  fi

  if [ -z "$SERVER_PASSWORD" ]; then
    if [ "$SERVER_PORT" = "22" ]; then
      printf 'нет password, пробую 122 по ключу ... '
      SERVER_PORT=122
      build_connection_options
      if verify_key_login_quiet "$REMOTE_SYSTEM"; then
        bulk_ok "ключ уже работает на 122"
        return 0
      fi
    fi

    bulk_fail "нет password, а вход по ключу не работает"
    return 0
  fi

  set +e
  output="$(install_unix_key_with_password 2>&1)"
  rc=$?
  set -e

  if [ "$rc" -ne 0 ] && [ "$SERVER_PORT" = "22" ] && should_try_port_122 "$output"; then
    printf '22 недоступен, пробую 122 ... '
    SERVER_PORT=122
    build_connection_options

    if verify_key_login_quiet "$REMOTE_SYSTEM"; then
      bulk_ok "ключ уже работает на 122"
      return 0
    fi

    set +e
    output="$(install_unix_key_with_password 2>&1)"
    rc=$?
    set -e
  fi

  if [ "$rc" -ne 0 ]; then
    detail="$(compact_error "$output")"
    bulk_fail "${detail:-ssh вернул код $rc}"
    return 0
  fi

  if verify_key_login_quiet "$REMOTE_SYSTEM"; then
    if printf '%s\n' "$output" | grep -q '^added:'; then
      bulk_ok "ключ добавлен"
    elif printf '%s\n' "$output" | grep -q '^already:'; then
      bulk_ok "ключ уже был в authorized_keys"
    else
      bulk_ok "ключ установлен и проверен"
    fi
  else
    detail="$(compact_error "$output")"
    bulk_fail "${detail:-ключ записан, но вход по ключу не подтвердился}"
  fi
}

is_private_key_file() {
  local file="$1"
  local first_line
  local base

  [ -f "$file" ] || return 1
  base="$(basename "$file")"
  case "$base" in
    *.pub|known_hosts*|config|authorized_keys*|environment)
      return 1
      ;;
  esac

  IFS= read -r first_line < "$file" || return 1
  [[ "$first_line" == "-----BEGIN "*PRIVATE\ KEY----- ]]
}

discover_ssh_private_keys() {
  local file

  BULK_KEY_CANDIDATES=()
  BULK_KEY_CANDIDATES_COUNT=0
  while IFS= read -r file; do
    if is_private_key_file "$file"; then
      BULK_KEY_CANDIDATES[$BULK_KEY_CANDIDATES_COUNT]="$file"
      BULK_KEY_CANDIDATES_COUNT=$((BULK_KEY_CANDIDATES_COUNT + 1))
    fi
  done < <(find "${HOME}/.ssh" -maxdepth 1 -type f -print 2>/dev/null | sort)
}

select_bulk_key_file() {
  local i
  local choice

  if [ -n "$BULK_KEY_FILE" ]; then
    if is_private_key_file "$BULK_KEY_FILE"; then
      printf '%s' "$BULK_KEY_FILE"
      return 0
    fi
    echo "BULK_KEY_FILE не похож на приватный SSH-ключ: $BULK_KEY_FILE" >&2
    return 1
  fi

  if [ ! -t 0 ]; then
    echo "Есть FAIL-серверы. Запусти ./add_key.sh -conf в терминале или задай BULK_KEY_FILE=/path/to/key, чтобы попробовать другой ключ." >&2
    return 1
  fi

  discover_ssh_private_keys
  if [ "$BULK_KEY_CANDIDATES_COUNT" -eq 0 ]; then
    echo "В ${HOME}/.ssh не нашёл приватных SSH-ключей." >&2
    return 1
  fi

  echo >&2
  echo "Возможно, password-login/root-login отключён. Можно попробовать существующим ключом зайти на FAIL-серверы и добавить текущий ключ." >&2
  echo "Выбери приватный ключ:" >&2
  i=1
  while [ "$i" -le "$BULK_KEY_CANDIDATES_COUNT" ]; do
    file="${BULK_KEY_CANDIDATES[$((i - 1))]}"
    printf '  %d) %s\n' "$i" "$file" >&2
    i=$((i + 1))
  done

  read -r -p "Номер ключа [Enter — пропустить]: " choice
  [ -n "$choice" ] || return 1
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$BULK_KEY_CANDIDATES_COUNT" ]; then
    echo "Неверный номер ключа: $choice" >&2
    return 1
  fi

  printf '%s' "${BULK_KEY_CANDIDATES[$((choice - 1))]}"
}

bulk_retry_server_with_key() {
  local index="$1"
  local total="$2"
  local server_json="$3"
  local key_file="$4"
  local label
  local domain
  local host
  local output
  local rc
  local detail

  label="$(json_value "$server_json" '.name // .tariff_plan // .domain // .ip // "unknown"')"
  domain="$(json_value "$server_json" '.domain // ""')"
  host="$(json_value "$server_json" '.host // .ip // .domain // empty')"
  SERVER_HOST="$host"
  SERVER_PORT="$(json_value "$server_json" '(.port // 22 | tostring)')"
  USERNAME="$(json_value "$server_json" '.user // .username // "root"')"
  REMOTE_SYSTEM="$(json_value "$server_json" '.remote_system // "unix"')"

  case "$REMOTE_SYSTEM" in
    ""|unix|linux|openssh|dropbear) REMOTE_SYSTEM="unix" ;;
    *)
      printf '[key %d/%d] %s (%s:%s) ... ' "$index" "$total" "$label" "${SERVER_HOST:-?}" "${SERVER_PORT:-?}"
      echo "SKIP (выбранный ключ пока поддержан только для Unix/Linux)"
      BULK_KEY_RETRY_SKIPPED=$((BULK_KEY_RETRY_SKIPPED + 1))
      return 0
      ;;
  esac

  printf '[key %d/%d] %s' "$index" "$total" "$label"
  if [ -n "$domain" ] && [ "$domain" != "$label" ]; then
    printf ' / %s' "$domain"
  fi
  printf ' (%s:%s) ... ' "${SERVER_HOST:-?}" "${SERVER_PORT:-?}"

  if [ -z "$SERVER_HOST" ] || [ -z "$USERNAME" ]; then
    echo "FAIL (нет host или user)"
    BULK_KEY_RETRY_FAILED=$((BULK_KEY_RETRY_FAILED + 1))
    return 0
  fi

  build_connection_options
  if verify_key_login_quiet "$REMOTE_SYSTEM"; then
    echo "OK (текущий ключ уже работает)"
    BULK_KEY_RETRY_OK=$((BULK_KEY_RETRY_OK + 1))
    return 0
  fi

  set +e
  output="$(install_unix_key_with_key_file "$key_file" 2>&1)"
  rc=$?
  set -e

  if [ "$rc" -ne 0 ] && [ "$SERVER_PORT" = "22" ] && should_try_port_122 "$output"; then
    printf '22 недоступен, пробую 122 ... '
    SERVER_PORT=122
    build_connection_options
    set +e
    output="$(install_unix_key_with_key_file "$key_file" 2>&1)"
    rc=$?
    set -e
  fi

  if [ "$rc" -ne 0 ]; then
    detail="$(compact_error "$output")"
    echo "FAIL (${detail:-выбранный ключ не подошёл})"
    BULK_KEY_RETRY_FAILED=$((BULK_KEY_RETRY_FAILED + 1))
    return 0
  fi

  if verify_key_login_quiet "$REMOTE_SYSTEM"; then
    echo "OK (текущий ключ добавлен через выбранный ключ)"
    BULK_KEY_RETRY_OK=$((BULK_KEY_RETRY_OK + 1))
  else
    echo "FAIL (ключ записан, но вход текущим ключом не подтвердился)"
    BULK_KEY_RETRY_FAILED=$((BULK_KEY_RETRY_FAILED + 1))
  fi
}

bulk_offer_key_retry() {
  local key_file
  local total
  local index
  local entry_b64
  local server_json
  local failed_before
  local skipped_before
  local remaining_b64=()
  local remaining_count=0

  [ "$BULK_FAILED_SERVERS_COUNT" -gt 0 ] || return 0

  if ! key_file="$(select_bulk_key_file)"; then
    return 0
  fi

  total="$BULK_FAILED_SERVERS_COUNT"
  BULK_KEY_RETRY_OK=0
  BULK_KEY_RETRY_FAILED=0
  BULK_KEY_RETRY_SKIPPED=0

  echo
  echo "Пробую выбранный ключ: $key_file"
  index=0
  while [ "$index" -lt "$BULK_FAILED_SERVERS_COUNT" ]; do
    entry_b64="${BULK_FAILED_SERVERS_B64[$index]}"
    index=$((index + 1))
    server_json="$(printf '%s' "$entry_b64" | base64 -d)"
    failed_before="$BULK_KEY_RETRY_FAILED"
    skipped_before="$BULK_KEY_RETRY_SKIPPED"
    bulk_retry_server_with_key "$index" "$total" "$server_json" "$key_file"
    if [ "$BULK_KEY_RETRY_FAILED" -gt "$failed_before" ] || [ "$BULK_KEY_RETRY_SKIPPED" -gt "$skipped_before" ]; then
      remaining_b64[$remaining_count]="$entry_b64"
      remaining_count=$((remaining_count + 1))
    fi
  done

  BULK_FAILED_SERVERS_B64=("${remaining_b64[@]}")
  BULK_FAILED_SERVERS_COUNT="$remaining_count"
  BULK_OK=$((BULK_OK + BULK_KEY_RETRY_OK))
  BULK_FAILED=$((BULK_KEY_RETRY_FAILED + BULK_KEY_RETRY_SKIPPED))

  echo
  echo "Итого по выбранному ключу: OK=$BULK_KEY_RETRY_OK FAIL=$BULK_KEY_RETRY_FAILED SKIP=$BULK_KEY_RETRY_SKIPPED TOTAL=$total"
}

main_conf() {
  local total
  local index
  local entry_b64
  local server_json

  bulk_requirements
  EMAIL="${EMAIL:-$(default_email)}"
  prepare_existing_key

  total="$(jq '.servers | length' "$BULK_CONFIG_FILE")"
  BULK_OK=0
  BULK_FAILED=0
  BULK_SKIPPED=0
  BULK_FAILED_SERVERS_B64=()
  BULK_FAILED_SERVERS_COUNT=0

  echo "add_key -conf"
  echo "Файл: $BULK_CONFIG_FILE"
  echo "Ключ: ${KEY_PATH}.pub"
  echo "Серверов: $total"
  echo

  index=0
  while IFS= read -r entry_b64; do
    index=$((index + 1))
    BULK_CURRENT_SERVER_B64="$entry_b64"
    server_json="$(printf '%s' "$entry_b64" | base64 -d)"
    bulk_process_server "$index" "$total" "$server_json"
  done < <(jq -r '.servers[] | @base64' "$BULK_CONFIG_FILE")
  BULK_CURRENT_SERVER_B64=""

  echo
  echo "Первый проход: OK=$BULK_OK FAIL=$BULK_FAILED SKIP=$BULK_SKIPPED TOTAL=$total"

  bulk_offer_key_retry

  echo
  echo "Итого: OK=$BULK_OK FAIL=$BULK_FAILED SKIP=$BULK_SKIPPED TOTAL=$total"

  if [ "$BULK_FAILED" -ne 0 ] && [ "$BULK_STRICT_EXIT" = "1" ]; then
    return 1
  fi

  return 0
}

main() {
  local default_port
  local default_user
  local install_ok
  local detect_rc
  local host_check_rc
  local password_failures=0

  ask_required "SERVER_INPUT" "Сервер (login@domain:port)"
  parse_server_input "$SERVER_INPUT"

  if [ "$PARSED_USERNAME" -eq 0 ]; then
    default_user="${USERNAME:-root}"
    USERNAME=""
    ask_with_default "USERNAME" "SSH-логин" "$default_user"
  fi

  if [ -n "$PARSED_PORT" ]; then
    SERVER_PORT="$PARSED_PORT"
  else
    default_port="${SERVER_PORT:-22}"
    SERVER_PORT=""
    ask_with_default "SERVER_PORT" "SSH-порт" "$default_port"
  fi

  ask_email
  prepare_existing_key
  ask_password

  validate_inputs
  while true; do
    build_host_aliases
    if check_host_key_conflict; then
      host_check_rc=0
    else
      host_check_rc=$?
    fi
    [ "$host_check_rc" -eq 0 ] && break
    if [ "$host_check_rc" -ne 2 ]; then
      exit "$host_check_rc"
    fi
    ask_new_port
  done
  build_connection_options
  while true; do
    if detect_remote_system; then
      detect_rc=0
    else
      detect_rc=$?
    fi
    [ "$detect_rc" -eq 0 ] && break
    if [ "$detect_rc" -eq 3 ]; then
      password_failures=$((password_failures + 1))
      if [ "$password_failures" -ge 3 ]; then
        echo "Парольный вход не удался после трёх попыток."
        exit 1
      fi
      ask_password_again
      continue
    fi
    if [ "$detect_rc" -ne 2 ]; then
      exit "$detect_rc"
    fi

    ask_new_port
    build_host_aliases
    if check_host_key_conflict; then
      host_check_rc=0
    else
      host_check_rc=$?
    fi
    if [ "$host_check_rc" -ne 0 ]; then
      [ "$host_check_rc" -eq 2 ] && continue
      exit "$host_check_rc"
    fi
    build_connection_options
  done

  install_ok=0
  if verify_key_login_quiet "$REMOTE_SYSTEM"; then
    echo "Текущий ключ уже установлен и работает."
    install_ok=1
  fi

  if [ "$install_ok" -ne 1 ] && install_key_with_password_for_detected_system; then
    if verify_key_login "$REMOTE_SYSTEM"; then
      install_ok=1
    fi
  fi

  if [ "$install_ok" -ne 1 ] && verify_key_login_quiet "$REMOTE_SYSTEM"; then
    echo "Ключ уже работает, несмотря на ошибку команды установки."
    install_ok=1
  fi

  if [ "$install_ok" -ne 1 ] && [ "$REMOTE_SYSTEM" = "routeros" ]; then
    echo "Прямое добавление не сработало, пробую импорт ключа через файл..."
    if install_routeros_key; then
      if verify_key_login "$REMOTE_SYSTEM"; then
        install_ok=1
      fi
    fi
  fi

  if [ "$install_ok" -ne 1 ] && [ "$REMOTE_SYSTEM" = "unix" ]; then
    if copy_with_ssh_copy_id; then
      if verify_key_login "$REMOTE_SYSTEM"; then
        install_ok=1
      fi
    fi
  fi

  if [ "$install_ok" -ne 1 ]; then
    echo "Не удалось настроить вход по ключу."
    exit 1
  fi

  echo
  echo "Готово. Можно подключаться:"
  echo "ssh -p ${SERVER_PORT} ${USERNAME}@${SERVER_HOST}"
}

if [ "$UPDATE_MODE" -eq 1 ]; then
  main_update
elif [ "$BULK_MODE" -eq 1 ]; then
  main_conf
else
  main
fi
