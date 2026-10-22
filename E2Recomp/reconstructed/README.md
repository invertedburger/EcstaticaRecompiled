# Reconstructed Build

Compileable reconstruction of `E2Recomp.exe` (32-bit Windows PE). This is a rebuildable scaffold, not a behavior-complete port.

## Files

- `E2Recomp_recon.c` / `E2Recomp_recon.h`: normalized Ghidra decompilation and declarations
- `E2Recomp_globals.c` / `E2Recomp_data_init.c`: recovered globals and data init
- `E2Recomp_stubs.c`: stubs for unresolved hardware / x87 / SIMD / helper symbols
- `Build-Reconstructed.ps1`: Windows build. MSVC x86 if Visual Studio is installed, otherwise a portable MinGW downloaded into `../.tools`
- `build.sh`: Linux cross-build of the same Windows exe. Uses `i686-w64-mingw32-gcc` if present, otherwise downloads MinGW into `../.tools`
- `E2Recomp_rebuilt.exe`: linked 32-bit Windows executable

## Build and run (Windows)

No project dependencies to install. If `cl.exe` is not available, the script downloads MinGW (about 200MB) into `E2Recomp/.tools`, which is gitignored.

```powershell
cd E2Recomp\reconstructed
.\Build-Reconstructed.ps1
.\E2Recomp_rebuilt.exe
```

The exe links only standard Windows libraries (`kernel32`, `user32`, `gdi32`, `winmm`, `comdlg32`). DirectDraw / DirectSound calls in this scaffold are stubbed in `E2Recomp_stubs.c`.

To force a specific Visual Studio environment:

```powershell
.\Build-Reconstructed.ps1 -VcVars32 "C:\Path\To\vcvars32.bat"
```

## Cross-build (Linux)

Produces the same Windows exe. Does not run the game.

```bash
cd E2Recomp/reconstructed
./build.sh
```

Copy `E2Recomp_rebuilt.exe` to Windows and launch it. The portable compiler downloaded by `build.sh` is the Ubuntu 24.04 MinGW package set. On other distros, install `gcc-mingw-w64-i686` and re-run; the script uses that compiler instead.

## Status

Links with MSVC x86 or MinGW i686. Stubs in `E2Recomp_stubs.c` must be replaced before runtime can match the original executable. Launching the current exe is expected to hit the crash logger in `E2Recomp_stubs.c` until those stubs are real.
