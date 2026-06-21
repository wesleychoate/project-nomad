#!/bin/bash

# Project N.O.M.A.D. Installation Script

###################################################################################################################################################################################################

# Script                | Project N.O.M.A.D. Installation Script
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
#                                                                                  Repo Source                                                                                                   #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

# Override these to install auxiliary files (compose file, helper scripts, platform.sh,
# disk collector) from a fork/branch instead of upstream's main — useful for running
# fork-specific changes (e.g. macOS support) that haven't been merged upstream yet:
#   NOMAD_REPO=wesleychoate/project-nomad NOMAD_REF=macos-compat bash install_nomad.sh
NOMAD_REPO="${NOMAD_REPO:-Crosstalk-Solutions/project-nomad}"
NOMAD_REF="${NOMAD_REF:-main}"
RAW_BASE_URL="https://raw.githubusercontent.com/${NOMAD_REPO}/refs/heads/${NOMAD_REF}/install"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fetches an install/ file from the configured repo/branch. Prefers a local sibling copy
# (e.g. when running from a full git clone) over the network — this also makes the
# documented single-file flow work:
#   curl -fsSL .../install_nomad.sh -o install_nomad.sh && bash install_nomad.sh
fetch_install_file() {
  local filename="$1"
  local dest="$2"
  if [[ -f "${SCRIPT_DIR}/${filename}" ]]; then
    cp "${SCRIPT_DIR}/${filename}" "$dest"
  else
    curl -fsSL "${RAW_BASE_URL}/${filename}" -o "$dest"
  fi
}

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                  Platform Detection                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

if [[ ! -f "${SCRIPT_DIR}/platform.sh" ]]; then
  if ! fetch_install_file "platform.sh" "${SCRIPT_DIR}/platform.sh"; then
    echo "Failed to fetch platform.sh from ${RAW_BASE_URL}/platform.sh. Check your network connection, or NOMAD_REPO/NOMAD_REF if set." >&2
    exit 1
  fi
fi
source "${SCRIPT_DIR}/platform.sh"

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                  Constants & Variables                                                                                          #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

WHIPTAIL_TITLE="Project N.O.M.A.D Installation"
NOMAD_DIR="$INSTALL_DIR"
script_option_debug='true'
accepted_terms='false'
local_ip_address=''

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Functions                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

header() {
  if [[ "${script_option_debug}" != 'true' ]]; then clear; clear; fi
  echo -e "${GREEN}#########################################################################${RESET}\\n"
}

header_red() {
  if [[ "${script_option_debug}" != 'true' ]]; then clear; clear; fi
  echo -e "${RED}#########################################################################${RESET}\\n"
}

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
  echo -e "${GREEN}#${RESET} Detected platform: ${PLATFORM} (${ARCH})\\n"
  echo -e "${GREEN}#${RESET} Install directory: ${NOMAD_DIR}\\n"

  if [[ "$PLATFORM" == "darwin" ]]; then
    if [[ "$EUID" -eq 0 ]]; then
      header_red
      echo -e "${RED}#${RESET} This script should not be run with sudo on macOS.\\n"
      echo -e "${RED}#${RESET} Unlike on Linux, no step here requires root, and running as root will\\n"
      echo -e "${RED}#${RESET} leave files in ${NOMAD_DIR} owned by root and break the per-user launchd\\n"
      echo -e "${RED}#${RESET} job for the disk collector. Please re-run as: bash $(basename "$0")"
      exit 1
    fi
    echo -e "${GREEN}#${RESET} macOS detected. Ollama will run natively (not in Docker).\\n"
    if [[ "$GPU_TYPE" == "apple_metal" ]]; then
      echo -e "${GREEN}#${RESET} Apple Silicon detected. Ollama will use Metal/MPS acceleration.\\n"
    fi
  elif [[ "$PLATFORM" == "linux" ]]; then
    if [[ ! -f /etc/debian_version ]]; then
      header_red
      echo -e "${RED}#${RESET} This script is designed to run on Debian-based Linux systems only.\\n"
      echo -e "${RED}#${RESET} Please run this script on a Debian-based system and try again."
      exit 1
    fi
    echo -e "${GREEN}#${RESET} This script is running on a Debian-based system.\\n"
  fi
}

