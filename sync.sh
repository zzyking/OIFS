#!/bin/bash
# ==============================================================================
# Obsidian-iCloud Fast Sync Launcher
# ==============================================================================

### 1. Configurations
LOCAL="$HOME/Documents/Obsidian/"
ICLOUD="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/"
LOG="$HOME/Library/Logs/obsidian_sync.log"
SYNC_LOCK="$HOME/Library/Logs/obsidian_sync.lock"
WATCHER_PIDS=()

export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

# ------------------------------------------------------------------------------
# 2. Core Atomic Functions (exported for subprocesses use)
# ------------------------------------------------------------------------------

# rsync encapsulation
run_rsync() {
  local src="$1"
  local dest="$2"
  local delete_flag=""
  
  if [ "$3" = "true" ]; then delete_flag="--delete"; fi

  rsync -av $delete_flag \
    --exclude=".DS_Store" \
    --exclude=".Trash" \
    --exclude=".obsidian/workspace" \
    --exclude=".obsidian/workspace.json" \
    "$src" "$dest" >>"$LOG" 2>&1
}

# Return success when rsync would copy or delete something.
rsync_has_changes() {
  local src="$1"
  local dest="$2"
  local delete_flag=""

  if [ "$3" = "true" ]; then delete_flag="--delete"; fi

  rsync -ain $delete_flag \
    --exclude=".DS_Store" \
    --exclude=".Trash" \
    --exclude=".obsidian/workspace" \
    --exclude=".obsidian/workspace.json" \
    "$src" "$dest" 2>>"$LOG" | grep -q .
}

# Remove directories from iCloud that no longer exist locally and only contain
# ignored sync artifacts such as .DS_Store.
prune_deleted_empty_dirs() {
  local local_root="${LOCAL%/}"
  local icloud_root="${ICLOUD%/}"

  find "$icloud_root" -depth -type d | while read -r icloud_dir; do
    local rel_path=""
    local local_dir=""

    if [ "$icloud_dir" = "$icloud_root" ]; then
      continue
    fi

    rel_path="${icloud_dir#"$icloud_root"/}"
    local_dir="$local_root/$rel_path"

    if [ -e "$local_dir" ]; then
      continue
    fi

    find "$icloud_dir" -depth \
      \( -name ".DS_Store" -o -path "*/.Trash" -o -path "*/.obsidian/workspace" -o -path "*/.obsidian/workspace.json" \) \
      -exec rm -rf {} + >/dev/null 2>&1

    if rmdir "$icloud_dir" 2>/dev/null; then
      log_info "🗑️ Removed deleted empty dir from iCloud: $rel_path"
    fi
  done
}

# Remove local directories that no longer exist in iCloud and only contain
# machine-specific garbage such as .DS_Store or .Trash.
prune_deleted_empty_local_dirs() {
  local local_root="${LOCAL%/}"
  local icloud_root="${ICLOUD%/}"

  find "$local_root" -depth -type d | while read -r local_dir; do
    local rel_path=""
    local icloud_dir=""

    if [ "$local_dir" = "$local_root" ]; then
      continue
    fi

    rel_path="${local_dir#"$local_root"/}"
    icloud_dir="$icloud_root/$rel_path"

    if [ -e "$icloud_dir" ]; then
      continue
    fi

    find "$local_dir" -depth \
      \( -name ".DS_Store" -o -path "*/.Trash" \) \
      -exec rm -rf {} + >/dev/null 2>&1

    if rmdir "$local_dir" 2>/dev/null; then
      log_info "🗑️ Removed deleted empty dir from Local: $rel_path"
    fi
  done
}

# unified logs
log_info() {
  echo -e "[$(date '+%F %T')] $1" >>"$LOG"
}

export -f run_rsync rsync_has_changes prune_deleted_empty_dirs prune_deleted_empty_local_dirs log_info
export LOG SYNC_LOCK LOCAL ICLOUD # Also export path variables

