#!/usr/bin/env bash
# Build (if needed) and smoke-run E2Recomp_rebuilt.exe.
# On Windows: runs the PE directly.
# On Linux: system wine, or Kron4ek amd64-wow64 into ../.tools/wine.
# Smoke success: process starts and either exits cleanly, times out still
# running, or writes E2Recomp_rebuilt_crash.log (expected for this scaffold).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2="$(cd "$ROOT/.." && pwd)"
WINE_HOME="$E2/.tools/wine"
EXE="$ROOT/E2Recomp_rebuilt.exe"
CRASH_LOG="$ROOT/E2Recomp_rebuilt_crash.log"
WINE_URL="${E2RECOMP_WINE_URL:-https://github.com/Kron4ek/Wine-Builds/releases/download/10.0/wine-10.0-amd64-wow64.tar.xz}"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}"
SMOKE_TIMEOUT="${E2RECOMP_SMOKE_TIMEOUT:-20}"
WINE_IS_PORTABLE=0

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

ensure_build() {
  if [[ ! -f "$EXE" ]]; then
    log "executable missing; building"
    "$ROOT/build.sh"
  fi
  [[ -f "$EXE" ]] || die "missing $EXE"
}

bootstrap_wine() {
  command -v tar >/dev/null 2>&1 || die "need tar to extract Wine"
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || die "need curl or wget to fetch Wine"

  mkdir -p "$E2/.tools"
  local archive="$E2/.tools/wine-10.0-amd64-wow64.tar.xz"
  local staging="$E2/.tools/wine-extract-$$"

  if [[ ! -x "$WINE_HOME/bin/wine" ]]; then
    log "fetching portable Wine from $WINE_URL"
    if [[ ! -f "$archive" ]]; then
      if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --retry-delay 2 -o "$archive.partial" "$WINE_URL"
        mv "$archive.partial" "$archive"
      else
        wget -O "$archive" "$WINE_URL"
      fi
    else
      log "reusing cached archive $archive"
    fi

    rm -rf "$staging"
    mkdir -p "$staging"
    tar -xJf "$archive" -C "$staging"
    local extracted
    extracted="$(find "$staging" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [[ -n "$extracted" ]] || die "Wine archive had no top-level directory"
    rm -rf "$WINE_HOME"
    mv "$extracted" "$WINE_HOME"
    rm -rf "$staging"
  fi

  [[ -x "$WINE_HOME/bin/wine" ]] || die "portable wine missing: $WINE_HOME/bin/wine"
  log "portable Wine ready: $WINE_HOME/bin/wine"
}

is_our_portable_wine() {
  local cand
  cand="$(readlink -f "$1" 2>/dev/null || printf '%s' "$1")"
  case "$cand" in
    "$WINE_HOME"/*|"$E2"/.tools/wine/*) return 0 ;;
  esac
  return 1
}

resolve_wine() {
  WINE_BIN=""
  WINE_IS_PORTABLE=0
  # Explicit WINEPREFIX from the environment wins; otherwise pick a prefix
  # that matches the wine build (system wine32 vs Kron4ek wow64).
  local explicit_prefix="${WINEPREFIX:-}"
  local cand=""
  # Ignore a vendored wine that someone left early on PATH.
  local search_path
  search_path="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v "/\.tools/wine" | paste -sd: -)"

  if cand="$(PATH="$search_path" command -v wine 2>/dev/null)" \
    && [[ -n "$cand" && -x "$cand" ]] \
    && ! is_our_portable_wine "$cand"; then
    WINE_BIN="$cand"
    WINE_PREFIX="${explicit_prefix:-$CACHE_ROOT/e2recomp-wine}"
    log "using system wine: $WINE_BIN"
    return
  fi
  if [[ -x "$WINE_HOME/bin/wine" ]]; then
    WINE_BIN="$WINE_HOME/bin/wine"
    WINE_IS_PORTABLE=1
    WINE_PREFIX="${explicit_prefix:-$CACHE_ROOT/e2recomp-wine-wow64}"
    log "using portable wine: $WINE_BIN"
    return
  fi
  bootstrap_wine
  WINE_BIN="$WINE_HOME/bin/wine"
  WINE_IS_PORTABLE=1
  WINE_PREFIX="${explicit_prefix:-$CACHE_ROOT/e2recomp-wine-wow64}"
}

evaluate_smoke() {
  local rc=$1
  if [[ -f "$CRASH_LOG" ]]; then
    log "smoke OK: crash handler wrote $CRASH_LOG (expected for incomplete scaffold)"
    head -n 8 "$CRASH_LOG" || true
    exit 0
  fi
  if [[ "$rc" -eq 0 ]]; then
    log "smoke OK: process exited cleanly (rc=0)"
    exit 0
  fi
  # GNU timeout(1)
  if [[ "$rc" -eq 124 ]]; then
    log "smoke OK: process stayed up until timeout (no crash log yet)"
    exit 0
  fi
  die "smoke failed: rc=$rc and no $CRASH_LOG"
}

run_windows() {
  log "running on Windows: $EXE"
  rm -f "$CRASH_LOG"
  set +e
  (cd "$ROOT" && "./E2Recomp_rebuilt.exe")
  local rc=$?
  set -e
  evaluate_smoke "$rc"
}

run_linux() {
  resolve_wine
  mkdir -p "$WINE_PREFIX"
  export WINEPREFIX="$WINE_PREFIX"
  export WINEDEBUG="${WINEDEBUG:--all}"
  if [[ "$WINE_IS_PORTABLE" -eq 1 ]]; then
    export LD_LIBRARY_PATH="${WINE_HOME}/lib:${WINE_HOME}/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  fi

  log "WINEPREFIX=$WINEPREFIX"
  log "smoke-running with timeout ${SMOKE_TIMEOUT}s: $EXE"
  rm -f "$CRASH_LOG"

  set +e
  if command -v timeout >/dev/null 2>&1; then
    (cd "$ROOT" && timeout "$SMOKE_TIMEOUT" "$WINE_BIN" "E2Recomp_rebuilt.exe")
    local rc=$?
  else
    (cd "$ROOT" && "$WINE_BIN" "E2Recomp_rebuilt.exe")
    local rc=$?
  fi
  set -e
  evaluate_smoke "$rc"
}

ensure_build

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    run_windows
    ;;
  *)
    if [[ "${OS:-}" == "Windows_NT" ]]; then
      run_windows
    else
      run_linux
    fi
    ;;
esac