check_is_x86_64() {
  local arch
  arch="$(uname -m)"
  if [[ "${arch}" != "x86_64" && "${arch}" != "amd64" ]]; then
    echo -e "${YELLOW}#${RESET} WARNING: Detected architecture '${arch}'. NOMAD officially supports x86_64 only.\\n"
    echo -e "${YELLOW}#${RESET} ARM64/aarch64 support is tracked in PR #419 and is not yet ready.\\n"
    echo -e "${YELLOW}#${RESET} Continuing on an unsupported architecture will likely fail and may leave\\n"
    echo -e "${YELLOW}#${RESET} partial Docker images and files behind that you'll need to clean up manually.\\n"
    echo -e "${YELLOW}#${RESET} Continuing in 10 seconds... press Ctrl+C now to abort.\\n"
    sleep 10
    return
  fi
  echo -e "${GREEN}#${RESET} Architecture check passed (${arch}).\\n"
}

ensure_dependencies_installed() {
  if [[ "$PLATFORM" == "darwin" ]]; then
    ensure_dependencies_installed_macos
  else
    ensure_dependencies_installed_linux
  fi
}

ensure_dependencies_installed_linux() {
  local missing_deps=()

  if ! command -v curl &> /dev/null; then
    missing_deps+=("curl")
  fi

  # Check for gpg (required for NVIDIA container toolkit keyring)
  if ! command -v gpg &> /dev/null; then
    missing_deps+=("gpg")
  fi

  # Check for whiptail (used for dialogs, though not currently active)
  # if ! command -v whiptail &> /dev/null; then
  #   missing_deps+=("whiptail")
  # fi

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo -e "${YELLOW}#${RESET} Installing required dependencies: ${missing_deps[*]}...\\n"
    sudo apt-get update
    sudo apt-get install -y "${missing_deps[@]}"

    for dep in "${missing_deps[@]}"; do
      if ! command -v "$dep" &> /dev/null; then
        echo -e "${RED}#${RESET} Failed to install $dep. Please install it manually and try again."
        exit 1
      fi
    done
    echo -e "${GREEN}#${RESET} Dependencies installed successfully.\\n"
  else
    echo -e "${GREEN}#${RESET} All required dependencies are already installed.\\n"
  fi
}

ensure_dependencies_installed_macos() {
  # Check for Homebrew
  if ! command -v brew &> /dev/null; then
    header_red
    echo -e "${RED}#${RESET} Homebrew is required but not installed.\\n"
    echo -e "${RED}#${RESET} Install it from https://brew.sh and try again."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Homebrew is installed.\\n"

  local missing_deps=()

  for dep in git curl jq; do
    if ! command -v "$dep" &> /dev/null; then
      missing_deps+=("$dep")
    fi
  done

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo -e "${YELLOW}#${RESET} Installing required dependencies via Homebrew: ${missing_deps[*]}...\\n"
    brew install "${missing_deps[@]}"

    for dep in "${missing_deps[@]}"; do
      if ! command -v "$dep" &> /dev/null; then
        echo -e "${RED}#${RESET} Failed to install $dep. Please install it manually and try again."
        exit 1
      fi
    done
    echo -e "${GREEN}#${RESET} Dependencies installed successfully.\\n"
  else
    echo -e "${GREEN}#${RESET} All required dependencies are already installed.\\n"
  fi
}

check_is_debug_mode(){
  if [[ "${script_option_debug}" == 'true' ]]; then
    echo -e "${YELLOW}#${RESET} Debug mode is enabled, the script will not clear the screen...\\n"
  else
    clear; clear
  fi
}

generateRandomPass() {
  local length="${1:-32}"
  local password
  password=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length")
  echo "$password"
}

ensure_docker_installed() {
  if [[ "$PLATFORM" == "darwin" ]]; then
    ensure_docker_installed_macos
  else
    ensure_docker_installed_linux
  fi
}

