#!/bin/bash

# Project N.O.M.A.D. — Start Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/platform.sh" 2>/dev/null || {
  # Fallback if platform.sh isn't alongside this script (e.g., script was copied to NOMAD_DIR)
  PLATFORM="$(uname -s)"
  case "$PLATFORM" in
    Linux)  PLATFORM="linux"; INSTALL_DIR="/opt/project-nomad" ;;
    Darwin) PLATFORM="darwin"; INSTALL_DIR="${HOME}/project-nomad" ;;
  esac
}

NOMAD_DIR="${INSTALL_DIR}"

# On macOS, start native Ollama before Docker containers
if [[ "$PLATFORM" == "darwin" ]]; then
  if command -v ollama &> /dev/null; then
    echo "Starting Ollama service..."
    # Start Ollama in the background if not already running
    if ! pgrep -x "ollama" > /dev/null 2>&1; then
      ollama serve &>/dev/null &
      sleep 2
      echo "✓ Ollama service started"
    else
      echo "✓ Ollama is already running"
    fi
  else
    echo "Warning: Ollama is not installed. AI Assistant features will not be available."
  fi
fi

echo "Finding Project N.O.M.A.D containers..."

# -a to include all containers (running and stopped)
containers=$(docker ps -a --filter "name=^nomad_" --format "{{.Names}}")

if [ -z "$containers" ]; then
    echo "No containers found for Project N.O.M.A.D. Is it installed?"
    exit 0
fi

echo "Found the following containers:"
echo "$containers"
echo ""

for container in $containers; do
    echo "Starting container: $container"
    if docker start "$container"; then
        echo "✓ Successfully started $container"
    else
        echo "✗ Failed to start $container"
    fi
    echo ""
done

echo "Finished initiating start of all Project N.O.M.A.D containers."
