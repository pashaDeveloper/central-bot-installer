#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
prompt() {
  printf '%s' "$2" >&2
  IFS= read -r "$1" || fail 'Input cancelled.'
}

install_dependencies() {
  source /etc/os-release
  case "$ID" in ubuntu|debian) ;; *) fail 'Supported servers: Ubuntu or Debian.' ;; esac
  command -v systemctl >/dev/null || fail 'A systemd server is required.'
  export DEBIAN_FRONTEND=noninteractive
  printf '%s\n' 'Updating apt and upgrading server packages...'
  apt-get update
  apt-get upgrade -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
  apt-get install -y ca-certificates curl git openssh-client rsync
  if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
    if { dpkg-query -W -f='${Status}\n' docker.io containerd runc podman-docker docker-compose docker-compose-v2 2>/dev/null || true; } | grep -q 'install ok installed'; then
      fail 'Conflicting container packages found. Resolve Docker Engine/Compose package conflicts before rerunning; existing packages were not removed.'
    fi
    install -m 0755 -d /etc/apt/keyrings
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
      "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/central-bot-docker.asc
    chmod 0644 /etc/apt/keyrings/central-bot-docker.asc
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/central-bot-docker.asc] https://download.docker.com/linux/%s %s stable\n' \
      "$(dpkg --print-architecture)" "$ID" "${UBUNTU_CODENAME:-$VERSION_CODENAME}" > /etc/apt/sources.list.d/central-bot-docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
  systemctl enable --now docker
  docker info >/dev/null || fail 'Docker daemon is unavailable.'
  docker compose version >/dev/null || fail 'Docker Compose is unavailable.'
}

prepare_key() {
  local repository=$1 config_dir=${2:-/etc/${bot_name:-central-bot}-installer} key_file pubkey registered
  [[ "$repository" =~ ^git@github\.com:([A-Za-z0-9_-]+/[A-Za-z0-9_.-]+)$ ]] || return 0
  local github_repository=${BASH_REMATCH[1]%.git}
  install -d -m 0700 "$config_dir"
  key_file="$config_dir/deploy_key"
  [[ ! -L "$key_file" ]] || fail 'Deploy key must not be a symbolic link.'
  if [[ ! -e "$key_file" ]]; then
    ssh-keygen -q -t ed25519 -N '' -C 'central-bot-deploy' -f "$key_file"
  fi
  chmod 0600 "$key_file"
  pubkey=$(ssh-keygen -y -P '' -f "$key_file") || fail 'Cannot read the existing unencrypted deploy key.'
  printf '\nAdd this PUBLIC key to https://github.com/%s/settings/keys\n' "$github_repository"
  printf 'Settings > Deploy keys > Add deploy key. Leave Allow write access OFF.\n\n%s\n\n' "$pubkey"
  prompt registered 'Press Enter after adding this public key (or if it is already registered): '
  printf '%s\n' 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' > "$config_dir/known_hosts"
  export GIT_SSH_COMMAND="ssh -F /dev/null -i $key_file -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$config_dir/known_hosts -o HostKeyAlgorithms=ssh-ed25519"
  git ls-remote "$repository" HEAD >/dev/null || fail 'GitHub access failed. Check Deploy keys and outbound SSH port 22, then rerun.'
}

download_source() {
  local repository="git@github.com:pashaDeveloper/${bot_name:-central-bot}.git"
  local branch='main' subdirectory='.' source_dir file
  printf 'Downloading bot from %s (branch: %s)\n' "$repository" "$branch"
  prepare_key "$repository"
  download_dir=$(mktemp -d /tmp/central-bot-download.XXXXXX)
  GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$branch" -- "$repository" "$download_dir/repository"
  source_dir="$download_dir/repository/$subdirectory"
  for file in compose.yml Dockerfile server.mjs configure.sh package.json package-lock.json LICENSE; do
    [[ -f "$source_dir/$file" && ! -L "$source_dir/$file" ]] || fail "Downloaded repository is missing $file. Publish the complete updated Central Bot source and select the correct subdirectory."
  done
  [[ ! -L /opt/${bot_name:-central-bot} ]] || fail '/opt/${bot_name:-central-bot} must not be a symbolic link.'
  install -d -m 0700 /opt/${bot_name:-central-bot}
  rsync -a --exclude='.git' --exclude='.env' --exclude='.env.*' --exclude='node_modules' \
    "$source_dir/" /opt/${bot_name:-central-bot}/
  printf '%s\n' "Source installed in /opt/${bot_name:-central-bot}. Configuring the bot..."
}

