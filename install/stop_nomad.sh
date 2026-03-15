#!/bin/bash

# Project N.O.M.A.D. — Stop Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/platform.sh" 2>/dev/null || {
  PLATFORM="$(uname -s)"
  case "$PLATFORM" in
    Linux)  PLATFORM="linux"; INSTALL_DIR="/opt/project-nomad" ;;
    Darwin) PLATFORM="darwin"; INSTALL_DIR="${HOME}/project-nomad" ;;
  esac
}

echo "Finding running Docker containers for Project N.O.M.A.D..."

containers=$(docker ps --filter "name=^nomad_" --format "{{.Names}}")

if [ -z "$containers" ]; then
    echo "No running containers found for Project N.O.M.A.D."
else
    echo "Found the following running containers:"
    echo "$containers"
    echo ""

    for container in $containers; do
        echo "Gracefully stopping container: $container"
        if docker stop "$container"; then
            echo "✓ Successfully stopped $container"
        else
            echo "✗ Failed to stop $container"
        fi
        echo ""
    done

    echo "Finished initiating graceful shutdown of all Project N.O.M.A.D containers."
fi

# On macOS, also stop native Ollama
if [[ "$PLATFORM" == "darwin" ]]; then
  if pgrep -x "ollama" > /dev/null 2>&1; then
    echo ""
    echo "Stopping native Ollama service..."
    pkill -x "ollama" 2>/dev/null
    echo "✓ Ollama service stopped"
  fi
fi
