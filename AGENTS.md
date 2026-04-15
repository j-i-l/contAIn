# AGENTS.md — Instructions for cont[AI]n Coding Agents

## Core Principles

1. **Do not guess.** When uncertain, investigate first. Read the code, run
   the tests, check the logs. Assumptions lead to wrong fixes.

2. **Test-driven approach.** Write or identify the relevant test first,
   then implement. Verify the test fails for the right reason before writing
   the fix.

3. **When facing multiple options, debug first.** Do not pick an approach
   at random. Narrow down the root cause, then choose the correct fix with
   evidence.

4. **Fixing a failing test does NOT mean adapting the test to pass.**
   Unless you have strong evidence the test itself is wrong — in which case
   you **debug first** to be sure — the test defines the expected behavior.
   Fix the code, not the test.

5. **Always `chmod g+w` any file you create.** Files you create are owned
   by your UID. Once the file watcher reassigns ownership to the primary
   user, you lose write access unless group write is set. Run
   `chmod g+w <file>` immediately after creating any new file.

---

## Project Overview

**contAIn** is a rootful Podman container system for running AI coding
agents (OpenCode) in a sandboxed environment with host project directories
bind-mounted in. It uses systemd (Quadlet) for service management and Unix
group permissions for file access control.

---

## Repository Structure

```
contAIn/
├── container/          # Container image (Containerfile, entrypoint, scripts)
├── docs/               # Documentation and assets (architecture.md, logo.svg)
├── lib/                # Shared shell libraries (sourced by scripts and services)
│   ├── render-template.sh   # Systemd unit template rendering
│   ├── contain-watcher.sh   # inotify file ownership watcher
│   ├── contain-commit.sh    # Container snapshot/commit
│   └── contain-tui.sh       # TUI attach wrapper
├── nix/                # NixOS module and wrapped scripts
├── scripts/            # User-facing setup scripts
│   ├── configure.sh         # Interactive config generator
│   ├── setup.sh             # Idempotent deployment (8 steps)
│   └── prepare-permissions.sh  # Project directory permission setup
├── systemd/            # Systemd unit templates (.in = templated)
│   ├── contain.container.in      # Quadlet container unit
│   ├── contain-watcher.service.in
│   ├── contain-commit.service
│   └── contain-commit.timer
├── tests/              # Test scripts
│   └── test-template-rendering.sh
├── tui/                # Terminal UI (TypeScript + bash fallback)
│   ├── src/                 # TypeScript source (blessed library)
│   ├── cont-ai-nerd-tui.sh # Pure bash TUI fallback
│   ├── config-schema.json   # JSON Schema for config.json
│   ├── package.json
│   └── tsconfig.json
├── .github/workflows/  # CI (shellcheck, template tests, e2e deployment)
├── flake.nix           # Nix flake (NixOS module + dev shell)
└── README.md
```

---

## Code Style

### Shell Scripts

- **Shebang:** `#!/usr/bin/env bash`
- **Safety flags:** `set -euo pipefail` (always, at the top)
- **Indentation:** 2 spaces
- **Linting:** `shellcheck` (CI enforced)
- **Comments:** Descriptive header block at top of each script/library,
  inline comments for complex logic
- **Error handling:** Explicit checks, `die()` or `echo >&2` + `exit 1`
- **Config loading:** `jq` to parse `~/.config/contain/config.json`
- **Libraries:** `lib/*.sh` are sourceable (no `set -e` side effects);
  functions are documented with usage comments

### TypeScript (TUI)

- **Target:** ES2022, strict mode
- **Module system:** ESM (`"type": "module"`)
- **Framework:** `blessed` for terminal UI
- **Build:** `tsc` (output to `dist/`)
- **Run:** `node --loader ts-node/esm src/index.ts`
- **Node version:** >= 18.0.0

### Commit Messages

Follow conventional commit format:

```
type(scope): description
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

---

## Building and Testing

### Lint Shell Scripts

```bash
shellcheck scripts/*.sh lib/*.sh container/*.sh
```

### Run Template Tests

```bash
bash tests/test-template-rendering.sh
```

No root required, no external dependencies beyond bash + coreutils.

### Build the TUI

```bash
cd tui && npm install && npm run build
```

### Full Deployment (requires root + Podman)

```bash
sudo ./scripts/configure.sh
sudo ./scripts/setup.sh
```

### CI Workflows

- `.github/workflows/test-contAIn.yml` — shellcheck, template tests,
  full e2e deployment
- `.github/workflows/contAIn-nix.yml` — NixOS module validation

---

## Key Architecture Details

### File Permissions Model

The agent user shares the primary user's group GID. Access is controlled
via standard Unix group permissions:

- `g+rw` — agent can read and write
- `g+r` — agent can read only
- `g=` (mode 600/700) — agent is blocked
- `.git/` directories are automatically set read-only for group

### Systemd Integration

The container runs as a Quadlet-managed service. Templates (`*.in` files)
use `@@VARIABLE@@` placeholders rendered by `lib/render-template.sh`.

### Container

- Base: Ubuntu 24.04
- Runs OpenCode as the `agent` user (UID mapped to host)
- Host networking, binds to localhost only
- Resource limits: 2GB RAM, 100 processes
- Health check: `curl http://localhost:PORT/health`

### Configuration

JSON config at `~/.config/contain/config.json`. Schema defined in
`tui/config-schema.json`. Key fields: `primary_user`, `primary_home`,
`project_paths`, `agent_user`, `host`, `port`, `install_dir`,
`agent_systems`.
