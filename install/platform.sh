#!/bin/bash

# Project N.O.M.A.D. — Shared Platform Detection Library
# Source this file from other scripts: SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" && source "${SCRIPT_DIR}/platform.sh"

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                    Platform Detection                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

detect_platform() {
  PLATFORM="$(uname -s)"
  ARCH="$(uname -m)"

  case "$PLATFORM" in
    Linux)
      PLATFORM="linux"
      INSTALL_DIR="/opt/project-nomad"
      COMPOSE_PROFILES="linux"
      ;;
    Darwin)
      PLATFORM="darwin"
      INSTALL_DIR="${HOME}/project-nomad"
      COMPOSE_PROFILES="darwin"
      ;;
    *)
      echo "Unsupported platform: $PLATFORM"
      exit 1
      ;;
  esac

  # Determine GPU type
  GPU_TYPE="none"
  if [[ "$PLATFORM" == "darwin" && "$ARCH" == "arm64" ]]; then
    GPU_TYPE="apple_metal"
  elif [[ "$PLATFORM" == "linux" ]]; then
    if command -v lspci &> /dev/null && lspci 2>/dev/null | grep -i nvidia &> /dev/null; then
      GPU_TYPE="nvidia"
    elif command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
      GPU_TYPE="nvidia"
    elif command -v lspci &> /dev/null && lspci 2>/dev/null | grep -iE "amd|radeon" &> /dev/null; then
      GPU_TYPE="amd"
    fi
  fi

  # Set Ollama URL based on platform
  if [[ "$PLATFORM" == "darwin" ]]; then
    OLLAMA_URL="http://host.docker.internal:11434"
  else
    OLLAMA_URL="http://ollama:11434"
  fi

  export PLATFORM ARCH INSTALL_DIR COMPOSE_PROFILES GPU_TYPE OLLAMA_URL
}

# Auto-detect on source
detect_platform
