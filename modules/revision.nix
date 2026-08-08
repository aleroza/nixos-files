# Embedded in every host via flake.nix (specialArgs.gitMeta, passed through
# modules/default.nix). Always on — there is no auto.* gate for this; the
# git sha is metadata about the configuration itself, not a toggle.
#
# What it produces:
#   * `system.configurationRevision`        — visible via
#                                            `nixos-version --configuration-revision`
#                                            and `nixos-version --json`. Empty when
#                                            the env vars are unset.
#   * `/etc/os-release`                    — completely rewritten via
#                                            `lib.mkForce environment.etc."os-release".text`
#                                            with the same NixOS keys upstream emits,
#                                            plus five GIT_* keys at the bottom.
#                                            Uses pure-Nix substitution (no shell,
#                                            no awk, no activation script), so it
#                                            lands directly in the Nix store and
#                                            /etc/static/ et al. and the activation
#                                            step is just a symlink swap, idempotent
#                                            for free.
#
# Source of truth: four env vars read by flake.nix at evaluation time and
# forwarded here via specialArgs.gitMeta:
#   NIXOS_GIT_REVISION  full 40-char HEAD sha
#   NIXOS_GIT_BRANCH    branch name or "detached"
#   NIXOS_GIT_DIRTY     "1" if tree is dirty, else unset/0
#   NIXOS_GIT_URL       remote URL ("github:aleroza/nixos-files" or whatever
#                       `git config --get remote.origin.url` returns for the
#                       checkout the user invoked nixos-rebuild from)

{ gitMeta ? null, lib, config, ... }:
let
  defaults = {
    rev = "";
    lastModifiedCommitId = "";
    shortRev = "";
    branch = "no-branch";
    dirty = false;
    url = "";
  };
  # Fill missing gitMeta attributes with defaults so downstream code can rely
  # on m.rev / m.shortRev / m.dirty / etc. being always-defined. `gitMeta`
  # may be `null` when the module is imported outside a flake.nix that
  # forwards a specialArgs.gitMeta; in that case substitute `{}`.
  m = defaults // (if gitMeta == null then {} else gitMeta);

  baseRev =
    if m.rev != "" then m.rev
    else if m.lastModifiedCommitId != "" then m.lastModifiedCommitId
    else "";

  isDirty = m.dirty or false;

  shortRev =
    if m.shortRev != "" then m.shortRev
    else if baseRev != "" then lib.substring 0 7 baseRev
    else "";

  revString = baseRev + (lib.optionalString isDirty "-dirty");
  shortRevString = shortRev + (lib.optionalString isDirty "-dirty");

  v = config.system.nixos.version;        # e.g. "26.05.20260727.2f5a153"
  label = config.system.nixos.label;       # same
  vsuffix = config.system.nixos.versionSuffix;  # ".20260727.2f5a153"
  release = config.system.nixos.release;   # e.g. "26.05"
in
{
  # `nixos-version --configuration-revision` and the `configurationRevision`
  # field in `nixos-version --json`. Empty when env vars are unset.
  system.configurationRevision = if baseRev != "" then revString else "";

  # Replace /etc/os-release wholesale, mirroring what upstream's
  # nixos/modules/misc/version.nix emits (so we don't lose
  # BUILD_ID, HOME_URL, BUG_REPORT_URL, ANSI_COLOR, etc.), and tacking on
  # the five GIT_* keys at the bottom.
  #
  # `lib.mkForce` accepts that this overrides whatever upstream puts there
  # — at our single concrete version (nixos-26.05) the keys below are
  # stable; if upstream adds new ones we update here too.
  environment.etc."os-release".text = lib.mkForce ''
    NAME=NixOS
    ID=nixos
    BUILD_ID=${lib.escapeShellArg v}
    VERSION=${lib.escapeShellArg label}
    VERSION_ID=${lib.escapeShellArg vsuffix}
    PRETTY_NAME="NixOS ${lib.escapeShellArg label}"
    ANSI_COLOR="0;38;2;126;186;228"
    CPE_NAME="cpe:/o:nixos:nixos:${lib.escapeShellArg release}"
    DEFAULT_HOSTNAME=nixos
    HOME_URL="https://nixos.org/"
    DOCUMENTATION_URL="https://nixos.org/learn.html"
    BUG_REPORT_URL="https://github.com/NixOS/nixpkgs/issues"
    GIT_REVISION=${lib.escapeShellArg revString}
    GIT_SHORT_REVISION=${lib.escapeShellArg shortRevString}
    GIT_BRANCH=${lib.escapeShellArg m.branch}
    GIT_DIRTY=${if isDirty then "true" else "false"}
    GIT_URL=${lib.escapeShellArg m.url}
  '';
}
