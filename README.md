# sh-templates

Shared, stamped shell templates for repos, vendored as a submodule:
- install scripts
- Go build and release makefiles
- GDExtension addon packaging
- CI workflows

Installers, package scripts, and makefiles are split at a `# ---- end config ----` marker: the repo's
copy owns the config block above the marker, this repo owns the body below it. To
propagate a change, edit the template here, then run the consumer repo's render
script. Never edit below the marker in a consumer repo; `--check` gates the drift.
Workflows have no per-repo config and are copied byte-identically from their templates.

## Layout

- `common/stamp-template.sh` - content-agnostic config/body stamper. Everything else
  is policy layered on top of it, so both domains below share this one primitive.
- `go/` - the Go-binary domain: `install.sh` / `install.ps1` templates that download a
  release asset from GitHub, install to `BIN_DIR`, and optionally fix PATH (with a
  prompt, safely under `curl | sh`), plus a shared `makefile` and `test.yml` /
  `release.yml` workflows. Tests run on Linux and Windows; releases run `make package`
  and upload `dist/*` on version tags. `render-target.sh` handles every Go file;
  `templates/` holds templates and the entry script copied into consumer repos,
  while `utils/` holds the local-install function library.
- `gdext/` - `package.sh` (stage a Godot addon from `bin/` + addon source and create
  its release zip) and `build.yml` (matrix scons build for macOS/Linux/Windows,
  package, release on tag).

## Using in a consumer repo

Add this repo as a submodule at the repo root, so the renderer is pinned by SHA
alongside the code it renders:

```
git submodule add https://github.com/brohd11/sh-templates.git
```

Then:

- Go installers, makefile, and workflows: copy `go/templates/repo-render-entry.sh` as `render-go.sh`.
  Create `install.sh`/`install.ps1` containing their config blocks and the marker.
  Create `makefile` with `APP_NAME` (matching the installer's `BINARY`), `VERSION_PKG`
  (`main` or the import path declaring `version`), `PLATFORMS`, and the config marker.
  Run `./render-go.sh` to render all five targets. Libraries can
  select only `.github/workflows/test.yml` in the entry script's `TARGETS` array.
  For a repo tracking `Makefile`, use that exact spelling in `TARGETS`; the renderer
  accepts both `makefile` and `Makefile`.
  Existing workspaces can call `go/render-target.sh [--check] TARGET` from their own
  target-discovery loops. Installer checks remain separate from CI and `make package`.
- GDExtension addon: copy `gdext/repo-render-entry.sh` in as `render-gdext.sh`,
  bootstrap `package.sh` the same way
  (`ADDON_SRC`/`ADDON_DEST`/`VERSION_FILE`/`RELEASE_NAME` config block + marker), and
  run `./render-gdext.sh`. `build/` is the staged Godot project tree and `dist/`
  contains the canonical `$RELEASE_NAME-v<VERSION>.zip`; the byte-identical workflow
  uploads that zip and publishes it on tag pushes.

All entry scripts take `--check` to verify instead of write; use it in a pre-tag
gate or CI to fail on drift. A fresh clone needs
`git submodule update --init sh-templates` before rendering.

## Installing a local Go build

`go/utils/install-local.sh` is a function library, not a stamped per-repo script:

```bash
source sh-templates/go/utils/install-local.sh
make
binary=$(make --no-print-directory -s binary-path)
install_local_binary "$binary"
```

`install_local_binary BINARY_PATH [BIN_DIR]` links the built executable into
`~/.local/bin` by default. It resolves the source to an absolute path and preserves
the caller's working directory. The makefile's `binary-path` target reports the
host executable path using the repo's configured app name and build directory.