ensure_docker_installed_linux() {
  if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}#${RESET} Docker not found. Installing Docker...\\n"

    sudo apt-get update
    sudo apt-get install -y ca-certificates curl

    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh

    if ! command -v docker &> /dev/null; then
      echo -e "${RED}#${RESET} Docker installation failed. Please check the logs and try again."
      exit 1
    fi

    echo -e "${GREEN}#${RESET} Docker installation completed.\\n"
  else
    echo -e "${GREEN}#${RESET} Docker is already installed.\\n"

    if ! systemctl is-active --quiet docker; then
      echo -e "${YELLOW}#${RESET} Docker is installed but not running. Attempting to start Docker...\\n"
      sudo systemctl start docker
      if ! systemctl is-active --quiet docker; then
        echo -e "${RED}#${RESET} Failed to start Docker. Please check the Docker service status and try again."
        exit 1
      else
        echo -e "${GREEN}#${RESET} Docker service started successfully.\\n"
      fi
    else
      echo -e "${GREEN}#${RESET} Docker service is already running.\\n"
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

ensure_docker_installed_macos() {
  if ! command -v docker &> /dev/null; then
    header_red
    echo -e "${RED}#${RESET} Docker Desktop is required but not installed.\\n"
    echo -e "${RED}#${RESET} Please install Docker Desktop from https://www.docker.com/products/docker-desktop/ and try again.\\n"
    echo -e "${RED}#${RESET} Note: Docker Desktop requires a paid license for large organizations (>250 employees or >\$10M annual revenue).\\n"
    exit 1
  fi

  echo -e "${GREEN}#${RESET} Docker is installed.\\n"

  # Check if Docker daemon is running
  if ! docker info &> /dev/null; then
    echo -e "${YELLOW}#${RESET} Docker Desktop is not running. Please start Docker Desktop and try again.\\n"
    exit 1
  fi

  echo -e "${GREEN}#${RESET} Docker Desktop is running.\\n"
}

ensure_ollama_installed_macos() {
  if [[ "$PLATFORM" != "darwin" ]]; then
    return 0
  fi

  if ! command -v ollama &> /dev/null; then
    echo -e "${YELLOW}#${RESET} Installing Ollama via Homebrew...\\n"
    brew install --cask ollama

    if ! command -v ollama &> /dev/null; then
      echo -e "${RED}#${RESET} Ollama installation failed. Please install it manually from https://ollama.com and try again."
      exit 1
    fi
    echo -e "${GREEN}#${RESET} Ollama installed successfully.\\n"
  else
    echo -e "${GREEN}#${RESET} Ollama is already installed.\\n"
  fi
}

