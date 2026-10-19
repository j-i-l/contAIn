# CHANGELOG: OpenCode v1 → v2 Upgrade

## 🚀 **Major Changes**

### 1. **OpenCode v2 Support**
- **Binary Source**: OpenCode v2 is no longer published via GitHub releases. The container now downloads from:
  - `https://opencode.ai/update/api/latest/cli/opencode/opencode-linux-<arch>.tar.gz` (latest)
  - `https://opencode.ai/files/bin/<version>/opencode-linux-<arch>.tar.gz` (pinned v2)
  - Fallback to GitHub releases for `1.x` versions.
  - **Nix Adaptation**: Update `container.opencodeVersion` in `module.nix` to `"latest"` or a v2 tag (e.g., `"2.0.0"`).

---

### 2. **Authentication & Credentials**

#### **Server Password (Mandatory in v2)**
- OpenCode v2 **always requires a server password**. Without one, it auto-generates a new password on every boot, breaking stable client auth (TUI/plugin).
- **Nix Adaptation**:
  - A stable password is auto-generated at `/var/lib/contain/server-password` (root, `0600`) via the `contain-server-password` systemd unit.
  - **Override**: Set `services.contain.server.passwordEnvFile` to a custom path (e.g., a sops-nix secret).
    Example:
    ```nix
    services.contain.server.passwordEnvFile = "/run/secrets/opencode-server-password";
    ```
  - The password is passed to the container via `EnvironmentFile` in the Quadlet unit.

#### **Client Authentication**
- The in-container `opencode-tui.sh` maps `OPENCODE_SERVER_PASSWORD` → `OPENCODE_PASSWORD` for the client.
- **Neovim Plugin**: Configure the plugin to read the password from `/var/lib/contain/server-password`:
  ```lua
  require('opencode').setup({
    server = {
      url = 'http://127.0.0.1',
      port = 3000,
      password = function()
        local line = vim.fn.readfile('/var/lib/contain/server-password')[1]
        return (line:gsub('^OPENCODE_SERVER_PASSWORD=', ''))
      end,
    },
  })
  ```

#### **Provider Credentials**
- **v2 Change**: Credentials are now stored in OpenCode’s SQLite database (`opencode.db`) instead of `auth.json`.
- **Declarative Credentials**: Use `services.contain.opencode.envFiles` to pass environment files (e.g., `OPENCODE_API_KEY` for OpenCode Go).
  Example:
  ```nix
  services.contain.opencode.envFiles = [ "/run/secrets/opencode-go.env" ];
  ```
  The file must contain:
  ```
  OPENCODE_API_KEY=<your-key>
  ```
- **Runtime Credentials**: Credentials added via `/connect` in the TUI are persisted to the database and take precedence.

---

### 3. **Sandbox Policy (v2 `policies`)**
- **v1 → v2 Migration**:
  - v1 used `permission.external_directory` (a map of paths to `"allow"`).
  - v2 uses `policies` (an array of rules with `action`, `resource`, and `effect`).
- **Behavior**:
  - The first rule **hard-denies** all external directories (`external_directory:*`).
  - Subsequent rules **re-allow** each configured project path (`external_directory:<path>/*`).
  - Policies are evaluated **after** permissions and saved approvals, and **can only tighten access** (a repository cannot weaken the sandbox).
- **Nix Adaptation**: No changes needed. The `contain-opencode.json` policy is auto-generated from `projectPaths` in `module.nix`.

---

### 4. **Health Check Endpoint**
- **v1**: `/global/health`
- **v2**: `/api/info`
  - Returns `200` (auth ok) or `401` (API up behind auth). Both indicate readiness.
- **Nix Adaptation**: The Quadlet unit’s `HealthCmd` and `HealthStartupCmd` are auto-updated to use `/api/info`.
- **Startup Readiness**: Both deployment paths use `PodmanArgs=--sdnotify=healthy` so the proxy waits for OpenCode to accept connections. The explicit argument supports older Quadlet versions, including Podman 4.9.3, that parse `Notify` as a boolean.

---

### 5. **OpenCode Config (`opencode.json`)**
- **v1**: Read-only mount (`ro`).
- **v2**: Read-write mount (`rw`) to allow OpenCode to persist provider registration and helper files.
- **Nix Adaptation**: The `Volume` mount for `~/.config/opencode` is now `rw` in `contain.container.in`.

---

