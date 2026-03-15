#!/bin/bash

# Project N.O.M.A.D. — Disk Info Collector
# Collects disk layout and filesystem usage, outputting a consistent JSON schema
# on both Linux and macOS.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source platform detection if available (won't exist inside the sidecar container)
if [[ -f "${SCRIPT_DIR}/platform.sh" ]]; then
  source "${SCRIPT_DIR}/platform.sh"
else
  PLATFORM="$(uname -s)"
  case "$PLATFORM" in
    Linux)  PLATFORM="linux" ;;
    Darwin) PLATFORM="darwin" ;;
  esac
fi

# Determine output path
OUTPUT_DIR="${NOMAD_HOME:-/opt/project-nomad}/storage"
OUTPUT_FILE="${OUTPUT_DIR}/nomad-disk-info.json"

collect_linux() {
  DISK_LAYOUT=$(lsblk --json -o NAME,SIZE,TYPE,MODEL,SERIAL,VENDOR,ROTA,TRAN)

  FS_SIZE=$(df -B1 -x tmpfs -x devtmpfs -x squashfs | tail -n +2 | \
  awk 'BEGIN {print "["}
      {
          if (NR > 1) printf ","
          gsub(/%/, "", $5)
          printf "{\"fs\":\"%s\",\"size\":%s,\"used\":%s,\"available\":%s,\"use\":%s,\"mount\":\"%s\"}",
                  $1, $2, $3, $4, $5, $6
      }
      END {print "]"}')

  cat > "$OUTPUT_FILE" << EOF
{
"diskLayout": $DISK_LAYOUT,
"fsSize": $FS_SIZE
}
EOF
}

collect_darwin() {
  # Build a blockdevices JSON array from diskutil
  DISK_LAYOUT='{"blockdevices":['
  local first_disk=true

  # List physical disks
  for disk in $(diskutil list | grep "^/dev/disk" | grep -v "synthesized" | awk '{print $1}'); do
    local disk_name
    disk_name=$(basename "$disk")

    # Get disk info via diskutil
    local disk_info
    disk_info=$(diskutil info "$disk" 2>/dev/null)

    local model size_bytes is_solid_state protocol vendor
    model=$(echo "$disk_info" | grep "Device / Media Name:" | sed 's/.*Device \/ Media Name: *//')
    size_bytes=$(echo "$disk_info" | grep "Disk Size:" | grep -oE '[0-9]+ Bytes' | awk '{print $1}')
    is_solid_state=$(echo "$disk_info" | grep "Solid State:" | awk '{print $NF}')
    protocol=$(echo "$disk_info" | grep "Protocol:" | awk '{print $NF}')
    vendor=$(echo "$disk_info" | grep "Device / Media Name:" | awk '{print $1}' | sed 's/:.*//')

    # rota: false for SSD, true for HDD
    local rota="true"
    if [[ "$is_solid_state" == "Yes" ]]; then
      rota="false"
    fi

    if [[ -z "$size_bytes" ]]; then
      size_bytes="0"
    fi

    if $first_disk; then
      first_disk=false
    else
      DISK_LAYOUT+=","
    fi

    # Escape any quotes in model/vendor
    model=$(echo "$model" | sed 's/"/\\"/g')
    vendor=$(echo "$vendor" | sed 's/"/\\"/g')

    DISK_LAYOUT+="{\"name\":\"${disk_name}\",\"size\":\"${size_bytes}\",\"type\":\"disk\",\"model\":\"${model:-Unknown}\",\"serial\":\"\",\"vendor\":\"${vendor:-}\",\"rota\":${rota},\"tran\":\"${protocol:-}\"}"

    # Add partitions as children
    local partitions
    partitions=$(diskutil list "$disk" 2>/dev/null | grep "^ " | grep -v "TYPE\|NAME" | awk '{print $NF}' | grep "^disk")

    for part in $partitions; do
      local part_info part_size part_type part_name_val
      part_info=$(diskutil info "/dev/${part}" 2>/dev/null)
      part_size=$(echo "$part_info" | grep "Disk Size:" | grep -oE '[0-9]+ Bytes' | awk '{print $1}')
      part_type=$(echo "$part_info" | grep "Content (IOContent):" | sed 's/.*Content (IOContent): *//')
      part_name_val=$(echo "$part_info" | grep "Volume Name:" | sed 's/.*Volume Name: *//')

      if [[ -z "$part_size" ]]; then
        part_size="0"
      fi

      part_name_val=$(echo "$part_name_val" | sed 's/"/\\"/g')

      DISK_LAYOUT+=",{\"name\":\"${part}\",\"size\":\"${part_size}\",\"type\":\"part\",\"model\":\"\",\"serial\":\"\",\"vendor\":\"\",\"rota\":${rota},\"tran\":\"\"}"
    done
  done

  DISK_LAYOUT+=']}'

  # Build fsSize array from df (macOS df uses 512-byte blocks by default, use -b for bytes on GNU, but macOS doesn't have -B)
  FS_SIZE=$(df -k | tail -n +2 | grep -v "^devfs\|^map " | \
  awk 'BEGIN {print "["}
      {
          if (NR > 1) printf ","
          # Convert 1K-blocks to bytes
          size=$2*1024
          used=$3*1024
          available=$4*1024
          gsub(/%/, "", $5)
          # $9 is mount point (may contain spaces, so use everything from $9 onward)
          mount=""
          for(i=9;i<=NF;i++) { if(mount!="") mount=mount" "; mount=mount$i }
          if (mount == "") mount=$NF
          printf "{\"fs\":\"%s\",\"size\":%d,\"used\":%d,\"available\":%d,\"use\":%s,\"mount\":\"%s\"}",
                  $1, size, used, available, $5, mount
      }
      END {print "]"}')

  cat > "$OUTPUT_FILE" << EOF
{
"diskLayout": $DISK_LAYOUT,
"fsSize": $FS_SIZE
}
EOF
}

# Main loop — runs once if OUTPUT_FILE dir doesn't exist yet (host-side cron/launchd mode)
# or loops every 300s (container mode)
run_collection() {
  if [[ "$PLATFORM" == "darwin" ]]; then
    collect_darwin
  else
    collect_linux
  fi
}

# If run directly (not sourced), execute collection
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Ensure output directory exists
  mkdir -p "$(dirname "$OUTPUT_FILE")"

  # Check if we're running in a loop (container mode) or one-shot (launchd mode)
  if [[ "${NOMAD_COLLECTOR_LOOP:-false}" == "true" ]]; then
    while true; do
      run_collection
      sleep 300
    done
  else
    run_collection
  fi
fi
