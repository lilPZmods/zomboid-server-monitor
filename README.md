# Zomboid Server Monitor

A small macOS menu-bar app for people who run a **Project Zomboid dedicated server on a Mac**. It keeps your Steam Workshop update watcher running all the time and shows the server's mod status in the menu bar.

- Starts at login and comes back by itself if it crashes or is killed.
- Restarts your watcher command within 30 seconds if that dies.
- Shows in the menu bar whether the server is running, when it last checked Steam, and which mods are out of date.
- Turns off with one click, and stays off until you open the app again.

## What it needs

- macOS 13 or later
- Xcode or the Xcode Command Line Tools (for `swiftc`)
- A **watch command** that runs forever and handles the actual work: checking the Workshop for new uploads and restarting your server when one lands. The app keeps that command alive. It doesn't talk to Steam itself.

## Setup

```bash
git clone https://github.com/lilPZmods/zomboid-server-monitor.git
cd zomboid-server-monitor
cp config.example.env config.env   # then edit config.env
./build.sh                         # builds and copies the app to /Applications
./install-agent.sh                 # starts it now and at every login
```

### config.env

| Setting | What it is |
|---|---|
| `APP_NAME` | Name of the app in /Applications and the menu bar |
| `BUNDLE_ID`, `AGENT_LABEL` | macOS identifiers. Change them if you fork the app |
| `WORK_DIR` | Your server folder. The watch command runs here |
| `WATCH_COMMAND` | The command to keep running. Separate arguments with `\|`, e.g. `/opt/homebrew/bin/node\|native-server.mjs\|watch` |
| `LOG_FILE` | Where the watch command's output goes (relative to `WORK_DIR`) |
| `STATUS_FILE` | Optional JSON file the watcher writes after each check (format below) |
| `OFF_COMMAND` | Optional command run by "Turn Watcher Off". Leave empty to just unload the agent |

After changing `config.env`, run `./build.sh` again.

### Status file format

If your watcher writes this JSON after each check, the menu shows it:

```json
{
  "checked_at": 1792920852,
  "server_running": true,
  "mods": [
    { "title": "My Mod", "server": "current", "local": "match" },
    { "title": "Other Mod", "server": "outdated", "local": "differs" }
  ]
}
```

- `server` is anything other than `"current"`: the mod is listed as behind Steam.
- `local` is `"differs"`: your local copy has changes that aren't uploaded yet. With Project Zomboid that gets you kicked for a checksum mismatch when you join.

## Using it

Click the circular-arrows icon in the menu bar:

- **Check Now** restarts the watch command, so it checks right away.
- **Open Log** opens the watcher log in Console.
- **Open Project Folder** opens `WORK_DIR` in Finder.
- **Turn Watcher Off…** stops everything. It stays off through reboots until you open the app from /Applications again.

The icon changes to a warning triangle when a mod is out of date or has local changes, and to a warning arrow when the watch command isn't running.

From Terminal:

```bash
launchctl print gui/$(id -u)/io.github.lilpzmods.zomboid-server-monitor   # status
./install-agent.sh --remove                                              # uninstall the agent
rm -rf "/Applications/Zomboid Server Monitor.app"                        # remove the app
```

## How it works

`install-agent.sh` writes a launch agent to `~/Library/LaunchAgents/<AGENT_LABEL>.plist` with `RunAtLoad` and `KeepAlive`. macOS starts the app at login and restarts it if it exits. The app runs `WATCH_COMMAND` as a child process and stops it when the app quits. In System Settings → General → Login Items it shows up under the app's name.

## License

MIT. See [LICENSE](LICENSE).
