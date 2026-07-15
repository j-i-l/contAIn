# contAIn Architecture

## Overview

contAIn runs an AI coding agent (OpenCode) inside a sandboxed Podman
container. The system is designed as a **per-user application** — each user
runs their own container instance with their own configuration.

```
 Host                            Container
 ----                            ---------
 /home/alice/Projects  ------>   /home/alice/Projects (bind mount, rw, identity)
 /home/alice/work      ------>   /home/alice/work     (bind mount, rw, identity)

 ~/.config/contain/ ---->   /etc/contain/   (bind mount, ro)
 ~/.config/opencode/     ---->   ~/.config/opencode/   (bind mount, ro)
 ~/.local/share/opencode/ --->   ~/.local/share/opencode/ (bind mount, rw)
 ~/.local/state/opencode/ --->   ~/.local/state/opencode/ (bind mount, rw)
```

## Components

### Container Image (`container/Containerfile`)

Based on Ubuntu 24.04. Contains:
- The `opencode` binary (downloaded at build time)
- An `agent` user whose group GID matches the primary user's group on the host
- An entrypoint wrapper (`entrypoint.sh`) that handles volume housekeeping
  and privilege dropping
- `opencode-tui.sh` for attaching a TUI to the running server

### Entrypoint (`container/entrypoint.sh`)

The entrypoint runs as root and performs three tasks before starting OpenCode:

1. **Volume housekeeping**: Ensures subdirectories OpenCode expects (e.g.
   `~/.local/share/opencode/log`) exist inside the bind-mounted volumes.

2. **Umask configuration**: Sets `umask 002` so that files created by the agent
   are group-writable (`664` for files, `775` for directories). This ensures
   the primary user can always read and write agent-created files.

3. **Privilege dropping**: Uses `setpriv` to drop to the `agent` user before
   executing `opencode serve`.

### NixOS Module (`nix/module.nix`)

Declarative NixOS configuration that:
- Creates the `agent` system user
- Generates `config.json` and the `opencode.json` policy
- Builds the container image via `podman build` (passing the primary user's
  GID so the agent shares the same group inside the container)
- Installs the Quadlet `.container` file
- Sets up the file watcher and commit timer services

### Shell Scripts (`scripts/`)

For non-NixOS deployments:
- `configure.sh` -- interactive configuration generator
- `setup.sh` -- provisions users, builds the container, installs systemd units
- `prepare-permissions.sh` -- ensures directory traversal permissions

## Path Identity

### The Problem

OpenCode clients (neovim plugin, TUI) connect to the server with the
host-side project path (e.g., `?directory=/home/alice/projects/foo`).
OpenCode uses this as `Instance.directory`, which becomes the default
working directory (`cwd`) for shell command execution — and, critically,
the `directory` identity recorded on every **session**. Session listing is
scoped by that directory string, so all entry points (server, attached TUI,
host-side editor plugins) must agree on the exact same path strings, or
sessions created through one entry point become invisible to the others.

An earlier design mounted project directories under a container-private
`/workspace/...` prefix and bridged host paths with entrypoint-created
symlinks. That produced **divergent directory identities** (`/workspace/nix`
vs `/home/alice/Projects/nix` for the same project, varying with the entry
point and image revision), which stranded previously created sessions.

### The Solution

Project directories are bind-mounted at their **identical host paths**
(identity mounts):

```
Container filesystem:

/home/alice/Projects/  (bind mount from host, same path)
/home/alice/work/      (bind mount from host, same path)
```

There is no path translation layer: no `/workspace`, no symlinks, no
`path_map`. Podman creates the intermediate mountpoint skeleton
(e.g. `/home/alice/`) automatically.

### Security Properties

The mountpoint skeleton created by Podman:
- Intermediate directories (e.g., `/home/alice/`) are owned by `root:root`
  with mode `755`
