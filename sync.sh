#!/bin/bash
# ==============================================================================
# Obsidian-iCloud Fast Sync Launcher
# ==============================================================================

### 1. Configurations
LOCAL="$HOME/Documents/Obsidian/"
ICLOUD="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/"
LOG="$HOME/Library/Logs/obsidian_sync.log"
SYNC_LOCK="$HOME/Library/Logs/obsidian_sync.lock"

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

# unified logs
log_info() {
  echo -e "[$(date '+%F %T')] $1" >>"$LOG"
}

export -f run_rsync log_info
export LOG SYNC_LOCK LOCAL ICLOUD # Also export path variables

# ------------------------------------------------------------------------------
# 3. Automatic cleaning mechanism (in case of lone background process)
# ------------------------------------------------------------------------------
cleanup() {
  rm -rf "$SYNC_LOCK"
  kill $WATCHER_PID 2>/dev/null
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
}

# Background monitoring logic
start_watcher() {
  log_info "👀 Starting background file watcher..."
  
  rm -rf "$SYNC_LOCK"
  export SYNC_LOCK LOCAL ICLOUD LOG

  fswatch -o "$LOCAL" -l 10 \
    --exclude="\.DS_Store" \
    --exclude="\.Trash" \
    --exclude="\.obsidian/workspace" | while read -r _; do
    
    # 1. Check Obsidian process
    if ! pgrep -x "Obsidian" >/dev/null; then break; fi

    # Atomic operation: try to create a folder, continue only if successful, failure indicates the lock is being used
    if mkdir "$SYNC_LOCK" 2>/dev/null; then
      (
        log_info "🔄 Sync Triggered..." >>"$LOG"
        
        # Reserved Obsidian write buffer
        sleep 2
        
        # Execute function
        run_rsync "$LOCAL" "$ICLOUD" "true"
        
        log_info "✅ Sync completed" >>"$LOG"
        
        # Forced cooldown: Lock for an additional 5 seconds after synchronization
        sleep 5
        rm -rf "$SYNC_LOCK"
      ) &
    else
      # Failed creation indicates running synchronization, just silently ignore it
      continue
    fi

  done &
  
  WATCHER_PID=$!
  log_info "🤖 Watcher started with PID: $WATCHER_PID"
}

# ------------------------------------------------------------------------------
# 5. Main program
# ------------------------------------------------------------------------------

main() {
  mkdir -p "$(dirname "$LOG")"
  
  if ! command -v fswatch &> /dev/null; then
      echo "Error: fswatch not found!"
      exit 1
  fi
  
  rm -rf "$SYNC_LOCK"

  pre_sync
  start_watcher

  log_info "📝 Launching Obsidian"
  open -a "Obsidian"

  log_info "👀 Obsidian is running. Script is now holding..."
  while pgrep -x "Obsidian" >/dev/null; do
    sleep 3
  done
  
  final_sync

  cleanup
}

main