# install_scripts

Shared, stamped shell templates for repos:
- install scripts
- GDExtension addon packaging
- CI workflows

A file managed by this repo is split at a `# ---- end config ----` marker: the repo's
copy owns the config block above the marker, this repo owns the body below it. To
propagate a change, edit the template here, then run the consumer repo's render
script. Never edit below the marker in a consumer repo; `--check` gates the drift.

## Layout

- `simple/stamp-template.sh` - content-agnostic config/body stamper. Everything else
  is policy layered on top of it.
- `simple/` - `install.sh` / `install.ps1` templates: download a release asset from
  GitHub, install to `BIN_DIR`, optionally fix PATH (with a prompt, safely under
  `curl | sh`).
- `gdext/` - `package.sh` (assemble a Godot addon zip from `bin/` + addon source) and
  `build.yml` (matrix scons build for macOS/Linux/Windows, package, release on tag).

## Using in a consumer repo

Clone this repo somewhere; override with `INSTALL_SCRIPTS_DIR`), then:

- installers: copy `simple/repo-render-entry.sh` into the repo as
  `render-installers.sh`, create `install.sh`/`install.ps1` containing just a config
  block and the marker, and run `./render-installers.sh` to receive the bodies.
- GDExtension addon: copy `gdext/repo-render-entry.sh` in as `render-gdext.sh`,
  bootstrap `package.sh` the same way (`ADDON_SRC`/`ADDON_DEST`/`VERSION_FILE`
  config block + marker), and run `./render-gdext.sh`. The workflow needs no config;
  zip and artifact names come from the GitHub repo name.

Both entry scripts take `--check` to verify instead of write; use it in a pre-tag
gate or CI to fail on drift.
