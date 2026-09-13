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
  local repository=$1 config_dir=${2:-/etc/central-bot-installer} key_file pubkey registered
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
  local repository='git@github.com:pashaDeveloper/central-bot.git'
  local branch='main' subdirectory='.' source_dir file
  printf 'Downloading Central Bot from %s (branch: %s)\n' "$repository" "$branch"
  prepare_key "$repository"
  download_dir=$(mktemp -d /tmp/central-bot-download.XXXXXX)
  GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$branch" -- "$repository" "$download_dir/repository"
  source_dir="$download_dir/repository/$subdirectory"
  for file in compose.yml Dockerfile server.mjs configure.sh package.json package-lock.json LICENSE; do
    [[ -f "$source_dir/$file" && ! -L "$source_dir/$file" ]] || fail "Downloaded repository is missing $file. Publish the complete updated Central Bot source and select the correct subdirectory."
  done
  [[ ! -L /opt/central-bot ]] || fail '/opt/central-bot must not be a symbolic link.'
  install -d -m 0700 /opt/central-bot
  rsync -a --exclude='.git' --exclude='.env' --exclude='.env.*' --exclude='node_modules' \
    "$source_dir/" /opt/central-bot/
  printf '%s\n' 'Source installed in /opt/central-bot. Configuring the bot...'
}

main() {
  [[ $(id -u) == 0 ]] || fail 'Run with sudo bash install.sh (or as root).'
  if [[ ! -t 0 ]]; then exec </dev/tty; fi
  download_dir=''
  trap 'if [[ "$download_dir" == /tmp/central-bot-download.* && -d "$download_dir" ]]; then rm -rf -- "$download_dir"; fi' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  install_dependencies
  download_source
  bash /opt/central-bot/configure.sh
  if [[ -f /var/run/reboot-required ]]; then
    printf '%s\n' 'System updates require a reboot. Reboot the server when convenient.'
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
