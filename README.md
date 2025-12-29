# OIFS (Obsidian-iCloud Fast Sync) 🚀

**OIFS** is a robust macOS shell script wrapper for [Obsidian](https://obsidian.md/). It ensures your vault is perfectly synced between a fast local directory and iCloud Drive using `rsync` and `fswatch` with atomic locking.

## 🛠 Prerequisites

You need macOS and the following tools:

1.  **fswatch** (Monitors file system changes):
    ```bash
    brew install fswatch
    ```
2.  **rsync** (Pre-installed on macOS, but Homebrew version is recommended).


## 📥 Usage

### Option 1: Automator Workflow (Recommended)

Packing OIFS into a macOS App allows you to launch Obsidian with a single click, completely hiding the terminal window.

1. Open **Automator.app** and select **Application**.
2. Add a **Run Shell Script** action.
3. Set "Shell" to `/bin/bash` and paste the contents of `sync.sh`.
4. Save it as `Obsidian Launcher.app` and move it to your `/Applications` folder.
5. (Optional) Give it a cool icon! Replace the default Automator icon with the [Obsidian icon](https://obsidian.md/blog/new-obsidian-icon/).

### Option 2: Direct Terminal Execution

For those who want to monitor the logs in real-time or for debugging.

1. Open Terminal.
2. Navigate to the script directory:
```bash
chmod +x sync.sh
bash ./sync.sh
```

## ❓ Why OIFS?

If you use Obsidian with iCloud on macOS, you've likely encountered:
- **iCloud Latency:** Files taking forever to download or upload.
- **Indexing Lag:** Obsidian getting stuck while iCloud "calculates" changes.
- **Conflicts:** Workspace file corruption due to slow sync.
- **Missing Files:** iCloud can't keep all files downloaded for indexing (especially common in MacOS 14 Sonoma and previous versions).


**OIFS** solves this by creating a "Fast Lane": you work on a **purely local folder** (zero latency), and OIFS mirrors every change to iCloud in the background using an optimized, non-blocking sync engine.

## ✨ Key Features

- **⬇️ Smart Presync:** Automatically pulls the latest changes from iCloud to Local before Obsidian opens in an incremental way.
- **⚡️ Atomic Mirroring:** Uses `rsync` with a custom **Atomic Lock** mechanism to prevent race conditions and redundant syncs.
- **⏳ Debounced Watcher:** Merges multiple file changes into a single `fswatch` sync event (10s window) to save CPU and battery.
- **🛡️ Zombie Protection:** Built-in `trap` logic ensures all background processes are killed when Obsidian exits.
- **📝 Structured Logging:** Beautiful, scannable logs to track your sync history.