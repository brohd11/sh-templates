#!/usr/bin/env bash
# Source this file, then call install_local_binary BINARY_PATH [BIN_DIR].
# Symlink an already-built executable into BIN_DIR (default: ~/.local/bin).
# The link uses an absolute source path; sourcing and calling preserve the caller's cwd.

install_local_binary() (
  if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ -z "${1:-}" ]; then
    echo "usage: install_local_binary BINARY_PATH [BIN_DIR]" >&2
    return 2
  fi

  local binary=$1
  local bin_dir=${2:-"$HOME/.local/bin"}
  local binary_dir
  if [ ! -f "$binary" ] || [ ! -x "$binary" ]; then
    echo "error: $binary not found or not executable -- build it first" >&2
    return 1
  fi
  binary_dir=$(cd "$(dirname "$binary")" && pwd) || return 1
  binary="$binary_dir/$(basename "$binary")"

  mkdir -p "$bin_dir" || return 1
  if [ -d "$bin_dir/$(basename "$binary")" ] && [ ! -L "$bin_dir/$(basename "$binary")" ]; then
    echo "error: $bin_dir/$(basename "$binary") is a directory" >&2
    return 1
  fi
  # -n replaces an existing symlink instead of following it into a directory.
  ln -sfn "$binary" "$bin_dir/$(basename "$binary")"
)
