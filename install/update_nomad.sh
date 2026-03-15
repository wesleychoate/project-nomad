#!/bin/bash

# Project N.O.M.A.D. Update Script

###################################################################################################################################################################################################

# Script                | Project N.O.M.A.D. Update Script
# Version               | 1.1.0
# Author                | Crosstalk Solutions, LLC
# Website               | https://crosstalksolutions.com

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Color Codes                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

RESET='\033[0m'
YELLOW='\033[1;33m'
WHITE_R='\033[39m' # Same as GRAY_R for terminals with white background.
GRAY_R='\033[39m'
RED='\033[1;31m' # Light Red.
GREEN='\033[1;32m' # Light Green.

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                  Platform Detection                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/platform.sh" 2>/dev/null || {
  PLATFORM="$(uname -s)"
  case "$PLATFORM" in
    Linux)  PLATFORM="linux"; INSTALL_DIR="/opt/project-nomad" ;;
    Darwin) PLATFORM="darwin"; INSTALL_DIR="${HOME}/project-nomad" ;;
  esac
}

NOMAD_DIR="$INSTALL_DIR"

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Functions                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

check_has_sudo() {
  if sudo -n true 2>/dev/null; then
    echo -e "${GREEN}#${RESET} User has sudo permissions.\\n"
  else
    echo "User does not have sudo permissions"
    header_red
    echo -e "${RED}#${RESET} This script requires sudo permissions to run. Please run the script with sudo.\\n"
    echo -e "${RED}#${RESET} For example: sudo bash $(basename "$0")"
    exit 1
  fi
}

check_is_bash() {
  if [[ -z "$BASH_VERSION" ]]; then
    header_red
    echo -e "${RED}#${RESET} This script requires bash to run. Please run the script using bash.\\n"
    echo -e "${RED}#${RESET} For example: bash $(basename "$0")"
    exit 1
  fi
    echo -e "${GREEN}#${RESET} This script is running in bash.\\n"
}

check_platform() {
  echo -e "${GREEN}#${RESET} Detected platform: ${PLATFORM} ($(uname -m))\\n"

  if [[ "$PLATFORM" == "linux" ]]; then
    if [[ ! -f /etc/debian_version ]]; then
      echo -e "${RED}#${RESET} This script is designed to run on Debian-based systems only.\\n"
      echo -e "${RED}#${RESET} Please run this script on a Debian-based system and try again."
      exit 1
    fi
    echo -e "${GREEN}#${RESET} This script is running on a Debian-based system.\\n"
  fi
}

get_update_confirmation(){
  read -p "This script will update Project N.O.M.A.D. and its dependencies on your machine. No data loss is expected, but you should always back up your data before proceeding. Are you sure you want to continue? (y/n): " choice
  case "$choice" in
    y|Y )
      echo -e "${GREEN}#${RESET} User chose to continue with the update."
      ;;
    n|N )
      echo -e "${RED}#${RESET} User chose not to continue with the update."
      exit 0
      ;;
    * )
      echo "Invalid Response"
      echo "User chose not to continue with the update."
      exit 0
      ;;
  esac
}

ensure_docker_installed_and_running() {
  if ! command -v docker &> /dev/null; then
    echo -e "${RED}#${RESET} Docker is not installed. This is unexpected, as Project N.O.M.A.D. requires Docker to run. Did you mean to use the install script instead of the update script?"
    exit 1
  fi

  if [[ "$PLATFORM" == "linux" ]]; then
    if ! systemctl is-active --quiet docker; then
      echo -e "${RED}#${RESET} Docker is not running. Attempting to start Docker..."
      sudo systemctl start docker
      if ! systemctl is-active --quiet docker; then
        echo -e "${RED}#${RESET} Failed to start Docker. Please start Docker and try again."
        exit 1
      fi
    fi
  else
    # macOS — check via docker info
    if ! docker info &> /dev/null; then
      echo -e "${RED}#${RESET} Docker Desktop is not running. Please start Docker Desktop and try again."
      exit 1
    fi
  fi
}

check_docker_compose() {
  # Check if 'docker compose' (v2 plugin) is available
  if ! docker compose version &>/dev/null; then
    echo -e "${RED}#${RESET} Docker Compose v2 is not installed or not available as a Docker plugin."
    echo -e "${YELLOW}#${RESET} This script requires 'docker compose' (v2), not 'docker-compose' (v1)."
    echo -e "${YELLOW}#${RESET} Please read the Docker documentation at https://docs.docker.com/compose/install/ for instructions on how to install Docker Compose v2."
    exit 1
  fi
}

ensure_docker_compose_file_exists() {
  if [ ! -f "${NOMAD_DIR}/compose.yml" ]; then
    echo -e "${RED}#${RESET} compose.yml file not found. Please ensure it exists at ${NOMAD_DIR}/compose.yml."
    exit 1
  fi
}

update_native_ollama_macos() {
  if [[ "$PLATFORM" != "darwin" ]]; then
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Updating native Ollama installation...\\n"
  if command -v brew &> /dev/null; then
    brew upgrade ollama 2>/dev/null || brew upgrade --cask ollama 2>/dev/null || true
    echo -e "${GREEN}#${RESET} Ollama update completed.\\n"
  else
    echo -e "${YELLOW}#${RESET} Homebrew not found. Please update Ollama manually.\\n"
  fi
}

force_recreate() {
  echo -e "${YELLOW}#${RESET} Pulling the latest Docker images..."

  local compose_cmd="docker compose -p project-nomad -f ${NOMAD_DIR}/compose.yml"
  if [[ "$PLATFORM" == "darwin" ]]; then
    compose_cmd="$compose_cmd --profile darwin"
  else
    compose_cmd="$compose_cmd --profile linux"
  fi

  if ! $compose_cmd pull; then
    echo -e "${RED}#${RESET} Failed to pull the latest Docker images. Please check your network connection and the Docker registry status, then try again."
    exit 1
  fi

  echo -e "${YELLOW}#${RESET} Forcing recreation of containers..."
  if ! $compose_cmd up -d --force-recreate; then
    echo -e "${RED}#${RESET} Failed to recreate containers. Please check the Docker logs for more details."
    exit 1
  fi
}

get_local_ip() {
  if [[ "$PLATFORM" == "darwin" ]]; then
    local_ip_address=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "")
  else
    local_ip_address=$(hostname -I | awk '{print $1}')
  fi

  if [[ -z "$local_ip_address" ]]; then
    echo -e "${RED}#${RESET} Unable to determine local IP address. Please check your network configuration."
  fi
}

success_message() {
  echo -e "${GREEN}#${RESET} Project N.O.M.A.D update completed successfully!\\n"
  echo -e "${GREEN}#${RESET} Installation files are located at ${NOMAD_DIR}\\n\\n"
  echo -e "${GREEN}#${RESET} Project N.O.M.A.D's Command Center should automatically start whenever your device reboots. However, if you need to start it manually, you can always do so by running: ${WHITE_R}${NOMAD_DIR}/start_nomad.sh${RESET}\\n"
  echo -e "${GREEN}#${RESET} You can now access the management interface at http://localhost:8080 or http://${local_ip_address}:8080\\n"
  echo -e "${GREEN}#${RESET} Thank you for supporting Project N.O.M.A.D!\\n"
}

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Main Script                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

# Pre-flight checks
check_platform
check_is_bash
if [[ "$PLATFORM" == "linux" ]]; then
  check_has_sudo
fi

# Main update
get_update_confirmation
ensure_docker_installed_and_running
check_docker_compose
ensure_docker_compose_file_exists
update_native_ollama_macos
force_recreate
get_local_ip
success_message