setup_nvidia_container_toolkit() {
  # Only run on Linux — macOS uses native Ollama with Metal/MPS
  if [[ "$PLATFORM" == "darwin" ]]; then
    echo -e "${GREEN}#${RESET} macOS detected. Skipping NVIDIA container toolkit (Ollama runs natively with Metal/MPS).\\n"
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Checking for NVIDIA GPU...\\n"

  local has_nvidia_gpu=false
  if command -v lspci &> /dev/null; then
    if lspci 2>/dev/null | grep -i nvidia &> /dev/null; then
      has_nvidia_gpu=true
      echo -e "${GREEN}#${RESET} NVIDIA GPU detected.\\n"
    fi
  fi

  if ! $has_nvidia_gpu && command -v nvidia-smi &> /dev/null; then
    if nvidia-smi &> /dev/null; then
      has_nvidia_gpu=true
      echo -e "${GREEN}#${RESET} NVIDIA GPU detected via nvidia-smi.\\n"
    fi
  fi

  if ! $has_nvidia_gpu; then
    echo -e "${YELLOW}#${RESET} No NVIDIA GPU detected. Skipping NVIDIA container toolkit installation.\\n"
    return 0
  fi

  if command -v nvidia-ctk &> /dev/null; then
    echo -e "${GREEN}#${RESET} NVIDIA container toolkit is already installed.\\n"
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Installing NVIDIA container toolkit...\\n"

  if ! curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey 2>/dev/null | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null; then
    echo -e "${YELLOW}#${RESET} Warning: Failed to add NVIDIA container toolkit GPG key. Continuing anyway...\\n"
    return 0
  fi

  if ! curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list 2>/dev/null \
      | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
      | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null 2>&1; then
    echo -e "${YELLOW}#${RESET} Warning: Failed to add NVIDIA container toolkit repository. Continuing anyway...\\n"
    return 0
  fi

  if ! sudo apt-get update 2>/dev/null; then
    echo -e "${YELLOW}#${RESET} Warning: Failed to update package list. Continuing anyway...\\n"
    return 0
  fi

  if ! sudo apt-get install -y nvidia-container-toolkit 2>/dev/null; then
    echo -e "${YELLOW}#${RESET} Warning: Failed to install NVIDIA container toolkit. Continuing anyway...\\n"
    return 0
  fi

  echo -e "${GREEN}#${RESET} NVIDIA container toolkit installed successfully.\\n"

  echo -e "${YELLOW}#${RESET} Configuring Docker to use NVIDIA runtime...\\n"

  if ! sudo nvidia-ctk runtime configure --runtime=docker 2>/dev/null; then
    echo -e "${YELLOW}#${RESET} nvidia-ctk configure failed, attempting manual configuration...\\n"

    local daemon_json="/etc/docker/daemon.json"
    local config_success=false

    if [[ -f "$daemon_json" ]]; then
      sudo cp "$daemon_json" "${daemon_json}.backup" 2>/dev/null || true

      if ! grep -q '"nvidia"' "$daemon_json" 2>/dev/null; then
        if command -v jq &> /dev/null; then
          if sudo jq '. + {"runtimes": {"nvidia": {"path": "nvidia-container-runtime", "runtimeArgs": []}}}' "$daemon_json" > /tmp/daemon.json.tmp 2>/dev/null; then
            if sudo mv /tmp/daemon.json.tmp "$daemon_json" 2>/dev/null; then
              config_success=true
            fi
          fi
          sudo rm -f /tmp/daemon.json.tmp 2>/dev/null || true
        else
          echo -e "${YELLOW}#${RESET} jq not available, skipping manual daemon.json configuration...\\n"
        fi
      else
        config_success=true
      fi
    else
      if echo '{"runtimes":{"nvidia":{"path":"nvidia-container-runtime","runtimeArgs":[]}}}' | sudo tee "$daemon_json" > /dev/null 2>&1; then
        config_success=true
      fi
    fi

    if ! $config_success; then
      echo -e "${YELLOW}#${RESET} Manual daemon.json configuration unsuccessful. GPU support may require manual setup.\\n"
    fi
  fi

  echo -e "${YELLOW}#${RESET} Restarting Docker service...\\n"
  if ! sudo systemctl restart docker 2>/dev/null; then
    echo -e "${YELLOW}#${RESET} Warning: Failed to restart Docker service. You may need to restart it manually.\\n"
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Verifying NVIDIA runtime configuration...\\n"
  sleep 2

  if docker info 2>/dev/null | grep -q "nvidia"; then
    echo -e "${GREEN}#${RESET} NVIDIA runtime successfully configured and verified.\\n"
  else
    echo -e "${YELLOW}#${RESET} Warning: NVIDIA runtime not detected in Docker info. GPU acceleration may not work.\\n"
    echo -e "${YELLOW}#${RESET} You may need to manually configure /etc/docker/daemon.json and restart Docker.\\n"
  fi

  echo -e "${GREEN}#${RESET} NVIDIA container toolkit configuration completed.\\n"
}

get_install_confirmation(){
  echo -e "${YELLOW}#${RESET} This script will install Project N.O.M.A.D. and its dependencies on your machine."
  echo -e "${YELLOW}#${RESET} If you already have Project N.O.M.A.D. installed with customized config or data, please be aware that running this installation script may overwrite existing files and configurations. It is highly recommended to back up any important data/configs before proceeding."
  read -p "Are you sure you want to continue? (y/N): " choice
  case "$choice" in
    y|Y )
      echo -e "${GREEN}#${RESET} User chose to continue with the installation."
      ;;
    * )
      echo "User chose not to continue with the installation."
      exit 0
      ;;
  esac
}

