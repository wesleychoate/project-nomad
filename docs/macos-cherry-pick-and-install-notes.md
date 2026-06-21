# macOS Support: Cherry-Pick & Mac Mini Install Notes

Notes from bringing macOS support into `wesleychoate/project-nomad` (fork of
`Crosstalk-Solutions/project-nomad`) and installing it on the Mac mini that
runs Ollama (`192.168.4.39`).

**Credit**: the entire macOS port — platform detection, native Ollama on
macOS instead of a Docker container, Apple Silicon/Metal GPU handling, and
the install-script refactor to support both Linux and macOS from one
codebase — is [Aaron Bailey](https://github.com/aaronbailey)'s work, not
mine. He did it on a plain clone rather than a GitHub fork, so it couldn't
be merged or credited automatically by GitHub the normal way. This branch
exists to carry his work forward against a much-diverged fork, fix a few
bugs that only showed up once it was actually tested on macOS hardware, and
hopefully get it proposed upstream properly someday. His original commit
(`3cd8cf59a88d77262d1cc0f052addc2c734f9ab` on
[aaronbailey/project-nomad-macos](https://github.com/aaronbailey/project-nomad-macos))
was cherry-picked with `git cherry-pick`, which preserves him as the commit
author — visible in `git log`/`git blame` on this branch, and will carry
through automatically if this is ever opened as a PR against upstream.

## Background

- `aaronbailey/project-nomad-macos` is a plain clone (not a GitHub fork) that
  branched off the upstream commit `8bb8b414f8c70419533aa1ca0cc50270c27edf35`
  (March 14) and added one commit making the project run on macOS:
  `3cd8cf59a88d77262d1cc0f052addc2c734f9ab` — "feat: add macOS support with
  platform detection and native Ollama".
- Our fork had diverged significantly from that March 14 point (GPU
  detection rewrite, ROCm/AMD support, etc.), so a straight merge wasn't an
  option — needed a cherry-pick of just that one commit.

## Cherry-pick steps

```bash
cd ~/repos/project-nomad
git remote add aaronbailey https://github.com/aaronbailey/project-nomad-macos.git
git fetch aaronbailey
git checkout -b macos-compat origin/main
git cherry-pick 3cd8cf59a88d77262d1cc0f052addc2c734f9ab
```

### Conflicts hit and how they were resolved

3 files conflicted (others applied cleanly):

- **`install/management_compose.yaml`** — mechanical. HEAD had hardcoded
  `/opt/project-nomad` paths with inline comments; incoming side had
  `${NOMAD_HOME:-/opt/project-nomad}` variable substitution. Resolution: kept
  the variable substitution, re-attached HEAD's comments. The new
  `OLLAMA_URL`/`NOMAD_PLATFORM` env vars and HEAD's `DISABLE_COMPRESSION` var
  weren't actually conflicting (different lines added in the same spot) —
  kept both.

- **`install/install_nomad.sh`** — most of the file's 3-way merge resolved
  automatically (git correctly interleaved `check_platform`,
  `ensure_docker_installed`, `get_local_ip`, `verify_gpu_setup` darwin
  branches, etc.). Eight remaining conflict blocks, each judged on its own:
  - Kept HEAD's `gpg`/whiptail dependency check in
    `ensure_dependencies_installed_linux` (incoming side was empty there).
  - `check_docker_compose` (HEAD) and `ensure_docker_installed_macos` /
    `ensure_ollama_installed_macos` (incoming) are three distinct functions
    that all get called later — kept all three, just had to fix brace
    placement after the merge.
  - Kept HEAD's MySQL-data-directory cleanup logic (prevents stale
    credentials from a previous install attempt) — incoming had nothing
    there.
  - **Dropped** `download_wait_for_it_script`, `download_entrypoint_script`,
    and `download_sidecar_files` entirely. These referenced
    `ENTRYPOINT_SCRIPT_URL` / `SIDECAR_UPDATER_DOCKERFILE_URL` /
    `SIDECAR_UPDATER_SCRIPT_URL`, none of which exist in our fork's constants
    anymore — confirmed `management_compose.yaml`'s `updater` service now
    pulls a prebuilt image (`ghcr.io/.../project-nomad-sidecar-updater:latest`)
    instead of building from a downloaded Dockerfile, and no service mounts
    `entrypoint.sh`/`wait-for-it.sh` anymore. Dead code from the old
    architecture.
  - In `verify_gpu_setup`, kept HEAD's comments and correctly-unescaped
    `grep -q "nvidia"` checks; incoming side had stray backslash-escaped
    quotes (`grep -q \"nvidia\"`) that looked like a bug from however that
    fork was edited.
  - Kept HEAD's GPU marker-file writing logic (`.nomad-gpu-type`,
    `.nomad-amd-gfx`) and AMD summary line in full — incoming's version was a
    simpler subset.
  - Pre-flight check: `check_is_debian_based` (HEAD) doesn't exist anymore as
    a function — its logic moved inside `check_platform`'s linux branch.
    Replaced the call with `check_platform`, kept `check_is_x86_64` but
    **gated it to Linux only** (it would otherwise print a scary "NOMAD only
    supports x86_64" warning on every normal Apple Silicon Mac, which defeats
    the purpose of this commit).
  - Final pre-flight/install sequence: kept both `check_docker_compose` and
    the darwin-gated `ensure_ollama_installed_macos` call.

- **`admin/app/services/system_service.ts`** — HEAD had replaced the old
  simple "check Docker for an nvidia runtime" logic with a much richer
  GPU-health system (Ollama log parsing, AMD/ROCm detection, KVStore marker
  lookups). The incoming commit's only contribution here was "skip GPU
  detection via Docker on macOS, since Ollama runs natively." Resolved by
  keeping HEAD's GPU-health logic essentially as-is, but adding an early
  Apple Silicon detection block before it:
  ```ts
  const nomadPlatform = process.env.NOMAD_PLATFORM || (process.platform === 'darwin' ? 'darwin' : 'linux')

  if (nomadPlatform === 'darwin' && os.arch === 'arm64') {
    graphics.controllers = [{
      model: 'Apple Silicon GPU (Metal/MPS)',
      vendor: 'Apple',
      bus: '',
      vram: 0,
      vramDynamic: true,
    }]
    gpuHealth = {
      status: 'ok',
      hasNvidiaRuntime: false,
      hasRocmRuntime: false,
      ollamaGpuAccessible: true,
    }
  }
  ```
  Because the Apple controller's vendor doesn't match the NVIDIA/AMD regex
  used later, and `graphics.controllers` is no longer empty, the existing
  Docker-based GPU probing skips itself naturally afterward — no further
  wrapping needed.

  **Bug caught after the cherry-pick landed**: the Apple Silicon `gpuHealth`
  assignment above was missing `hasRocmRuntime`, which is a *required* field
  on the `GpuHealthStatus` type (`admin/types/system.ts`). This would have
  failed `tsc`. Fixed in a separate follow-up commit (kept separate from the
  cherry-pick on purpose, so `03c89ca` stays an exact, recognizable
  cherry-pick of upstream's commit).

### `admin/app/services/docker_service.ts`

Applied with **no conflicts**. Extends `_detectGPUType()`'s return type with
`'apple_metal'` and adds an early return for `darwin`/`arm64` before the
Linux-only NVIDIA/ROCm toolkit checks.

## Resulting commits on `macos-compat`

```
03c89ca feat: add macOS support with platform detection and native Ollama   (cherry-pick)
3004b8b fix: add missing hasRocmRuntime field in Apple Silicon GPU health status
1be5f52 fix: macOS install hardening — root guard, tr locale, conditional sudo
```

## Pre-flight verification done before testing for real

- `bash -n` on every changed shell script — all passed.
- Hand-reviewed the TS diff (no `node_modules` installed in the dev
  environment used for review, so `tsc`/`npm run typecheck` wasn't run —
  worth doing once dependencies are installed).
- Reasoned through what `install_nomad.sh` actually *does* on a real
  machine before running it on the Mac mini that holds the real Ollama
  models: install dir is `~/project-nomad` (not `/opt/...`, no `sudo mkdir`
  needed), `OLLAMA_URL` is hardcoded to `http://host.docker.internal:11434`
  for darwin (so Ollama must run on the *same* host as Docker — confirmed
  this is why the Mac mini, not the Intel MacBook, is the right install
  target), and the Ollama-install step only runs if `ollama` isn't already
  on `PATH` (it was, so existing install/models were left untouched).

## Docker Compose v2 plugin gotcha (Colima + Homebrew docker CLI)

The Mac mini uses [Colima](https://github.com/abiosoft/colima) instead of
Docker Desktop, with `docker` installed via the Homebrew CLI-only formula.
`install_nomad.sh`'s `check_docker_compose` failed with:

```
Docker Compose v2 is not installed or not available as a Docker plugin.
This script requires 'docker compose' (v2), not 'docker-compose' (v1).
```

Root cause: the Docker CLI only looks for plugins in fixed paths (notably
`~/.docker/cli-plugins/`), and:

- `brew install docker` (CLI-only formula) does **not** include the compose
  plugin.
- `brew install docker-compose` installs the v2 plugin binary, but Homebrew
  drops it at
  `$(brew --prefix docker-compose)/lib/docker/cli-plugins/docker-compose` —
  it does **not** symlink it into `~/.docker/cli-plugins/` automatically.
  That directory didn't even exist yet on this machine.

Fix:

```bash
brew install docker-compose
mkdir -p ~/.docker/cli-plugins
ln -sfn "$(brew --prefix docker-compose)/lib/docker/cli-plugins/docker-compose" \
  ~/.docker/cli-plugins/docker-compose
docker compose version   # should now print "Docker Compose version 5.x.x"
```

After this, `docker compose version` resolved and `install_nomad.sh`'s
`check_docker_compose` passed.

## Confirmed Colima compatibility (for reference)

Before running the real install, verified Colima satisfies everything the
macOS install path assumes:

```bash
colima status                 # confirms colima running, runtime: docker
docker info                   # succeeds — same check the script does
curl -s http://localhost:11434/api/tags   # confirms host Ollama reachable

# Confirms host.docker.internal resolves correctly *from inside a container*
# and reaches the host's Ollama — this is the one thing that's historically
# flaky on Colima vs. Docker Desktop:
docker run --rm alpine sh -c \
  "apk add --no-cache curl -q >/dev/null 2>&1; \
   getent hosts host.docker.internal; \
   curl -s -o /dev/null -w 'HTTP_STATUS:%{http_code}\n' http://host.docker.internal:11434/api/tags"
# -> 192.168.5.2  host.docker.internal  host.docker.internal
# -> HTTP_STATUS:200
```

All green, so no script changes were needed for Colima — the "Docker
Desktop is required" wording in `ensure_docker_installed_macos` is just
stale copy text; the actual checks (`command -v docker`, `docker info`) are
generic and work fine against any docker-compatible backend.

## Real install attempt — bugs found and fixed

### `tr: Illegal byte sequence` silently broke password generation

First real run got all the way through container image pulls, then
`nomad_mysql` came up unhealthy. Its logs said:

```
[ERROR] [Entrypoint]: Database is uninitialized and password option is not specified
```

Root cause: `generateRandomPass()` did:

```bash
password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length")
```

On macOS, `tr` running in a UTF-8 locale chokes on raw binary bytes from
`/dev/urandom` ("Illegal byte sequence" on stderr) and truncates its output
early. Checking the generated `compose.yml` confirmed it:

```
APP_KEY=                      # empty — should be 32 chars
MYSQL_ROOT_PASSWORD=          # empty
DB_PASSWORD=CQ                # truncated to 2 chars
MYSQL_PASSWORD=CQ             # truncated to 2 chars
```

Fix — force the C locale so `tr` treats input as raw bytes:

```bash
password=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length")
```

This is a real cross-platform bug in upstream's existing `install_nomad.sh`,
unrelated to the cherry-pick itself — it just never got exercised on macOS
until now. Fixed in commit `1be5f52`.

To recover from a broken state caused by this: `docker compose -p
project-nomad -f ~/project-nomad/compose.yml --profile darwin down -v` to
tear down the half-initialized containers/volumes, then re-run the
installer once the fix is in place.

### Accidentally running the installer with `sudo` on macOS

After fixing the password bug, the second run completed, but two things
looked wrong:

```
Warning: Expecting a LaunchDaemons path since the command was run as root.
Got LaunchAgents instead.
```

...plus a macOS "bash wants to run in the background" notification.

Root cause: the installer was run with `sudo` (a habit carried over from
the Linux instructions, where `sudo` is genuinely required). On macOS
nothing in this script needs root — running as root made `create_nomad_directory`
write every file under `~/project-nomad` as `root:staff`, and made the
disk-collector's `launchctl load` target the wrong launchd domain (root's
system domain instead of the per-user GUI domain), so the job never
actually started even though the plist file got dropped into
`~/Library/LaunchAgents`.

Confirmed Docker itself was unaffected — `docker ps` as the normal user
showed all 6 containers running healthy regardless of which user ran
`docker compose up`, since Colima's socket access doesn't care about the
caller's euid.

Recovery steps used (no full re-run needed since containers were fine):

```bash
# Fix ownership of everything the script wrote while running as root
sudo chown -R $(whoami):staff ~/project-nomad

# Remove the root-owned plist — it was written into a per-user path but
# never actually loaded into any launchd domain, so no unload needed
sudo rm -f ~/Library/LaunchAgents/com.projectnomad.disk-collector.plist

# Recreate it as yourself (no sudo) so it lands in the right domain
cat > ~/Library/LaunchAgents/com.projectnomad.disk-collector.plist <<'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.projectnomad.disk-collector</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/wes/project-nomad/collect_disk_info.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/wes/project-nomad/storage/logs/disk-collector.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/wes/project-nomad/storage/logs/disk-collector-error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>NOMAD_HOME</key>
        <string>/Users/wes/project-nomad</string>
    </dict>
</dict>
</plist>
PLISTEOF
launchctl load ~/Library/LaunchAgents/com.projectnomad.disk-collector.plist
launchctl list | grep nomad   # should now list it cleanly
```

Hardened the script itself so this can't happen to the next person
(commit `1be5f52`):

- `check_platform()` now exits immediately with a clear error if run as
  root (`$EUID -eq 0`) on macOS, telling the user to re-run without `sudo`.
- The MySQL data-dir cleanup in `download_management_compose_file()` — the
  one step that legitimately needs `sudo` on Linux — is now gated to only
  use `sudo` when `$PLATFORM == "linux"`, since it was the likely reason
  someone would reach for `sudo bash install_nomad.sh` on macOS in the
  first place.

## Final result

Installed and verified on the Mac mini (`192.168.4.39`):

```bash
curl -s -o /dev/null -w "HTTP_STATUS:%{http_code}\n" http://localhost:8080/api/health
# -> HTTP_STATUS:200

docker ps --filter "name=nomad" --format "table {{.Names}}\t{{.Status}}"
# nomad_admin            Up (healthy)
# nomad_redis            Up (healthy)
# nomad_mysql            Up (healthy)
# nomad_dozzle           Up
# nomad_updater          Up
# nomad_disk_collector   Up
```

GPU verification correctly detected Apple Silicon and confirmed Metal/MPS
acceleration for the AI Assistant. Dashboard reachable at
`http://192.168.4.39:8080`.

## Bug found during a real multi-hour indexing run: Kiwix/Qdrant storage paths

After a long Comprehensive-tier content download + RAG indexing run,
`nomad_kiwix_server` was crash-looping with:

```
ERROR: Failed to load the XML library file '/data/kiwix-library.xml'.
```

`nomad_admin` was correctly writing `kiwix-library.xml` and downloaded ZIM
files to the real host disk (`~/project-nomad/storage/zim`) — its bind mount
goes through `management_compose.yaml`, which got the `${NOMAD_HOME}`
treatment back in the original cherry-pick. But `nomad_kiwix_server` and
`nomad_qdrant` aren't defined in `management_compose.yaml` at all — they're
created dynamically by the admin app itself (same mechanism as the AI
Assistant/Ollama container), with their bind-mount paths read once at
**database seed time** from `service_seeder.ts`:

```ts
private static NOMAD_STORAGE_ABS_PATH = env.get(
  'NOMAD_STORAGE_PATH',
  '/opt/project-nomad/storage'
)
```

Nothing in `management_compose.yaml` ever set `NOMAD_STORAGE_PATH` — the
original macOS commit added `NOMAD_PLATFORM` and `OLLAMA_URL` to the admin
container's environment but missed this one. So the seeder always fell back
to `/opt/project-nomad/storage`, which — same root cause as the very first
storage bug in this doc — isn't a path Colima shares with the host, so it
silently got created *inside the Colima VM's own disk* instead. Kiwix and
Qdrant ended up reading/writing storage completely disconnected from where
`nomad_admin` puts everything else. Because `service_seeder.ts` only inserts
rows for service names that don't already exist (never updates), simply
fixing the env var doesn't retroactively fix an already-seeded database —
fixing this on a live install requires a direct correction of the
`container_config` JSON already baked into the `services` table, not just a
script/compose fix.

Fixed in two places:
- `management_compose.yaml`: added `NOMAD_STORAGE_PATH=${NOMAD_HOME:-/opt/project-nomad}/storage`
  to the admin container's environment, so the seeder gets the right value
  on first boot for any future install.
- `service_seeder.ts`: hardened the fallback (if `NOMAD_STORAGE_PATH` is
  somehow still unset) to be platform-aware instead of always assuming
  Linux, mirroring the `NOMAD_PLATFORM` fallback pattern already used in
  `docker_service.ts`/`system_service.ts`.

Live-system recovery (no data loss — ZIM downloads were already on the real
disk; only ~811MB of Qdrant embeddings needed moving):
1. Migrate the misplaced Qdrant data out of the Colima VM to the real host
   path via a throwaway helper container that bind-mounts both the
   VM-internal path and the real `~/project-nomad/storage` path at once
   (the only way to bridge an arbitrary VM-internal path and a
   virtiofs-shared host path, since Colima only shares `/Users` with the
   guest by default).
2. Directly `UPDATE` the `Binds` path inside the `container_config` JSON
   column for the `kiwix` and `qdrant` rows in the `services` table.
3. Recreate both containers so they pick up the corrected bind mounts.