require_bot() {
  [[ -f /opt/${bot_name:-central-bot}/compose.yml && -f /opt/${bot_name:-central-bot}/.env && ! -L /opt/${bot_name:-central-bot} ]] || fail 'Install the selected bot first.'
}

install_bot() {
  if [[ -f /opt/${bot_name:-central-bot}/.env ]]; then
    printf 'Bot is already installed. Use the management menu.\n'
    return
  fi
  install_dependencies
  download_source
  bash /opt/${bot_name:-central-bot}/configure.sh
}

edit_bot() {
  require_bot
  printf 'To change settings, answer n when asked to keep existing settings.\n'
  bash /opt/${bot_name:-central-bot}/configure.sh
}

update_bot() {
  require_bot
  local backup
  install -d -m 0700 /etc/${bot_name:-central-bot}-installer/backups
  backup=$(mktemp /etc/${bot_name:-central-bot}-installer/backups/source.XXXXXXXX.tar.gz)
  tar --exclude='./node_modules' --exclude='./.git' -czf "$backup" -C /opt/${bot_name:-central-bot} .
  printf 'Current source and settings backed up to %s\n' "$backup"
  download_source
  if [[ "${bot_name:-central-bot}" == customer-bot ]]; then
    bash /opt/customer-bot/configure.sh
    return
  fi
  cd /opt/${bot_name:-central-bot}
  docker compose --env-file .env -f compose.yml config --quiet
  docker compose --env-file .env -f compose.yml up -d --build --wait --wait-timeout 180
}

remove_bot() {
  require_bot
  local confirmation
  prompt confirmation 'Remove selected bot containers, source and settings? Type REMOVE: '
  [[ "$confirmation" == REMOVE ]] || { printf 'Cancelled.\n'; return; }
  [[ ! -L /opt/${bot_name:-central-bot} && $(readlink -f /opt/${bot_name:-central-bot}) == /opt/${bot_name:-central-bot} ]] || fail 'Unexpected installation path.'
  cd /opt/${bot_name:-central-bot}
  docker compose --env-file .env -f compose.yml down --remove-orphans
  cd /
  rm -rf -- /opt/${bot_name:-central-bot}
  printf 'Selected bot removed. External services, Docker volumes, Deploy Key and backups were kept.\n'
}

run_action() {
  local result
  set +e
  (
    set -Eeuo pipefail
    download_dir=''
    trap 'if [[ "$download_dir" == /tmp/central-bot-download.* && -d "$download_dir" ]]; then rm -rf -- "$download_dir"; fi' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    "$1"
  )
  result=$?
  set -e
  if (( result != 0 )); then printf 'Action failed (exit %s). Review the message above.\n' "$result"; fi
}

manage_bot() {
  local action
  printf '\n%s\n1. Edit settings\n2. Update from GitHub\n3. Remove\nb. Back\n' "$bot_name"
  prompt action 'Select an option: '
  case "$action" in
    1) run_action edit_bot ;;
    2) run_action update_bot ;;
    3) run_action remove_bot ;;
    b|B) return ;;
    *) printf 'Invalid option.\n' ;;
  esac
}

main() {
  [[ $(id -u) == 0 ]] || fail 'Run with sudo bash install.sh (or as root).'
  if [[ ! -t 0 ]]; then exec </dev/tty; fi
  local choice
  while true; do
    printf '\nBot Installer\n1. Install admin bot\n2. Install customer bot\n3. Manage admin bot\n4. Manage customer bot\nq) Exit\n'
    prompt choice 'Select an option: '
    case "$choice" in
      1) bot_name=central-bot; run_action install_bot ;;
      2) bot_name=customer-bot; run_action install_bot ;;
      3) bot_name=central-bot; manage_bot ;;
      4) bot_name=customer-bot; manage_bot ;;
      q|Q) return ;;
      *) printf 'Invalid option.\n' ;;
    esac
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