accept_terms() {
  printf "\n\n"
  echo "License Agreement & Terms of Use"
  echo "__________________________"
  printf "\n\n"
  echo "Project N.O.M.A.D. is licensed under the Apache License 2.0. The full license can be found at https://www.apache.org/licenses/LICENSE-2.0 or in the LICENSE file of this repository."
  printf "\n"
  echo "By accepting this agreement, you acknowledge that you have read and understood the terms and conditions of the Apache License 2.0 and agree to be bound by them while using Project N.O.M.A.D."
  echo -e "\n\n"
  read -p "I have read and accept License Agreement & Terms of Use (y/N)? " choice
  case "$choice" in
    y|Y )
      accepted_terms='true'
      ;;
    * )
      echo "License Agreement & Terms of Use not accepted. Installation cannot continue."
      exit 1
      ;;
  esac
}

create_nomad_directory(){
  if [[ ! -d "$NOMAD_DIR" ]]; then
    echo -e "${YELLOW}#${RESET} Creating directory for Project N.O.M.A.D at $NOMAD_DIR...\\n"
    if [[ "$PLATFORM" == "darwin" ]]; then
      mkdir -p "$NOMAD_DIR"
    else
      sudo mkdir -p "$NOMAD_DIR"
      sudo chown "$(whoami):$(whoami)" "$NOMAD_DIR"
    fi
    echo -e "${GREEN}#${RESET} Directory created successfully.\\n"
  else
    echo -e "${GREEN}#${RESET} Directory $NOMAD_DIR already exists.\\n"
  fi

  if [[ "$PLATFORM" == "darwin" ]]; then
    mkdir -p "${NOMAD_DIR}/storage/logs"
    touch "${NOMAD_DIR}/storage/logs/admin.log"
  else
    sudo mkdir -p "${NOMAD_DIR}/storage/logs"
    sudo touch "${NOMAD_DIR}/storage/logs/admin.log"
  fi
}

download_management_compose_file() {
  local compose_file_path="${NOMAD_DIR}/compose.yml"

  echo -e "${YELLOW}#${RESET} Downloading docker-compose file for management...\\n"
  if ! fetch_install_file "management_compose.yaml" "$compose_file_path"; then
    echo -e "${RED}#${RESET} Failed to download the docker compose file. Please check the URL and try again."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Docker compose file downloaded successfully to $compose_file_path.\\n"

  local app_key=$(generateRandomPass)
  local db_root_password=$(generateRandomPass)
  local db_user_password=$(generateRandomPass)

  # If MySQL data directory exists from a previous install attempt, remove it.
  # MySQL only initializes credentials on first startup when the data dir is empty.
  # If stale data exists, MySQL ignores the new passwords above and uses the old ones,
  # causing "Access denied" errors when the admin container tries to connect.
  if [[ -d "${NOMAD_DIR}/mysql" ]]; then
    echo -e "${YELLOW}#${RESET} Removing existing MySQL data directory to ensure credentials match...\\n"
    if [[ "$PLATFORM" == "darwin" ]]; then
      rm -rf "${NOMAD_DIR}/mysql"
    else
      sudo rm -rf "${NOMAD_DIR}/mysql"
    fi
  fi

  # Inject dynamic env values into the compose file
  echo -e "${YELLOW}#${RESET} Configuring docker-compose file env variables...\\n"

  # Use sed compatible with both macOS and Linux
  if [[ "$PLATFORM" == "darwin" ]]; then
    sed -i '' "s|URL=replaceme|URL=http://${local_ip_address}:8080|g" "$compose_file_path"
    sed -i '' "s|APP_KEY=replaceme|APP_KEY=${app_key}|g" "$compose_file_path"
    sed -i '' "s|DB_PASSWORD=replaceme|DB_PASSWORD=${db_user_password}|g" "$compose_file_path"
    sed -i '' "s|MYSQL_ROOT_PASSWORD=replaceme|MYSQL_ROOT_PASSWORD=${db_root_password}|g" "$compose_file_path"
    sed -i '' "s|MYSQL_PASSWORD=replaceme|MYSQL_PASSWORD=${db_user_password}|g" "$compose_file_path"
  else
    sed -i "s|URL=replaceme|URL=http://${local_ip_address}:8080|g" "$compose_file_path"
    sed -i "s|APP_KEY=replaceme|APP_KEY=${app_key}|g" "$compose_file_path"
    sed -i "s|DB_PASSWORD=replaceme|DB_PASSWORD=${db_user_password}|g" "$compose_file_path"
    sed -i "s|MYSQL_ROOT_PASSWORD=replaceme|MYSQL_ROOT_PASSWORD=${db_root_password}|g" "$compose_file_path"
    sed -i "s|MYSQL_PASSWORD=replaceme|MYSQL_PASSWORD=${db_user_password}|g" "$compose_file_path"
  fi

  # Write .env file with platform-specific values
  cat > "${NOMAD_DIR}/.env" <<ENVEOF
NOMAD_PLATFORM=${PLATFORM}
NOMAD_HOME=${NOMAD_DIR}
OLLAMA_URL=${OLLAMA_URL}
GPU_TYPE=${GPU_TYPE}
ENVEOF

  echo -e "${GREEN}#${RESET} Docker compose file configured successfully.\\n"
}

