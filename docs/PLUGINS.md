[Dex Explorer](../README.md) / Plugins

# Plugins

A `.dexplugin` file contains the plugin's details and Luau source. Its buttons appear under **Plugins** in the Dex menu. Plugins can also add menu actions and shortcuts.

[Install](#install-a-plugin) · [Create a plugin](#create-a-plugin) · [Package fields](#package-fields) · [API](#plugin-api) · [Actions](#menu-actions-and-shortcuts)

## Install a plugin

1. Open the Dex menu and click **+** next to **Plugins**.
2. Select a package from `dex-explorer/plugins` in your executor workspace. To use a link or paste a package, open **Import From** instead.
3. Click **Review**, then **Install** and **Enable**.

Only enable plugins you trust. They run with the same access as Dex. Use **Copy Source** to read the code if your executor supports the clipboard.

## Manage installed plugins

Right click a plugin button for its menu. On a phone or tablet, tap the ellipsis.

For a plugin installed from a file, choose **Review Local Changes** to read the file again. For one installed from a link, choose **Check for Update**. Review the changes, then click **Update** and **Enable**.

**Reload** restarts the installed copy. **Disable** stops it but keeps it installed; **Uninstall** removes it and its buttons. Open **Plugin Output** from the same menu to read its logs and errors.

## Create a plugin

The example below adds a **Hello** button that opens a window. Keep its details in `plugin.json` and its code in `main.luau`. A short Node.js script combines them into the file Dex installs.

### 1. Package details

Save as `plugin.json`:

```json
{
  "schema": 1,
  "id": "example.hello",
  "name": "Hello",
  "version": "1.0.0",
  "description": "A first Dex plugin."
}
```

### 2. Luau source

Save as `main.luau`:

```luau
local plugin = ...
local window, content = plugin:CreateWindow("Hello", 320, 200)

local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Text = "Hello from Dex"
plugin.Lib.StudioText(label)
label.Parent = content

plugin:RegisterButton("open", function()
    window:Show()
    plugin:Log("Opened Hello")
end)
```

### 3. Build the package

Save as `package.mjs` in the same folder:

```js
import { readFileSync, writeFileSync } from "node:fs";

const manifest = JSON.parse(readFileSync("plugin.json", "utf8"));
manifest.source = readFileSync("main.luau", "utf8");

writeFileSync("hello.dexplugin", JSON.stringify(manifest, null, 2));
```

Run `node package.mjs`, then copy `hello.dexplugin` into `dex-explorer/plugins` and [install it](#install-a-plugin). Click **Hello** in the Dex menu to open the window.

After editing either file, run `node package.mjs` again and use **Review Local Changes** to update the installed copy.

## Package fields

The generated `.dexplugin` file is JSON. Its `source` field contains the Luau from `main.luau`.

| Field | Required | Description |
| :--- | :---: | :--- |
| `schema` | Yes | `1` |
| `id` | Yes | Plugin ID, such as `example.hello`. Start with a lowercase letter or digit; use lowercase letters, digits, `.`, `_`, or `-`. |
| `name` | Yes | Plugin name shown in Dex. |
| `version` | Yes | Version string shown during review, such as `1.0.0`. |
| `source` | Yes | UTF-8 Luau source, up to 512 KiB. The packaging step adds this. |
| `author` | No | Author name shown during review. |
| `description` | No | Description shown during review. |
| `icon` | No | Custom icon, such as `rbxassetid://123456`. |
| `startup` | No | `true` runs the entry script when enabled and when Dex starts. Defaults to `false`, which loads it on the first button click. |
| `buttons` | No | Up to 24 button definitions with `id`, `name`, and optional `icon` and `tooltip` fields. |

Without `buttons`, Dex creates one button with ID `open`, using the plugin's name and icon. Keep the plugin ID unchanged when publishing updates.

## Plugin API

Use `local plugin = ...` to get the plugin API.

| Method | What it does |
| --- | --- |
| `plugin:RegisterButton(idOrDefinition, callback)` | Register a callback for a declared button, or pass a definition to add or update a button after loading. |
| `plugin:SetButtonActive(id, active)` | Changes whether a toolbar button looks selected. |
| `plugin:RegisterAction(definition, callback)` | Adds a menu action or shortcut. Returns a function that removes it. |
| `plugin:CreateWindow(title, width, height)` | Returns a Dex window and its content frame. Call `window:Show()` to open it. Dex closes and cleans up the window when the plugin stops. |
| `plugin:Track(resource)` | Destroy an instance, disconnect a connection, or run a cleanup function when the plugin stops. Returns the resource. The entry script can also return a cleanup function. |
| `plugin:GetSetting(key, fallback)` | Read a saved setting, or return the fallback. |
| `plugin:SetSetting(key, value)` | Save a setting as a JSON value. Returns `false` and an error message if saving fails. |
| `plugin:Log(...)` and `plugin:Warn(...)` | Write a message to **Plugin Output**. |

A button definition accepts `ID`, `Name`, `Icon`, and `Tooltip`. Declare buttons in the package's `buttons` list if they should appear before the plugin loads.

`plugin.Main`, `plugin.Apps`, `plugin.Lib`, and `plugin.Settings` are Dex's internal objects. You can use them, but they may change between releases.

## Properties panel rows

Use `RegisterPropertyRow` to add a read-only text row under **Plugins** in the Properties panel.

```lua
local plugin = ...
local remove, refresh = plugin:RegisterPropertyRow({
    ID = "selection-count",
    Name = "Selected objects",
}, function(selection)
    return tostring(#selection)
end)
```

The callback receives a frozen array of selected instances in selection order. Return a string to display the row or `nil` to hide it. The callback must finish without yielding. Dex skips a row if its callback fails. Rows appear for selections of real instances and follow the panel's name filter. Call `refresh()` when your plugin's data changes or `remove()` to withdraw the row. Dex removes it automatically when the plugin stops. Row IDs are unique within each plugin.

## Menu actions and shortcuts

Call `RegisterAction` from your plugin's entry script. Set `startup` to `true` if the action should be ready as soon as the plugin is enabled.

```luau
local plugin = ...

plugin:RegisterAction({
    ID = "log-path",
    Name = "Log Object Path",
    Surface = "Explorer",
    Shortcut = "Ctrl+Alt+M",
    When = function(context)
        return context.Target ~= nil
    end,
}, function(context)
    plugin:Log(context.Target:GetFullName())
end)

plugin:RegisterAction({
    ID = "comment-selection",
    Name = "Toggle Comment",
    Surface = "Editor",
    When = function(context)
        return context.Editable and context.Selection.Selected
    end,
}, function(context)
    context.Editor.Command("ToggleComment")
end)
```

Each action needs a unique lowercase `ID`, a `Name`, and a `Surface`. `Tooltip`, `Shortcut`, and `When` are optional, though `Global` actions need a shortcut. `When` must return a boolean without yielding.

| Surface | Menu and callback context |
| --- | --- |
| `Explorer` | Appears in **Plugins** in the Explorer context menu. `Selection` is an array of selected instances. `Target` is the instance the action applies to, when one is available. |
| `Editor` | Appears in **Plugins** in the Script Editor context menu. The callback receives `Editor`, `Document`, `Script`, `Selection`, `Selections`, and `Editable`. Selection offsets count UTF-8 bytes, starting at 1. `Last` points just past the selection. |
| `Global` | Runs from its shortcut. The callback receives `Surface = "Global"`. |

Use `Ctrl+Alt` or `Alt+Shift` with a letter, number, or function key. You can also add `Shift` to `Ctrl+Alt`. Pick a combination that Dex or Roblox hasn't reserved. A shortcut can be shared between Explorer and Script Editor. Global shortcuts must be unique across both panels.

## Plugin Output

Right click a plugin button and choose **Plugin Output**. Calls to `plugin:Log`, `plugin:Warn`, `print`, and `warn` appear here, along with errors.

Click a row for details. An error's line number opens its source in the Script Editor. **Clear** removes only that plugin's messages from the current session.

---

[Readme](../README.md) · [User guide](USAGE.md) · [Dex MCP](mcp/SETUP.md) · [Building](../BUILDING.md)
