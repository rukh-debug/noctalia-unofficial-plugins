# Noctalia Plugins Registry

***Unofficial*** plugin registry for [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell) based on the [official plugin registry](https://github.com/noctalia-dev/noctalia-plugins).

## Overview

This repository hosts my personal/forked/non-upstreamed plugins for Noctalia Shell. The `registry.json` file is automatically maintained and provides a centralized index of all available plugins.

## Installation

To use plugins from this registry:

1. Open **Noctalia Settings** → **Plugins** → **Sources**
2. Click **Add custom repository**
3. Enter a repository name (e.g., "Unofficial Plugins")
4. Add the repository URL:
   ```
   https://github.com/rukh-debug/noctalia-unofficial-plugins
   ```
5. The plugins will now appear in your **Available** tab

You can then browse and install any plugin from this repository. 

## Registry Automation

The plugin registry is automatically maintained using GitHub Actions:

- **Automatic Updates**: Registry updates when manifest.json files are modified
- **PR Validation**: Pull requests show if registry will be updated

See [.github/workflows/README.md](.github/workflows/README.md) for technical details.

## Available Plugins

Check [registry.json](registry.json) for the complete list of available plugins.

## License

MIT - See individual plugin licenses in their respective directories.