download_helper_scripts() {
  local start_script_path="${NOMAD_DIR}/start_nomad.sh"
  local stop_script_path="${NOMAD_DIR}/stop_nomad.sh"
  local update_script_path="${NOMAD_DIR}/update_nomad.sh"

  echo -e "${YELLOW}#${RESET} Downloading helper scripts...\\n"
  if ! fetch_install_file "start_nomad.sh" "$start_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the start script. Please check the URL and try again."
    exit 1
  fi
  chmod +x "$start_script_path"

  if ! fetch_install_file "stop_nomad.sh" "$stop_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the stop script. Please check the URL and try again."
    exit 1
  fi
  chmod +x "$stop_script_path"

  if ! fetch_install_file "update_nomad.sh" "$update_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the update script. Please check the URL and try again."
    exit 1
  fi
  chmod +x "$update_script_path"

  echo -e "${GREEN}#${RESET} Helper scripts downloaded successfully to $start_script_path, $stop_script_path, and $update_script_path.\\n"
}

start_management_containers() {
  echo -e "${YELLOW}#${RESET} Starting management containers using docker compose...\\n"

  local compose_cmd="docker compose -p project-nomad -f ${NOMAD_DIR}/compose.yml"

  if [[ "$PLATFORM" == "darwin" ]]; then
    compose_cmd="$compose_cmd --profile darwin"
  else
    compose_cmd="$compose_cmd --profile linux"
    compose_cmd="sudo $compose_cmd"
  fi

  if ! $compose_cmd up -d; then
    echo -e "${RED}#${RESET} Failed to start management containers. Please check the logs and try again."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Management containers started successfully.\\n"
}

get_local_ip() {
  if [[ "$PLATFORM" == "darwin" ]]; then
    local_ip_address=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "")
  else
    local_ip_address=$(hostname -I | awk '{print $1}')
  fi

  if [[ -z "$local_ip_address" ]]; then
    echo -e "${RED}#${RESET} Unable to determine local IP address. Please check your network configuration."
    exit 1
  fi
}

