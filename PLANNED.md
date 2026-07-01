# Planned Work

contAIn is currently a rootful Podman-based OpenCode container. The immediate
goal is to keep that path usable on NixOS while leaving room for a stronger
Nix-native isolation model and alternate agent runtimes.

## Near Term

- Keep the existing Podman/Quadlet backend working as the default deployment.
- Support both x86_64 and aarch64 Linux hosts when building the OpenCode image.
- Treat provider credentials as declarative secrets, not mutable runtime state:
  `auth.json` should be deployed from sops-backed inventory data and replaced on
  activation.
- Keep project access opt-in via explicit `projectPaths`; do not mount a whole
  home or workspace parent by default.

## MicroVM Backend

- Investigate replacing or complementing the Podman backend with a NixOS
  MicroVM backend.
- Keep the backend selectable, e.g. `podman` now and `microvm` later.
- Preserve the current permission model where the agent can only access explicit
  project paths.
- Decide how host paths, credentials, and generated state should be shared with
  the MicroVM without broad home-directory exposure.

## Agent Runtime Options

- Keep OpenCode as the first supported runtime.
- Add `mini-swe-agent` as another runtime option once the container interface is
  stable enough.
- Adapt editor integration, especially the Neovim plugin workflow, so sessions
  can target either OpenCode or mini-swe-agent.
- Keep runtime-specific configuration and credentials separate from the generic
  sandbox/backend configuration.

## Security Notes

- Provider API keys and access tokens must live in inventory-managed sops
  secrets.
- Generated mutable state should be reviewed before being persisted or backed
  up.
- Sensitive project files remain protected by normal Unix group permissions;
  helper tooling may detect and optionally lock common secret patterns, but the
  user remains the authority on access.