# ------------------------------------------------------------------------------
# 3. Automatic cleaning mechanism (in case of lone background process)
# ------------------------------------------------------------------------------
cleanup() {
  rm -rf "$SYNC_LOCK"
  for pid in "${WATCHER_PIDS[@]}"; do
    kill "$pid" 2>/dev/null
  done
  pkill -P $$  # Kill all child processes of the current process
  log_info "🛑 OIFS: Processes cleaned up. Exiting.\n\n"
  exit
}

# Capture normal exit signals
trap cleanup SIGHUP SIGINT SIGTERM

# ------------------------------------------------------------------------------
# 4. Flow control functions
# ------------------------------------------------------------------------------

pre_sync() {
  log_info "⬇️ Presync: iCloud → local"
  run_rsync "$ICLOUD" "$LOCAL" "false"
  log_info "✅ Presync done" >>"$LOG"
}

final_sync() {
  log_info "🛡️ Final sync: local → iCloud before exit"
  run_rsync "$LOCAL" "$ICLOUD" "true"
  prune_deleted_empty_dirs
}

# Background monitoring logic
start_watcher() {
  local label="$1"
  local watch_dir="$2"
  local src="$3"
  local dest="$4"
  local delete_flag="$5"
  local prune_mode="$6"
  local watcher_pid=""

  log_info "👀 Starting watcher: $label"

  fswatch -o "$watch_dir" -l 10 \
    --exclude="\.DS_Store" \
    --exclude="\.Trash" \
    --exclude="\.obsidian/workspace" \
    --exclude="\.obsidian/workspace\.json" | while read -r _; do

    # 1. Check Obsidian process
    if ! pgrep -x "Obsidian" >/dev/null; then break; fi

    # Skip mirrored or empty events that do not produce real rsync work.
    if ! rsync_has_changes "$src" "$dest" "$delete_flag"; then
      continue
    fi

    # Atomic operation: try to create a folder, continue only if successful, failure indicates the lock is being used
    if mkdir "$SYNC_LOCK" 2>/dev/null; then
      (
        log_info "🔄 Sync Triggered: $label"

        # Reserved write buffer for Obsidian/iCloud flushes
        sleep 2

        run_rsync "$src" "$dest" "$delete_flag"

        if [ "$prune_mode" = "icloud" ]; then
          prune_deleted_empty_dirs
        elif [ "$prune_mode" = "local" ]; then
          prune_deleted_empty_local_dirs
        fi

        log_info "✅ Sync completed: $label"

        # Forced cooldown: hold the lock a bit longer to coalesce bursts
        sleep 5
        rm -rf "$SYNC_LOCK"
      ) &
    else
      # Failed creation indicates running synchronization, just silently ignore it
      continue
    fi

  done &

  watcher_pid=$!
  WATCHER_PIDS+=("$watcher_pid")
  log_info "🤖 Watcher started with PID: $watcher_pid ($label)"
}

# ------------------------------------------------------------------------------
# 5. Main program
# ------------------------------------------------------------------------------

main() {
  mkdir -p "$(dirname "$LOG")"

  if [ -f "$LOG" ]; then
    echo "$(tail -n 1000 "$LOG")" > "$LOG"
  fi
  
  if ! command -v fswatch &> /dev/null; then
      echo "Error: fswatch not found!"
      exit 1
  fi
  
  rm -rf "$SYNC_LOCK"

  pre_sync
  start_watcher "Local → iCloud" "$LOCAL" "$LOCAL" "$ICLOUD" "true" "icloud"
  start_watcher "iCloud → Local" "$ICLOUD" "$ICLOUD" "$LOCAL" "true" "local"

  log_info "📝 Launching Obsidian"
  open -a "Obsidian"

  log_info "👀 Obsidian is running. Script is now holding..."
  while pgrep -x "Obsidian" >/dev/null; do
    sleep 3
  done
  
  final_sync

  cleanup
}

if [ "${OIFS_SOURCE_ONLY:-0}" != "1" ] && { [ -z "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]}" = "$0" ]; }; then
  main "$@"
fi