verify_gpu_setup() {
  echo -e "\\n${YELLOW}#${RESET} GPU Setup Verification\\n"
  echo -e "${YELLOW}===========================================${RESET}\\n"

  if [[ "$PLATFORM" == "darwin" ]]; then
    if [[ "$GPU_TYPE" == "apple_metal" ]]; then
      echo -e "${GREEN}✓${RESET} Apple Silicon detected (${ARCH})"
      echo -e "${GREEN}✓${RESET} Ollama will use Metal/MPS acceleration natively\\n"
      echo -e "${GREEN}#${RESET} GPU acceleration is properly configured! The AI Assistant will use your Apple Silicon GPU.\\n"
    else
      echo -e "${YELLOW}○${RESET} Intel Mac detected. Ollama will run in CPU-only mode.\\n"
    fi
    echo -e "${YELLOW}===========================================${RESET}\\n"
    return
  fi

  # Linux GPU verification
  if command -v nvidia-smi &> /dev/null; then
    echo -e "${GREEN}✓${RESET} NVIDIA GPU detected:"
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | while read -r line; do
      echo -e "  ${WHITE_R}$line${RESET}"
    done
    echo ""
  else
    echo -e "${YELLOW}○${RESET} No NVIDIA GPU detected (nvidia-smi not available)\\n"
  fi

  if command -v nvidia-ctk &> /dev/null; then
    echo -e "${GREEN}✓${RESET} NVIDIA Container Toolkit installed: $(nvidia-ctk --version 2>/dev/null | head -n1)\\n"
  else
    echo -e "${YELLOW}○${RESET} NVIDIA Container Toolkit not installed\\n"
  fi
  # Check if Docker has NVIDIA runtime
  if docker info 2>/dev/null | grep -q "nvidia"; then
    echo -e "${GREEN}✓${RESET} Docker NVIDIA runtime configured\\n"
  else
    echo -e "${YELLOW}○${RESET} Docker NVIDIA runtime not detected\\n"
  fi
  # Check for AMD GPU — restrict to display controller classes to avoid false positives
  # from AMD CPU host bridges, PCI bridges, and chipset devices.
  local has_amd_gpu='false'
  local amd_gfx_version=''
  if command -v lspci &> /dev/null; then
    if lspci 2>/dev/null | grep -iE "VGA|3D controller|Display" | grep -iE "amd|radeon" &> /dev/null; then
      has_amd_gpu='true'
      echo -e "${GREEN}✓${RESET} AMD GPU detected — ROCm acceleration will be configured automatically when AI Assistant is installed.\\n"

      # Map AMD codename → gfx version so the admin can pick the right HSA_OVERRIDE_GFX_VERSION.
      # gfx1030/1100/1101/1102 are on AMD's official ROCm allowlist and need NO override —
      # forcing one (e.g. 11.0.0) breaks GPU discovery on these. Other variants do need it.
      local amd_devices
      amd_devices=$(lspci -vmm 2>/dev/null | awk -F'\t' '/^Class:.*(VGA|3D|Display)/{c=1} c && /^Device:/{print $2; c=0}')
      if echo "${amd_devices}" | grep -iq 'Navi 21'; then
        amd_gfx_version='gfx1030'
      elif echo "${amd_devices}" | grep -iq 'Navi 22'; then
        amd_gfx_version='gfx1031'
      elif echo "${amd_devices}" | grep -iq 'Navi 23'; then
        amd_gfx_version='gfx1032'
      elif echo "${amd_devices}" | grep -iq 'Navi 24'; then
        amd_gfx_version='gfx1034'
      elif echo "${amd_devices}" | grep -iq 'Rembrandt'; then
        amd_gfx_version='gfx1035'
      elif echo "${amd_devices}" | grep -iEq 'Phoenix1?|Phoenix2'; then
        amd_gfx_version='gfx1103'
      elif echo "${amd_devices}" | grep -iEq 'Strix Halo'; then
        amd_gfx_version='gfx1151'
      elif echo "${amd_devices}" | grep -iEq 'Strix( Point)?'; then
        amd_gfx_version='gfx1150'
      elif echo "${amd_devices}" | grep -iq 'Navi 31'; then
        amd_gfx_version='gfx1100'
      elif echo "${amd_devices}" | grep -iq 'Navi 32'; then
        amd_gfx_version='gfx1101'
      elif echo "${amd_devices}" | grep -iq 'Navi 33'; then
        amd_gfx_version='gfx1102'
      fi
    fi
  fi

  # Write detected GPU type to a marker file the admin container can read. The admin
  # container lacks lspci and AMD GPUs don't register a Docker runtime, so this is the
  # only reliable way for the admin to know an AMD GPU is present at install time.
  local gpu_marker_path="${NOMAD_DIR}/storage/.nomad-gpu-type"
  if command -v nvidia-smi &> /dev/null; then
    echo 'nvidia' | sudo tee "${gpu_marker_path}" > /dev/null 2>&1 || true
  elif [[ "${has_amd_gpu}" == 'true' ]]; then
    echo 'amd' | sudo tee "${gpu_marker_path}" > /dev/null 2>&1 || true
  else
    sudo rm -f "${gpu_marker_path}" 2>/dev/null || true
  fi

  # Companion marker used by the admin to pick the right HSA_OVERRIDE_GFX_VERSION for
  # the detected card. Absence of this file means "unknown gfx" — the admin falls back
  # to its built-in default. Always rewrite (or remove) on install to keep state fresh.
  local amd_gfx_marker_path="${NOMAD_DIR}/storage/.nomad-amd-gfx"
  if [[ -n "${amd_gfx_version}" ]]; then
    echo "${amd_gfx_version}" | sudo tee "${amd_gfx_marker_path}" > /dev/null 2>&1 || true
  else
    sudo rm -f "${amd_gfx_marker_path}" 2>/dev/null || true
  fi

  echo -e "${YELLOW}===========================================${RESET}\\n"

  # Summary
  if command -v nvidia-smi &> /dev/null && docker info 2>/dev/null | grep -q "nvidia"; then
    echo -e "${GREEN}#${RESET} GPU acceleration is properly configured! The AI Assistant will use your GPU.\\n"
  elif [[ "${has_amd_gpu}" == 'true' ]]; then
    echo -e "${GREEN}#${RESET} GPU acceleration will be enabled (AMD/ROCm) when AI Assistant is installed from the dashboard.\\n"
  else
    echo -e "${YELLOW}#${RESET} GPU acceleration not detected. The AI Assistant will run in CPU-only mode.\\n"
    if command -v nvidia-smi &> /dev/null && ! docker info 2>/dev/null | grep -q "nvidia"; then
      echo -e "${YELLOW}#${RESET} Tip: Your GPU is detected but Docker runtime is not configured.\\n"
      echo -e "${YELLOW}#${RESET} Try restarting Docker: ${WHITE_R}sudo systemctl restart docker${RESET}\\n"
    fi
  fi
}

