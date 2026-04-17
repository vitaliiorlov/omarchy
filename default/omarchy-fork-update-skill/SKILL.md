---
name: omarchy-fork-update
description: >
  Merge upstream basecamp/omarchy releases into the personal fork.
  Use when: syncing upstream, merging new omarchy version, updating fork,
  pulling upstream changes, "new omarchy version", "upstream update",
  "sync fork", "merge upstream". Covers: fetch, merge, conflict resolution,
  config diffing, tag pushing, and post-merge cleanup.
---

# Omarchy Fork Update Skill

Merge upstream [basecamp/omarchy](https://github.com/basecamp/omarchy) releases into the personal fork (`vitaliiorlov/omarchy`) adapted for CachyOS.

## Prerequisites

- Working directory: `~/.local/share/omarchy`
- Git remotes: `origin` = fork, `upstream` = `basecamp/omarchy`
- Branch: `master`

## Update Procedure

### Step 1: Fetch and assess

```bash
git fetch upstream --tags
git log --oneline upstream/master...HEAD   # divergence
git log --oneline v<current>..upstream/master  # upstream changes
git diff v<current>..upstream/master --stat    # changed files summary
```

Report to the user: how many new commits, what version, high-level summary of changes.

### Step 2: Stash pending work (pre-flight)

Before merging, check `git status`. If the tree is dirty, stash it — `git merge` will refuse to run if any working-tree file conflicts with an incoming change, and a stale staged-but-modified file (e.g. a new file staged as empty but later given content) will also block `git stash`.

```bash
git status
# If dirty: re-stage any new/modified files cleanly, then stash
git add -A    # or just the problematic files
git stash push -u -m "pre-upstream-merge pending work"
```

The stash is restored in Step 7 after the merge commit.

### Step 3: Merge

```bash
git merge upstream/master
```

### Step 4: Resolve conflicts

Conflicts are expected in fork-modified files. Follow these rules:

**Fork convention (`# [omarchy]` comments):**
- Lines commented out with `# [omarchy]` must stay commented out — these are intentional CachyOS overrides
- If upstream changed the original line, update the `# [omarchy]` comment to reflect the new upstream version, but keep it commented out
- If upstream deleted a line we have commented out, remove our `# [omarchy]` comment entirely (stay in sync)

**Merge strategy per file type:**

| Pattern | Strategy |
|---------|----------|
| `install/omarchy-base.packages` | Keep our `# [omarchy]` comment-outs (fcitx5, sddm, tldr), keep our CachyOS replacements (linux-cachyos, linux-cachyos-headers), add any new upstream packages |
| `install/omarchy-other.packages` | Same as above. Keep `# [omarchy]` on linux-headers/snapper, keep our CachyOS equivalents, add new upstream entries (e.g. new hardware packages) |
| `install/config/all.sh` | Keep `# [omarchy]` on nvidia.sh, keep fork-only scripts (default-shell.sh, disable-snapper.sh), add new upstream scripts |
| `install/login/all.sh` | Keep `# [omarchy]` on sddm.sh and limine-snapper.sh |
| `install/preflight/guard.sh` | Keep `# [omarchy]` on distro guard and limine check |
| `default/limine/default.conf` | Keep CachyOS overrides (KERNEL_CMDLINE commented out, BOOT_ORDER added) |
| `bin/omarchy-reinstall-git` | Keep fork URL (`vitaliiorlov/omarchy`), adopt any new flags from upstream (e.g. `--depth=1`) |
| `bin/omarchy-menu` | Keep LG TV Control entries, merge new upstream menu items |
| `default/pacman/*.conf` | Keep `[omarchy]` repo section |

**General conflict resolution:**
1. Read both sides of every conflict carefully
2. Keep fork customizations (identified by `# [omarchy]` or fork-specific code)
3. Accept upstream additions (new files, new features, new packages)
4. When upstream reorganizes code (moves/renames files), follow the reorganization and drop our references to the old locations
5. Verify referenced files exist: `ls <path>` or `git show upstream/master:<path>`

### Step 5: Audit `# [omarchy]` comments and excluded packages

**5a. Verify `[omarchy]` markers still match upstream**

Check if upstream removed any lines we commented out:

```bash
grep -rn '\[omarchy\]' . --include='*.sh' --include='*.conf' --include='*.packages' --include='*.toml' --include='*.jsonc'
```

For each marker, run `git show upstream/master:<file>` and verify the original line still exists upstream. If upstream deleted it too, remove our `# [omarchy]` comment to stay in sync.

**5b. Verify no new code path reintroduces an excluded package**

The `[omarchy]` marker audit only catches lines the fork commented out. It does NOT catch upstream introducing a new `omarchy-pkg-add fcitx5` (or equivalent) in a fresh install script or migration. Run the exclusion audit on every new or modified `.sh` since the previous tag:

```bash
# Exclusion list: packages the fork deliberately does not install
EXCLUDED='fcitx5|snapper|sddm|limine-snapper-sync|\blinux\b|linux-headers|makima'

# Grep pkg-add / pacman -S / systemctl enable calls in changed .sh files
git diff v<previous>..HEAD --name-only -- '*.sh' \
  | xargs grep -nE "(omarchy-pkg-add|omarchy-pkg-aur-add|pacman +-S|systemctl +enable).*($EXCLUDED)" 2>/dev/null
```

If anything matches, surface it to the user — upstream may have re-added a package under a new code path.

### Step 6: Audit new migrations

Migrations (`migrations/*.sh`) are the main attack surface for silent breakage. They run once on `omarchy-update` and can:
- Install or uninstall packages (e.g. re-adding excluded packages, or removing one the user actively relies on)
- Touch boot/kernel files (`/etc/default/limine`, `/etc/udev/rules.d/`, `limine-mkinitcpio`, `limine-update`)
- Write to user's `~/.config/` or wipe existing config dirs

List new/modified migrations since the previous tag and read each one:

```bash
git diff v<previous>..HEAD --stat -- migrations/
```

For each migration, classify:

| Class | Definition | Action |
|---|---|---|
| **no-op** | Guard condition fails on user's hardware/setup (no battery, no XPS, no swapfile, package not installed) | Report as no-op, let it run |
| **benign** | Reinstalls idempotent wrappers, creates harmless files | Report briefly, let it run |
| **cosmetic** | Will emit errors on stderr but exits 0 (e.g. `sudo tee /usr/lib/chromium/...` when chromium isn't installed) | Report the noise; offer pre-skip via `touch ~/.local/state/omarchy/migrations/skipped/<id>.sh` |
| **destructive** | Uninstalls a package the user uses, wipes `~/.config/<app>/`, touches limine/boot/btrfs/snapper/kernel cmdline | **Stop and ask the user before running `omarchy-update`** |

**Verify actual system state** before classifying — don't assume:
- `pacman -Qi <pkg>` for each package the migration touches
- `systemctl is-enabled <service>` for services it disables/removes
- `ls <path>` for config dirs it deletes (`~/.config/makima`, `~/.config/fcitx5`, etc.)
- `bin/omarchy-hw-match <model>`, `bin/omarchy-battery-present`, `bin/omarchy-hw-intel-ptl` for hardware guards
- `[[ -f /etc/limine-entry-tool.d/resume.conf ]]`, `[[ -f /swap/swapfile ]]` for limine/hibernation guards

Present a table to the user: migration id, what it does, guard condition, actual match on this system, verdict (no-op / benign / cosmetic / destructive), recommendation.

For any **destructive** migration — including pkg-drop of something installed, or writes to `/etc/default/limine` — ask explicitly before the user runs `omarchy-update`. Offer pre-skipping: `touch ~/.local/state/omarchy/migrations/skipped/<id>.sh`.

Also re-check excluded packages (Step 5b) against migration contents — a migration installing fcitx5 via `omarchy-pkg-add` would bypass our `omarchy-base.packages` comment-outs.

### Step 7: Verify, commit, restore stash

```bash
# Ensure no conflict markers remain
grep -rn '<<<<<<\|>>>>>>' . --include='*.sh' --include='*.conf' --include='*.packages' --include='*.jsonc'

# Stage resolved files and commit
git add <resolved files>
git commit -m "Merge upstream/master: v<version> - <brief summary of key changes>"

# Restore pre-merge pending work (from Step 2)
git stash pop
```

The commit message should list conflicts resolved and key upstream changes.

### Step 8: Diff configs against `~/.config/`

Compare upstream config changes against the user's local files:

```bash
git diff v<previous>..upstream/master -- config/
```

For each changed config file:
1. Read the repo version (`config/<path>`)
2. Read the user's local version (`~/.config/<path>`)
3. **Only flag functional changes** worth applying. Skip:
   - Comment-only changes (documentation examples)
   - Personal preference differences (fonts, keyboard layouts, monitor configs, theming)
   - Files the user has intentionally customized with a completely different structure
4. Present a table: file, change description, recommendation (apply/skip)
5. Wait for user confirmation before applying

**Proactively update or propose updates for these configs** — don't just list them, actually diff and apply:
- **Waybar** (`~/.config/waybar/config.jsonc`, `style.css`) — tooltip changes, new modules, format string fixes
- **Hyprland** (`~/.config/hypr/`) — window rules, new bindings, env changes, autostart changes
- **uwsm/env** — PATH changes, new environment variables
- **tmux** (`~/.config/tmux/tmux.conf`) — new status indicators, binding changes
- **Any other config in `config/`** that has functional upstream changes

For straightforward bug fixes and improvements (e.g. removing broken tooltips, adding missing PATH entries), apply them directly and report what was changed. For changes that could alter the user's workflow or appearance, ask first.

After applying changes:
- `chezmoi re-add <file>` for each modified `~/.config/` file
- Restart affected services (`omarchy-restart-waybar`, `hyprctl reload`, etc.)

### Step 9: Push and update

```bash
git push origin master --tags
```

Tags MUST be pushed — otherwise waybar shows a false update icon (`omarchy-update-available` compares local vs remote tags).

Then tell the user to run `omarchy-update` in a terminal (it needs an interactive TTY for the confirmation prompt).

### Step 10: Check `omarchy-nvim` package drift

`omarchy-update` runs `pacman -Syu`, which may upgrade the `omarchy-nvim` package. The nvim config is NOT managed by this fork — it ships as a separate Arch package from the `[omarchy]` pacman repo, installing into `/usr/share/omarchy-nvim/config/`. The user's `~/.config/nvim/` was bootstrapped once and is now heavily customized (~25 custom plugins). Pacman upgrades do NOT auto-sync — drift accumulates silently.

After the user confirms `omarchy-update` ran, check for drift:

```fish
diff -rq /usr/share/omarchy-nvim/config ~/.config/nvim 2>&1 | grep differ
```

**Files worth syncing** (pull in when upstream changes them):
- `lua/plugins/all-themes.lua` — new themes added periodically. Always sync; then tell user to run `:Lazy sync` in nvim to install new theme plugins. *Historical note: syncing this file once fixed a catppuccin v2.0.0 rendering regression, likely via load-order / priority changes.*
- `lua/plugins/omarchy-theme-hotreload.lua` — hot-reload logic improvements.
- `plugin/after/transparency.lua` — transparent highlight group list.

**Files to leave alone** (user has customized, review diffs for upstream bug fixes only, don't blindly overwrite):
- `lua/config/autocmds.lua`, `keymaps.lua`, `lazy.lua`, `options.lua`
- `init.lua`, `lazyvim.json`, `lazy-lock.json`

**NEVER run `omarchy-nvim-setup`** on a customized config — it does `mv ~/.config/nvim ~/.config/nvim.backup.<date>` and wipes the user's 25+ custom plugins. Always cherry-pick individual files instead.

## CachyOS System Safety — Boot, Limine, and Btrfs

**This system runs CachyOS with Limine bootloader and Btrfs.** Upstream omarchy targets vanilla Arch with different defaults. Any merge changes touching the following areas require extra caution:

- **Limine** (`default/limine/`, `install/login/limine-snapper.sh`, migrations referencing limine) — CachyOS manages `/etc/default/limine` itself. Our fork comments out upstream's `KERNEL_CMDLINE` directives. Never uncomment or add kernel cmdline changes without asking the user.
- **Boot process** (`install/login/`, `install/preflight/`, `boot.sh`) — upstream assumes vanilla Arch boot flow. Our fork disables distro guards and limine checks. Review any changes here carefully.
- **Btrfs / Snapper** (`snapper` package, `limine-snapper-sync`, `disable-snapper.sh`) — upstream uses snapper for Btrfs snapshots; our fork disables it (`# [omarchy] snapper`). Never re-enable snapper or snapshot-related packages without asking.
- **Kernel packages** — upstream uses `linux`/`linux-headers`; our fork uses `linux-cachyos`/`linux-cachyos-headers`. Never swap these.

**Rule: If a merge introduces ANY changes to boot, limine, btrfs, snapper, or kernel packages — stop and ask the user before resolving.** Even if the change looks safe, the risk of an unbootable system is too high to assume.

## What NOT to Do

- Never force-push or rebase — this is a merge-based workflow
- Never delete `# [omarchy]` comments unless upstream also deleted the original line
- Never silently drop fork-specific scripts or packages
- Never apply config changes to `~/.config/` without user confirmation
- Never run `omarchy-update` non-interactively — it requires TTY confirmation
- Never accept upstream changes to limine, boot, btrfs, or kernel packages without explicit user approval
- Never let a destructive migration run without asking — migrations can silently uninstall packages or wipe `~/.config/` dirs
