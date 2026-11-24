<p align="center">
  <img src="docs/dex-cover.png" width="760" alt="Dex Explorer">
</p>

<p align="center">An in-game Explorer for Roblox</p>

<p align="center">
  <a href="https://luau.org/"><img src="https://img.shields.io/badge/language-Luau-5e6ad2?style=flat-square" alt="Language: Luau"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-64748b?style=flat-square" alt="License: MIT"></a>
</p>

<p align="center">
  <a href="#run-dex"><strong>Run Dex</strong></a>
  &nbsp;·&nbsp;
  <a href="docs/USAGE.md">User guide</a>
  &nbsp;·&nbsp;
  <a href="docs/PLUGINS.md">Plugins</a>
  &nbsp;·&nbsp;
  <a href="docs/mcp/SETUP.md">Dex MCP</a>
</p>

## Run Dex

Paste this into your executor.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/wooxps/dex-explorer/main/loader.lua"))()
```

<p align="center">
  <a href="docs/explorer-preview.webp">
    <img src="docs/explorer-preview.webp" width="760" alt="Explorer search results and the Properties panel in Roblox">
  </a>
</p>

## Features

- [Explorer and Properties](docs/USAGE.md#explorer-and-properties) with searches by class or property, editing several objects at once, and actions such as highlighting objects or viewing players.
- [Script Editor](docs/USAGE.md#script-editor) with Luau autocomplete, types and docs on hover, formatting, and navigation to definitions.
- [Find in Place](docs/USAGE.md#find-in-place) to search scripts and open a result at its line.
- [Asset Manager and 3D Viewer](docs/USAGE.md#assets-and-3d-previews) to preview assets, download them, and see where they're used.
- [Save Instance](docs/USAGE.md#save-instance) with UniversalSynSaveInstance by default and an option to use the executor's version.
- [Input Macros](docs/USAGE.md#input-macros) to record and replay keyboard and mouse input, with speed, timing, and loop controls.
- [Plugins](docs/PLUGINS.md) for adding tools, menu actions, and shortcuts.
- [Dex MCP](docs/mcp/SETUP.md) for using Dex from Codex and other MCP clients.

Also includes [Transform Tools](docs/USAGE.md#transform-tools), a [Console](docs/USAGE.md#console), and a [Reconstructor](docs/USAGE.md#reconstructor).

## Performance

Dex Explorer timings are from the latest benchmark. Speedups compare them with the previously recorded [original Dex](https://github.com/LorekeeperZinnia/Dex) baseline.

| Task | Original Dex | Dex Explorer | Improvement |
| :--- | ---: | ---: | :--- |
| Find objects by name among 70,000 objects | 42.93 ms | 1.55 ms | **27.7× faster** |
| Repeat a search with 70,000 matches | 64.92 ms | 0.0103 ms | **6,315× faster** |
| Update syntax colors after an edit in a 10,000 line script | 19.25 ms | 0.00271 ms | **7,104× faster** |

Local tests with simulated objects and the search index ready. Index setup and UI rendering are excluded.

<details>
<summary>Benchmark details</summary>

Each column reports the median of nine runs of the same Luau CLI benchmark on an Intel Core i7-12700H. The original Dex functions come from [d6286cf](https://github.com/LorekeeperZinnia/Dex/commit/d6286cf27c77af749ad515d517d2500330f63ff2).

- **Name search:** a different search each run, with the same 70,000 simulated parts in both versions. Both return the same objects. Dex Explorer's initial index build is excluded.
- **Repeat search:** an unchanged query returning all 70,000 parts. Dex Explorer reuses its previous results; original Dex scans again.
- **Syntax colors:** ordinary edits near the start of a 10,000 line script. This measures updating the colors, not autocomplete or the rest of the editor.

These compare the search and syntax coloring functions. Sorting, frame waits and UI rendering are excluded. They do not measure FPS or the full time from typing to seeing results. Timings vary by game, executor and hardware.

[Recorded results](tests/fixtures/original-dex-benchmark.json) · [Run the benchmark](BUILDING.md#performance-reports) · [Benchmark source](tests/benchmark_dex.py)

</details>

## Documentation

- [User guide](docs/USAGE.md)
- [Installing and writing plugins](docs/PLUGINS.md)
- [Dex MCP setup](docs/mcp/SETUP.md)
- [Building from source](BUILDING.md)

## Help

[Report a bug](https://github.com/wooxps/dex-explorer/issues/new) with the steps to reproduce it, your executor, and the error text. For UI bugs, include a screenshot or recording.

## Credits

Developed by [Wooxps](https://github.com/wooxps).

Based on [Dex++ by Chillz](https://github.com/AZYsGithub/DexPlusPlus) and [Moon's Dex](https://github.com/LorekeeperZinnia/Dex). [MIT License](LICENSE).