### 6. **Config Seed**
- **New Option**: `services.contain.opencode.configSeedFile`
  - Merges a host-provided JSON file into `~/.config/opencode/opencode.json` **before** the container starts.
  - Layering order (later wins):
    `existing runtime config` < `host seed` < `contAIn sandbox policy`.
  - The sandbox policy is **always last** to enforce declarative security.
  - Example:
    ```nix
    services.contain.opencode.configSeedFile = "/path/to/opencode-seed.json";
    ```

---

### 7. **Service Shutdown**

- Both deployment paths set `SuccessExitStatus=130` because OpenCode v2's runtime exits with status `130` on normal `SIGTERM` or `SIGINT` interruption.
- Other failure statuses remain failures. Any exit with status `130` is treated as successful and does not trigger `Restart=on-failure`.

---

## 📌 **NixOS Module Adaptations**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `server.passwordEnvFile` | `nullOr str` | `null` | Custom `OPENCODE_SERVER_PASSWORD` env file. If unset, auto-generated at `/var/lib/contain/server-password`. |
| `opencode.envFiles` | `listOf str` | `[]` | Additional `EnvironmentFile=` entries for the container (e.g., `OPENCODE_API_KEY`). |
| `opencode.configSeedFile` | `nullOr str` | `null` | JSON file merged into `~/.config/opencode/opencode.json`. |
| `container.opencodeVersion` | `str` | `"latest"` | OpenCode version to install (`"latest"`, `"2.x.y"`, or `"1.x"` for fallback). |

---

## 🔧 **Migration Steps for Nix Deployments**

1. **Update `module.nix`**:
   - Ensure `container.opencodeVersion` is set to `"latest"` or a v2 tag.
   - Optionally, set `server.passwordEnvFile` to a custom password file (e.g., sops-nix secret).
   - Optionally, add `opencode.envFiles` for declarative credentials (e.g., OpenCode Go).

2. **Update `configuration.nix`**:
   - Add the new options under `services.contain`:
     ```nix
     services.contain = {
       enable = true;
       server.passwordEnvFile = "/run/secrets/opencode-server-password"; # Optional
       opencode.envFiles = [ "/run/secrets/opencode-go.env" ]; # Optional
       container.opencodeVersion = "latest"; # or "2.0.0"
     };
     ```

3. **Rebuild and Deploy**:
   ```bash
   sudo nixos-rebuild switch
   ```

4. **Post-Upgrade**:
   - Test `/connect` in the TUI to ensure credentials are persisted to the database.
   - Verify the Neovim plugin can authenticate using the server password.

---

## ⚠️ **Breaking Changes**

1. **`auth.json` No Longer Seeded**:
   - If you relied on `authSeedFile` to deploy `auth.json`, switch to `envFiles` for environment-based credentials or use `/connect` in the TUI.
2. **Health Endpoint**:
   - Monitoring tools must update to check `/api/info` instead of `/global/health`.
3. **Identity Mounts**:
   - Project paths are now **identity-mounted** (host path == container path). Remove any `/workspace` remapping logic.

---

## 🧪 **Testing Notes**

- **On-Demand Lifecycle**: Full workflows verify idle state after setup reruns, unchanged configuration and policy, and healthy reactivation through the public socket. Directory-recovery tests also verify healthy reactivation before subsequent checks.
- **Identity Mounts**: Watcher tests use host-resolved absolute project paths inside the container while running as the agent. Mount tests verify actual read-write identity bind mounts and agent-visible path identity rather than legacy mappings or symlinks.
- **Failure Diagnostics**: Activation failures include verbose curl output, systemd unit status and definitions, activation journals, TCP listeners, and container logs.
- **Platform Coverage**: The smoke-test matrix covers Ubuntu 24.04 and Fedora latest and checks for Podman 4.4 or newer. Ubuntu 22.04 is no longer in the matrix because its packaged Podman lacks the required Quadlet support; this does not enforce a host OS restriction.

- The CI workflows (`test-contAIn.yml`, `contAIn-nix.yml`, `e2e-smoke.yml`) have been updated to:
  - Use `/api/info` for health checks.
  - Remove `auth.json` seeding tests.
  - Validate v2 `policies` in the generated `opencode.json`.
- **Manual Test**: After upgrading, verify:
  - The container starts and the health endpoint (`/api/info`) returns `200` or `401`.
  - The TUI can connect and `/connect` persists credentials to the database.
  - The Neovim plugin can authenticate using the server password.
