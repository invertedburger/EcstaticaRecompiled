#!/usr/bin/env bash
# Cross-build E2Recomp_rebuilt.exe (32-bit Windows PE) on Linux.
# Uses i686-w64-mingw32-gcc if it is already on PATH. Otherwise downloads a
# portable MinGW GCC into ../.tools (nothing is installed system-wide).
# The executable runs on Windows. It does not run natively on Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2="$(cd "$ROOT/.." && pwd)"
TOOLS="$E2/.tools/mingw-gcc"
PREFIX="$TOOLS/root"
HOSTLIBS="$TOOLS/hostlibs"
UBUNTU="${E2_UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}"

log() { printf '%s\n' "$*"; }

extract_deb() {
  local deb="$1" dest="$2"
  mkdir -p "$dest"
  if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb -x "$deb" "$dest"
    return
  fi
  local tmp
  tmp="$(mktemp -d)"
  (cd "$tmp" && ar x "$deb")
  local data
  data="$(find "$tmp" -maxdepth 1 -name 'data.tar*' | head -1)"
  tar -C "$dest" -xf "$data"
  rm -rf "$tmp"
}

download() {
  local url="$1" dest="$2"
  if [[ -s "$dest" ]]; then
    return
  fi
  log "fetch $url"
  curl -fL --retry 3 --retry-delay 2 -o "$dest.partial" "$url"
  mv "$dest.partial" "$dest"
}

ensure_vendor_gcc() {
  local gcc="$PREFIX/usr/bin/i686-w64-mingw32-gcc"
  if [[ -x "$gcc" ]]; then
    return
  fi
  mkdir -p "$TOOLS/debs" "$PREFIX"
  local -a debs=(
    "pool/universe/b/binutils-mingw-w64/binutils-mingw-w64-i686_2.41.90.20240122-1ubuntu1+11.4_amd64.deb"
    "pool/universe/g/gcc-mingw-w64/gcc-mingw-w64-base_13.2.0-6ubuntu1+26.1_amd64.deb"
    "pool/universe/g/gcc-mingw-w64/gcc-mingw-w64-i686-win32_13.2.0-6ubuntu1+26.1_amd64.deb"
    "pool/universe/g/gcc-mingw-w64/gcc-mingw-w64-i686-win32-runtime_13.2.0-6ubuntu1+26.1_amd64.deb"
    "pool/universe/m/mingw-w64/mingw-w64-common_11.0.1-3build1_all.deb"
    "pool/universe/m/mingw-w64/mingw-w64-i686-dev_11.0.1-3build1_all.deb"
  )
  local rel name dest
  for rel in "${debs[@]}"; do
    name="$(basename "$rel")"
    dest="$TOOLS/debs/$name"
    download "$UBUNTU/$rel" "$dest"
    extract_deb "$dest" "$PREFIX"
  done
  (
    cd "$PREFIX/usr/bin"
    local t src dst
    for t in gcc g++ cpp gcc-ar gcc-nm gcc-ranlib; do
      src="i686-w64-mingw32-${t}-win32"
      dst="i686-w64-mingw32-${t}"
      if [[ -e "$src" && ! -e "$dst" ]]; then
        ln -sf "$src" "$dst"
      fi
    done
  )
}

