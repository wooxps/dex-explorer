[Dex Explorer](../README.md) / User guide

# Using Dex

Hover over an icon in the main menu to see the tool's name. Open a tool from there, then drag its header or borders to move or resize it.

- [Explorer and Properties](#explorer-and-properties)
- [Script Editor](#script-editor)
- [Find in Place](#find-in-place)
- [Assets and 3D previews](#assets-and-3d-previews)
- [Save Instance](#save-instance)
- [Input Macros](#input-macros)
- [Transform Tools](#transform-tools)
- [Console](#console)
- [Reconstructor](#reconstructor)
- [Settings and saved files](#settings-and-saved-files)
- [Plugins and Dex MCP](#plugins-and-dex-mcp)

## Explorer and Properties

Select an object in Explorer to show its properties. Select several objects to change their properties together.

Type in the Explorer search field to filter the tree. You can search for a name or combine a class with property values:

| Search | Finds |
| :--- | :--- |
| `Door` | Objects whose names contain `Door` |
| `is:BasePart` | Parts, including classes that inherit from BasePart |
| `is:BasePart and Anchored=false` | Unanchored parts |
| `is:Sound` | Sounds |

Clear the field to return to the full tree.

Right click an object for its actions. Players have **View Player** and **Listen To**. Use **Highlight** to mark an object in the game.

Open the same menu to stop an action: **Stop Viewing Player**, **Stop Listening To**, or **Remove Highlight** replaces the action you started.

**Find References** looks for uses of the selected object elsewhere in the game. Select a result to go to that object in Explorer.

## Script Editor

Double click a script in Explorer to open it. Dex reads or decompiles its source using the functions your executor provides.

While editing:

- Autocomplete includes Roblox APIs, local tables, and modules you require.
- Hover over a name for its type and documentation.
- Hold Ctrl and click a name to open its definition.
- Code is formatted as you type and paste.

Use the editor's find and replace controls to search the current document. Use **Find in Place** to search across scripts.

## Find in Place

Open **Find in Place** from the main menu and enter the text to search for. Click a result to open the script at that line. Replacement edits the source in editor tabs.

Searches can only include source available to your client and executor. They skip CoreScripts.

## Assets and 3D previews

Open **Asset Manager**, choose an asset type, and select an entry. The panel shows its preview and the objects that use it. Click one of those references to select the object in Explorer.

Use **Copy ID**, **Copy link**, or **Download** for the selected asset. Downloads require file and asset access from your executor.

Sounds and animations have playback controls. For an animation, choose an R6 or R15 rig that matches it. You can also use a selected rig.

**3D Viewer** opens parts and models in a separate viewport. Its camera controls let you inspect them without moving the game camera.

## Save Instance

1. Open **Save Instance** from the main menu.
2. Choose **Place** or **Selection** under **Objects**.
3. Enter a file name, or leave it blank for the automatic name.
4. Set any options you need and click **Save**.

The default provider, **Universal (USSI)**, uses UniversalSynSaveInstance. Choose **Executor** under **Provider** to use your executor's `saveinstance` instead.

Search the options by name. Open an option's details to read its description and check the default. File saving requires executor support.

## Input Macros

1. Open **Input Macros** and click **+** to create a recording.
2. Click **Record**, then perform the keyboard and mouse actions.
3. Press **F8** or click the recording bar's stop button.
4. Click **Play** to replay it. **F8** also stops playback.

Use the speed control to change playback speed or **Loop** to repeat it. Select an event to edit **Delay (s)**. **Trim** removes events before or after the selection, and **Hotkey** assigns a shortcut to the macro.

Recording over an existing macro replaces its events. Dex asks you to click **Record** again before doing that. Playback depends on the input functions available in your executor.

## Transform Tools

Select an object in Explorer or use the part and UI selection tools to pick one on screen. Open **Transform Tools** to move, rotate, or resize the selection.

## Console

The Console shows Roblox client output. Use its filters to narrow the messages and its command bar to run Luau through your executor.

## Reconstructor

The Reconstructor builds an inferred object hierarchy from the paths it finds. You can add script source or a traceback and inspect the resulting tree and its evidence. You can also copy paths or export the tree as JSON.

## Settings and saved files

Open Settings from the gear in the main menu. Dex stores its settings in `dex-explorer/settings.json` in your executor workspace. Plugins, macros, layouts, and caches use the same `dex-explorer/` folder.

For files from an older version, see [Workspace files](../BUILDING.md#workspace-files).

## Plugins and Dex MCP

For custom tools, see [Installing and writing plugins](PLUGINS.md). For access from an MCP client, see [Dex MCP setup](mcp/SETUP.md).

---

[Readme](../README.md) · [Plugins](PLUGINS.md) · [Dex MCP](mcp/SETUP.md) · [Building](../BUILDING.md)
