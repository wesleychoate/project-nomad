#!/bin/bash

# Project N.O.M.A.D. Uninstall Script

###################################################################################################################################################################################################

# Script                | Project N.O.M.A.D. Uninstall Script
# Version               | 1.1.0
# Author                | Crosstalk Solutions, LLC
# Website               | https://crosstalksolutions.com

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

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                  Constants & Variables                                                                                          #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

NOMAD_DIR="$INSTALL_DIR"
MANAGEMENT_COMPOSE_FILE="${NOMAD_DIR}/compose.yml"

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                     Functions                                                                                                   #
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

check_current_directory(){
  if [ "$(pwd)" == "${NOMAD_DIR}" ]; then
    echo "Please run this script from a directory other than ${NOMAD_DIR}."
    exit 1
  fi
}

ensure_management_compose_file_exists(){
  if [ ! -f "${MANAGEMENT_COMPOSE_FILE}" ]; then
    echo "Unable to find the management Docker Compose file at ${MANAGEMENT_COMPOSE_FILE}. There may be a problem with your Project N.O.M.A.D. installation."
    exit 1
  fi
}

get_uninstall_confirmation(){
  read -p "This script will remove ALL Project N.O.M.A.D. files and containers. THIS CANNOT BE UNDONE. Are you sure you want to continue? (y/n): " choice
  case "$choice" in
    y|Y )
      echo -e "User chose to continue with the uninstallation."
      ;;
    n|N )
      echo -e "User chose not to continue with the uninstallation."
      exit 0
      ;;
    * )
      echo "Invalid Response"
      echo "User chose not to continue with the uninstallation."
      exit 0
      ;;
  esac
}

ensure_docker_installed() {
    if ! command -v docker &> /dev/null; then
        echo "Unable to find Docker. There may be a problem with your Docker installation."
        exit 1
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

storage_cleanup() {
  read -p "Do you want to delete the Project N.O.M.A.D. storage directory (${NOMAD_DIR})? This is best if you want to start a completely fresh install. This will PERMANENTLY DELETE all stored Nomad data and can't be undone! (y/N): " delete_dir_choice
  case "$delete_dir_choice" in
      y|Y )
          echo "Removing Project N.O.M.A.D. files..."
          if rm -rf "${NOMAD_DIR}"; then
              echo "Project N.O.M.A.D. files removed."
          else
              echo "Warning: Failed to fully remove ${NOMAD_DIR}. You may need to remove it manually."
          fi
          ;;
      * )
          echo "Skipping removal of ${NOMAD_DIR}."
          ;;
  esac
}

uninstall_macos_extras() {
  if [[ "$PLATFORM" != "darwin" ]]; then
    return 0
  fi

  # Remove launchd disk collector job
  local plist_path="${HOME}/Library/LaunchAgents/com.projectnomad.disk-collector.plist"
  if [[ -f "$plist_path" ]]; then
    echo "Removing disk collector launchd job..."
    launchctl unload "$plist_path" 2>/dev/null || true
    rm -f "$plist_path"
    echo "Disk collector launchd job removed."
  fi

  # Offer to uninstall Ollama
  read -p "Do you want to uninstall Ollama? (y/N): " uninstall_ollama_choice
  case "$uninstall_ollama_choice" in
    y|Y )
      echo "Stopping Ollama..."
      pkill -x "ollama" 2>/dev/null || true
      sleep 2

      if command -v brew &> /dev/null; then
        echo "Uninstalling Ollama via Homebrew..."
        brew uninstall --cask ollama 2>/dev/null || brew uninstall ollama 2>/dev/null || true
        echo "Ollama uninstalled."
      else
        echo "Homebrew not found. Please uninstall Ollama manually."
      fi

      # Clean up Ollama data
      read -p "Do you want to remove Ollama model data (~/.ollama)? (y/N): " remove_ollama_data
      case "$remove_ollama_data" in
        y|Y )
          rm -rf "${HOME}/.ollama"
          echo "Ollama data removed."
          ;;
        * )
          echo "Keeping Ollama data."
          ;;
      esac
      ;;
    * )
      echo "Keeping Ollama installed."
      ;;
  esac

  echo ""
  echo "Note: Docker Desktop was NOT uninstalled. Remove it manually via Applications if desired."
}

uninstall_nomad() {
    echo "Stopping and removing Project N.O.M.A.D. management containers..."
    docker compose -p project-nomad -f "${MANAGEMENT_COMPOSE_FILE}" down
    echo "Allowing some time for management containers to stop..."
    sleep 5


    # Stop and remove all containers where name starts with "nomad_"
    echo "Stopping and removing all Project N.O.M.A.D. app containers..."
    docker ps -a --filter "name=^nomad_" --format "{{.Names}}" | xargs -r docker rm -f
    echo "Allowing some time for app containers to stop..."
    sleep 5

    echo "Containers should be stopped now."

    # Remove the shared Docker network (may still exist if app containers were using it during compose down)
    echo "Removing project-nomad_default network if it exists..."
    docker network rm project-nomad_default 2>/dev/null && echo "Network removed." || echo "Network already removed or not found."

    # Remove the shared update volume
    echo "Removing project-nomad_nomad-update-shared volume if it exists..."
    docker volume rm project-nomad_nomad-update-shared 2>/dev/null && echo "Volume removed." || echo "Volume already removed or not found."

    # macOS-specific cleanup
    uninstall_macos_extras

    # Prompt user for storage cleanup and handle it if so
    storage_cleanup

    echo "Project N.O.M.A.D. has been uninstalled. We hope to see you again soon!"
}

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                       Main                                                                                                      #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

if [[ "$PLATFORM" == "linux" ]]; then
  check_has_sudo
fi
check_current_directory
ensure_management_compose_file_exists
ensure_docker_installed
check_docker_compose
get_uninstall_confirmation
uninstall_nomad
