<!--
SPDX-FileCopyrightText: 2024-2026 Jonas I. Liechti <j-i-l@t4d.ch>
SPDX-License-Identifier: CC-BY-NC-4.0
-->
# cont[AI]*nerd* - NixOS Installation

This directory contains a NixOS flake module that declaratively manages
the entire contain deployment: users, systemd services, Podman
Quadlet container, and file permissions.

For the general (non-NixOS) installation, see the main
[README](../README.md).

---

## Prerequisites

- **NixOS** with [flakes enabled](https://wiki.nixos.org/wiki/Flakes)
- **Podman** (enabled automatically by the module)
- API credentials for at least one LLM provider - see the
  [OpenCode docs](https://opencode.ai/docs/providers)

---

## Installation

### 1. Add the flake input

In your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    contain = {
      url = "github:j-i-l/contAIn";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, contain, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        contain.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

### 2. Configure the module

In your `configuration.nix` (or a dedicated module file):

```nix
{ config, ... }:
{
  services.contain = {
    enable = true;

    # Required
    primaryUser  = "alice";
    projectPaths = [ "/home/alice/Projects" ];

    # Optional (shown with defaults)
    # primaryHome = "/home/alice";
    # agent.user  = "agent";
    # server.host = "127.0.0.1";
    # server.port = 3000;
    # container.memoryLimit    = "2g";
    # container.pidsLimit      = 100;
    # container.opencodeVersion = "latest";
  };
}
```

### 3. Apply

```bash
sudo nixos-rebuild switch
```

This will:
1. Create the `agent` system user (sharing the primary user's group)
2. Enable Podman
3. Build the container image (first run only, or when the Containerfile changes)
4. Generate `config.json` in `~/.config/contain/` and merge the sandbox
   policy into `~/.config/opencode/opencode.json` (via the
   `contain-opencode-config-seed` unit)
 5. Install the Quadlet container file
 6. Generate a stable OpenCode v2 server password at
    `/var/lib/contain/server-password` (unless `server.passwordEnvFile` is set)
 7. Start the watcher service and commit timer
 8. Set project directory permissions

**Note:** Project directories are identity-mounted at their exact host paths
inside the container (e.g., `/home/alice/Projects` stays
`/home/alice/Projects`). This keeps OpenCode's session `directory` identity
consistent between host-side clients and the containerized server. Podman
creates the intermediate mountpoint skeleton (root-owned); nothing outside
the mounted paths is exposed.

---

## Module Options Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable the contain service |
| `primaryUser` | string | - | Login name of the primary (human) user |
| `primaryHome` | path | `/home/${primaryUser}` | Home directory of the primary user |
| `projectPaths` | list of path | - | Directories the agent can access; created empty (primary-user-owned) if absent so bind mounts cannot fail |

OpenCode runtime files under `.config/opencode`, `.local/share/opencode`, and
`.local/state/opencode` are normalized to primary-user ownership with group-
writable permissions. This keeps `opencode.db` and provider state writable by
both the container agent and the primary user.
| `agent.user` | string | `"agent"` | Container agent username |
| `server.host` | string | `"127.0.0.1"` | Server listen address |
| `server.port` | port | `3000` | Public client port (activation socket in on-demand mode) |
| `server.internalPort` | port | `3001` | Port OpenCode binds behind the proxy (on-demand mode) |
| `server.passwordEnvFile` | nullOr str | `null` | Env file with `OPENCODE_SERVER_PASSWORD`. When unset, `contain-server-password` generates/persists one at `/var/lib/contain/server-password` (v2 always requires a password) |
| `onDemand.enable` | bool | `true` | Start on first client connection, stop when idle |
| `onDemand.idleTimeout` | string | `"20min"` | Idle window before the container stops |
| `container.memoryLimit` | string | `"2g"` | Container memory limit |
| `container.pidsLimit` | int | `100` | Container PID limit |
| `container.opencodeVersion` | string | `"latest"` | OpenCode version to install (`latest` or `2.x.y`; a `1.x` pin falls back to the v1 GitHub release) |
| `opencode.envFiles` | list of str | `[]` | Extra `EnvironmentFile=` entries for the container, e.g. a file with `OPENCODE_API_KEY=<key>` to activate OpenCode Go declaratively (v2 stores runtime credentials in its database, not `auth.json`) |
| `opencode.configSeedFile` | nullOr str | `null` | JSON merged into `~/.config/opencode/opencode.json` before the container starts (below the sandbox policy) |

---

## Post-Deployment

### Configure OpenCode credentials

Run the TUI and use `/connect` to authenticate with your LLM provider:

```bash
sudo contain-tui
# Then run: /connect
```

Credentials are saved automatically and persist across sessions — no restart needed.

OpenCode v2 always requires a server password; `contain-tui` handles it for you.
For the Neovim plugin, set `server.url`/`server.port` to the public port and
supply the same password (`/var/lib/contain/server-password`, or your
`server.passwordEnvFile`) — see the main README's "Server Authentication"
section.

### Access the TUI

```bash
sudo contain-tui
```

This attaches an interactive TUI to the headless OpenCode server running inside the container. You can use `/connect` at any time to authenticate or re-authenticate with an LLM provider.

### Prepare project permissions

For fine-grained permission control (locking `.env`, secrets, making `.git/`
read-only), use the bundled preparation script:

```bash
# Preview changes
sudo contain-prepare-permissions --dry-run ~/Projects

# Apply
sudo contain-prepare-permissions ~/Projects

# Or read paths from the generated config
sudo contain-prepare-permissions --from-config
```

---

## Updating

To update the container image after a new OpenCode release:

```nix
# Pin a specific version
services.contain.container.opencodeVersion = "0.5.0";
```

Then rebuild:

```bash
sudo nixos-rebuild switch
```

The stage-2 `contain-image` service detects image input changes and rebuilds
automatically. To force a rebuild:

```bash
sudo rm /var/lib/contain/containerfile.sha256
sudo nixos-rebuild switch
```

---

## Development Shell

For contributing to contain, a development shell is provided:

```bash
nix develop github:j-i-l/contAIn

# Or from a local checkout
nix develop
```

This gives you `bash`, `jq`, `podman`, `inotify-tools`, and `shellcheck`.

---

## How It Differs from the Imperative Setup

| Aspect | Imperative (`setup.sh`) | NixOS module |
|--------|------------------------|--------------|
| User creation | `useradd` | `users.users` |
| Systemd services | Files copied to `/etc/systemd/system/` | `systemd.services.*` |
| Quadlet file | Template rendered by `sed` | `environment.etc` |
| Configuration | Interactive `configure.sh` | Nix module options |
| Script PATH | Ambient `$PATH` | Nix `makeWrapper` |
| Idempotency | Script checks | Nix guarantees |
| Rollback | Manual | `nixos-rebuild switch --rollback` |
| SELinux labels | `:rw,Z` volume flag | `:rw` (NixOS uses AppArmor or none) |

---

## Troubleshooting

### Container service not starting

```bash
systemctl status contain
journalctl -u contain -n 50
```

If the Quadlet generator did not pick up the file:

```bash
ls -la /etc/containers/systemd/
systemctl daemon-reload
```

### Image not built

Check if the activation script ran:

```bash
ls -la /var/lib/contain/containerfile.sha256
podman images | grep contain
```

Force a rebuild:

```bash
sudo rm /var/lib/contain/containerfile.sha256
sudo nixos-rebuild switch
```

### Watcher service errors

```bash
journalctl -u contain-watcher -f
```

Ensure `inotify-tools` is available (it should be, via `environment.systemPackages`).
