# Reconstructed Build

Compileable reconstruction of `E2Recomp.exe` (32-bit Windows PE). This is a rebuildable scaffold, not a behavior-complete port.

## Files

- `E2Recomp_recon.c` / `E2Recomp_recon.h`: normalized Ghidra decompilation and declarations
- `E2Recomp_globals.c` / `E2Recomp_data_init.c`: recovered globals and data init
- `E2Recomp_stubs.c`: stubs for unresolved hardware / x87 / SIMD / helper symbols
- `Build-Reconstructed.ps1`: Windows build. MSVC x86 if Visual Studio is installed, otherwise a portable MinGW downloaded into `../.tools`
- `build.sh`: Linux cross-build of the same Windows exe. Uses `i686-w64-mingw32-gcc` if present, otherwise downloads MinGW into `../.tools`
- `run.sh`: build if needed, then smoke-run (Windows native, or Wine on Linux)
- `E2Recomp_rebuilt.exe`: linked 32-bit Windows executable

## Build and run (Windows)

No project dependencies to install. If `cl.exe` is not available, the script downloads MinGW (about 200MB) into `E2Recomp/.tools`, which is gitignored.

```powershell
cd E2Recomp\reconstructed
.\Build-Reconstructed.ps1
.\E2Recomp_rebuilt.exe
# or: bash .\run.sh   (Git Bash / WSL)
```

The exe links only standard Windows libraries (`kernel32`, `user32`, `gdi32`, `winmm`, `comdlg32`). DirectDraw / DirectSound calls in this scaffold are stubbed in `E2Recomp_stubs.c`.

To force a specific Visual Studio environment:

```powershell
.\Build-Reconstructed.ps1 -VcVars32 "C:\Path\To\vcvars32.bat"
```

## Build and smoke (Linux, clean machine)

No system MinGW or Wine required. Toolchains land in `E2Recomp/.tools/` (gitignored).

```bash
cd E2Recomp/reconstructed
./build.sh    # system i686-w64-mingw32-gcc, or Ubuntu mingw debs → ../.tools/mingw-gcc
./run.sh      # builds if needed; system wine or Kron4ek wow64 → ../.tools/wine
```

`run.sh` defaults `WINEPREFIX` to `$HOME/.cache/e2recomp-wine` (system wine) or `$HOME/.cache/e2recomp-wine-wow64` (portable Kron4ek). Do not point it at an unowned `/tmp` prefix.

Smoke success means the PE starts and either exits cleanly, stays up until the timeout, or writes `E2Recomp_rebuilt_crash.log` (expected AV crash handler for this incomplete scaffold).

Optional: install `g++-mingw-w64-i686` / `wine` via apt to skip downloads. Force the vendored compiler with `E2_FORCE_VENDOR=1 ./build.sh`.

## Status

Links with MSVC x86 or MinGW i686. Stubs in `E2Recomp_stubs.c` must be replaced before runtime can match the original executable. Launching the current exe is expected to hit the crash logger in `E2Recomp_stubs.c` until those stubs are real.