- They contain **only** the project mountpoints
- The agent can traverse these directories but cannot:
  - Create files in them (not the owner, directory not group-writable)
  - Read any host home directory contents (they don't exist in the container)
  - Access `.ssh/`, `.bashrc`, or any other dotfiles (they don't exist)

### Git Ownership

Project files are owned by the primary user's UID while the agent runs under
its own UID. Without countermeasures git refuses to operate on such
worktrees ("dubious ownership"), which breaks OpenCode's project discovery:
every session collapses into the fallback `global` project. The image
therefore sets `git config --system safe.directory '*'`. Access control is
enforced by the mount allow-list plus group permissions, not by git.

## Permission Model

### How the Agent Gets Access

When you configure `projectPaths`, you are **opting in** to the agent being
able to access those directories. This is the primary access control
mechanism.

Inside the container, the `agent` user belongs to a group whose GID matches
your (the primary user's) primary group. This means:

- **Any file you own with group-read permission (`g+r`) is readable by the
  agent** — and on most Linux systems, the default umask (`022`) creates
  files with `644` permissions, so group-read is on by default.

- **The agent can only access files within the directories you've explicitly
  configured** in `projectPaths`. It has no access to the rest of your
  home directory or system.

Think of it this way: by adding a directory to `projectPaths`, you're
saying "the agent can work with files in this folder, just like a
colleague who's in my team." The agent reads what your group can read
and writes what your group can write.

### Controlling Access

| What you want                    | How to do it                                  |
|----------------------------------|-----------------------------------------------|
| Agent can read and write a file  | Default for files with `g+rw` (or `664`)      |
| Agent can read but not write     | `chmod g-w file` (mode `644`)                 |
| Agent completely blocked         | `chmod 600 file` (removes all group access)   |
| Agent blocked from a directory   | `chmod 700 dir` (removes group traversal)     |

### Agent-Created Files

The agent runs with `umask 002`, so files it creates are:
- Files: `664` (owner rw, group rw, other r)
- Directories: `775` (owner rwx, group rwx, other rx)

This ensures you (the primary user) can always read and write files the
agent creates, since you share the same group.

### The File Watcher

The `contain-watcher` systemd service monitors project directories via
inotify. When the agent creates or modifies files (inside the container via
bind mounts), the watcher reassigns ownership from `agent` to the primary
user and defensively ensures group-write permission (`g+w` on files, `g+ws`
on directories). This makes the system robust regardless of the umask that
was active when the file was created (e.g. the entrypoint sets `umask 002`,
but `podman exec` inherits the default `022`).

### `.git/` Directories

The `prepare-permissions.sh` script sets `.git/` directories to group
read-only (`g-w` on contents). This means the agent can read git state
(branches, commits, etc.) but cannot directly modify git internals. The
agent can still commit via git commands — it just can't tamper with the
`.git/` directory directly.

## Container Lifecycle

### On-Demand Mode (default)

The container does not run at boot. The public port is owned by a systemd
activation socket, and the container only runs while clients are connected:

```
opencode.nvim / contain-tui ──TCP──▶ contain-proxy.socket (127.0.0.1:3000)
                                         │ first connection activates
                                         ▼
                              contain-proxy.service
                              systemd-socket-proxyd --exit-idle-time=20min
                                         │ forwards to 127.0.0.1:3001
                                         │ Requires=/After=
                                         ▼
                              contain.service
                              (opencode serve --port 3001,
                               Notify=healthy, StopWhenUnneeded=yes)
```

- **Start:** the first TCP connection activates the proxy, which pulls up
  the container (and transitively the image build and secret-seed units).
  `Notify=healthy` delays readiness until the Quadlet-defined runtime
  healthcheck passes, so early connections wait in the socket backlog instead
  of being refused. The healthcheck is attached when Podman creates the
  container rather than stored in image metadata: contAIn keeps its native OCI
  image format, whose manifest does not carry Containerfile `HEALTHCHECK`.
- **Stay up:** long-lived client connections (the neovim plugin's SSE event
  stream, an attached TUI) keep the proxy busy.
- **Stop:** when the last connection closes, `systemd-socket-proxyd` exits
  after the idle timeout; `contain.service` then has no active dependent
  left and `StopWhenUnneeded=yes` stops it (the watcher follows via
  `PartOf=`). Session data lives in the bind-mounted `opencode.db`, so
  nothing is lost across stop/start cycles.

Configure via `on_demand` (bool), `idle_timeout` (systemd time span) and
`internal_port` in `config.json`, or `services.contain.onDemand.*` /
`services.contain.server.internalPort` in the NixOS module.

### Always-On Mode (`on_demand: false`)

Legacy behavior: OpenCode binds the public port directly, the container is
`WantedBy=multi-user.target` and starts at boot; no socket or proxy units
are installed.

### Startup Flow

```
contain.service starts (socket activation or boot)
  -> podman creates container from localhost/contain:latest
  -> entrypoint.sh runs as root:
       1. Ensures expected subdirectories exist in mounted volumes
       2. Sets umask 002
       3. Drops to agent user via setpriv
       4. Execs: opencode serve --hostname 127.0.0.1 --port <listen port>
```

### Health Check

The container includes a health check that curls
`http://127.0.0.1:${PORT}/global/health` every 30 seconds.

### Commit Timer

The `contain-commit` timer runs daily to commit the container's
overlay filesystem, preserving any tools the agent installed in
`/opt/tools/bin/`.

## Configuration Files

### `config.json`

Generated by `configure.sh` (non-NixOS) or `module.nix` (NixOS).
Located at `~/.config/contain/config.json`.

```json
{
  "primary_user": "alice",
  "primary_home": "/home/alice",
  "project_paths": ["/home/alice/Projects", "/home/alice/work"],
  "agent_user": "agent",
  "host": "127.0.0.1",
  "port": 3000,
  "install_dir": "/opt/contain"
}
```

### `opencode.json`

OpenCode policy file. Controls which directories OpenCode is allowed to
access (host paths — identical inside the container):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "external_directory": {
      "/home/alice/Projects/**": "allow",
      "/home/alice/work/**": "allow"
    }
  }
}
```

## Deployment Options

### NixOS (Recommended)

Add to your NixOS configuration:

```nix
{
  services.contain = {
    enable = true;
    primaryUser = "alice";
    projectPaths = [ "/home/alice/Projects" "/home/alice/work" ];
  };
}
```

### Non-NixOS (Ubuntu/Debian)

```bash
sudo ./scripts/configure.sh   # Interactive configuration
sudo ./scripts/setup.sh        # Provisions everything
```