ensure_hostlibs() {
  local cc1
  cc1="$(find "$PREFIX/usr/lib/gcc/i686-w64-mingw32" -name cc1 -type f | head -1)"
  if [[ -z "$cc1" ]]; then
    log "warning: cc1 not found; skipping host library check"
    return
  fi
  if LD_LIBRARY_PATH="${HOSTLIBS}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$cc1" | grep -q 'not found'; then
    mkdir -p "$TOOLS/debs" "$HOSTLIBS" "$TOOLS/hostlibs-root"
    local -a libs=(
      "pool/main/i/isl/libisl23_0.26-3build1.1_amd64.deb"
      "pool/main/m/mpclib3/libmpc3_1.3.1-1build1.1_amd64.deb"
      "pool/main/m/mpfr4/libmpfr6_4.2.1-1build1.1_amd64.deb"
      "pool/main/g/gmp/libgmp10_6.3.0+dfsg-2ubuntu6.1_amd64.deb"
      "pool/main/libz/libzstd/libzstd1_1.5.5+dfsg2-2build1.1_amd64.deb"
      "pool/main/z/zlib/zlib1g_1.3.dfsg-3.1ubuntu2.2_amd64.deb"
      "pool/main/g/gcc-14/libstdc++6_14.2.0-4ubuntu2~24.04.1_amd64.deb"
      "pool/main/g/gcc-14/libgcc-s1_14.2.0-4ubuntu2~24.04.1_amd64.deb"
    )
    local rel name dest
    for rel in "${libs[@]}"; do
      name="$(basename "$rel")"
      dest="$TOOLS/debs/$name"
      download "$UBUNTU/$rel" "$dest"
      extract_deb "$dest" "$TOOLS/hostlibs-root"
    done
    find "$TOOLS/hostlibs-root" -type f \( -name '*.so' -o -name '*.so.*' \) -exec cp -a {} "$HOSTLIBS/" \;
  fi
  if [[ -d "$HOSTLIBS" ]]; then
    export LD_LIBRARY_PATH="${HOSTLIBS}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  fi
}

pick_gcc() {
  local have_system=0
  if command -v i686-w64-mingw32-gcc >/dev/null 2>&1; then
    have_system=1
  fi
  if [[ "${E2_FORCE_VENDOR:-}" == "1" || "$have_system" -eq 0 ]]; then
    if [[ "$have_system" -eq 0 ]]; then
      log "i686-w64-mingw32-gcc not on PATH; fetching portable MinGW into $TOOLS"
    else
      log "using portable MinGW in $TOOLS"
    fi
    ensure_vendor_gcc
    ensure_hostlibs
    export PATH="$PREFIX/usr/bin:$PATH"
  else
    log "using $(command -v i686-w64-mingw32-gcc)"
  fi
}

pick_gcc
command -v i686-w64-mingw32-gcc >/dev/null
i686-w64-mingw32-gcc -dumpmachine | grep -q '^i686-w64-mingw32'

log "compiling"
i686-w64-mingw32-gcc -c -w -std=gnu11 -I"$ROOT" -I"$E2/src" \
  "$ROOT/E2Recomp_recon.c" -o "$ROOT/E2Recomp_recon.o"
i686-w64-mingw32-gcc -c -w -std=gnu11 -I"$ROOT" -I"$E2/src" \
  "$ROOT/E2Recomp_globals.c" -o "$ROOT/E2Recomp_globals.o"
i686-w64-mingw32-gcc -c -w -std=gnu11 -I"$ROOT" -I"$E2/src" \
  "$ROOT/E2Recomp_data_init.c" -o "$ROOT/E2Recomp_data_init.o"
i686-w64-mingw32-gcc -c -w -std=gnu11 -I"$ROOT" -I"$E2/src" \
  "$ROOT/E2Recomp_stubs.c" -o "$ROOT/E2Recomp_stubs.o"

log "linking $ROOT/E2Recomp_rebuilt.exe"
i686-w64-mingw32-gcc -o "$ROOT/E2Recomp_rebuilt.exe" \
  "$ROOT/E2Recomp_recon.o" "$ROOT/E2Recomp_globals.o" \
  "$ROOT/E2Recomp_data_init.o" "$ROOT/E2Recomp_stubs.o" \
  -nostartfiles \
  -Wl,--subsystem,windows \
  -Wl,-e,_entry \
  -Wl,--image-base,0x10000000 \
  -luser32 -lgdi32 -lkernel32 -lwinmm -lcomdlg32 -ldsound -lddraw -lmsacm32

log "built $ROOT/E2Recomp_rebuilt.exe"
log "Run it on Windows:  .\\E2Recomp_rebuilt.exe"
log "It links only standard Windows DLLs (kernel32, user32, gdi32, winmm, comdlg32)."