setup_macos_disk_collector() {
  if [[ "$PLATFORM" != "darwin" ]]; then
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Setting up disk info collector for macOS...\\n"

  # Fetched via NOMAD_REPO/NOMAD_REF (or a local sibling copy) — must NOT be hardcoded to
  # upstream's main branch. Upstream's collect_disk_info.sh is Linux-only (lsblk, hardcoded
  # /tmp output) and has no macOS-aware collect_darwin() path, which silently breaks
  # disk-space reporting if it ever gets pulled instead of this fork's version.
  local collector_script="${NOMAD_DIR}/collect_disk_info.sh"

  if ! fetch_install_file "collect_disk_info.sh" "$collector_script"; then
    echo -e "${YELLOW}#${RESET} Warning: Failed to fetch disk collector script. Disk info may not be available.\\n"
    return 0
  fi
  chmod +x "$collector_script"

  # Create a launchd plist to run the disk collector periodically
  local plist_path="${HOME}/Library/LaunchAgents/com.projectnomad.disk-collector.plist"
  mkdir -p "${HOME}/Library/LaunchAgents"

  cat > "$plist_path" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.projectnomad.disk-collector</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${collector_script}</string>
    </array>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${NOMAD_DIR}/storage/logs/disk-collector.log</string>
    <key>StandardErrorPath</key>
    <string>${NOMAD_DIR}/storage/logs/disk-collector-error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>NOMAD_HOME</key>
        <string>${NOMAD_DIR}</string>
    </dict>
</dict>
</plist>
PLISTEOF

  # Load the launchd job
  launchctl unload "$plist_path" 2>/dev/null || true
  launchctl load "$plist_path"

  echo -e "${GREEN}#${RESET} Disk info collector configured via launchd.\\n"
}

success_message() {
  echo -e "${GREEN}#${RESET} Project N.O.M.A.D installation completed successfully!\\n"
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
if [[ "$PLATFORM" == "linux" ]]; then
  check_is_x86_64
fi
check_is_bash
if [[ "$PLATFORM" == "linux" ]]; then
  check_has_sudo
fi
ensure_dependencies_installed
check_is_debug_mode

# Main install
get_install_confirmation
accept_terms
ensure_docker_installed
check_docker_compose
if [[ "$PLATFORM" == "darwin" ]]; then
  ensure_ollama_installed_macos
fi
setup_nvidia_container_toolkit
get_local_ip
create_nomad_directory
download_helper_scripts
download_management_compose_file
start_management_containers
if [[ "$PLATFORM" == "darwin" ]]; then
  setup_macos_disk_collector
fi
verify_gpu_setup
success_message
