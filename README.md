# Workspace Opener

An Omarchy menu plugin for opening projects at `~/Projects/<group>/<project>`.

## Install

```sh
omarchy plugin add https://github.com/DigitalBastion/omarchy-workspace-plugin.git --enable
```

Bind it in your user-owned Hyprland configuration (change the key as desired):

```ini
bind = SUPER, P, exec, omarchy-shell shell toggle io.github.digitalbastion.workspace-opener '{}'
```

## Usage

- Type to fuzzy-filter projects. The initial view has Recent, Most Used, and Other Projects; each project appears in one section only.
- `Up` / `Down` select; `Enter` or a single click opens the selected project in a new window of the current editor.
- `Ctrl+E` switches VS Code and Cursor for this opening.
- `Ctrl+T` opens the selected project in the configured default terminal.
- `Delete` removes an item from its current Recent or Most Used section until it is launched again.
- `Ctrl+R` rescans projects; `Escape` clears a filter, then closes the menu.

Projects with exactly the visible directories `src` and `output` open in `src`. Dot-prefixed items are ignored when making that determination.

## Configure

Create `$XDG_CONFIG_HOME/omarchy/workspace-opener/config.json` (normally `~/.config/omarchy/workspace-opener/config.json`):

```json
{
  "version": 1,
  "editor": "cursor",
  "dimBackdrop": true
}
```

`editor` is either `code` (the default) or `cursor`. `dimBackdrop` defaults to `false`.

Operational usage state is stored separately at `$XDG_STATE_HOME/omarchy/workspace-opener/history.json` (normally `~/.local/state/omarchy/workspace-opener/history.json`). Python 3 is the only runtime dependency; it is used from the standard library only.

## Develop

```sh
PLUGIN_DIR="$HOME/.config/omarchy/plugins/io.github.digitalbastion.workspace-opener"
omarchy plugin validate "$PLUGIN_DIR"
qmllint -I "$OMARCHY_PATH/shell" "$PLUGIN_DIR"/*.qml
python3 -m unittest tests/test_store.py
```
