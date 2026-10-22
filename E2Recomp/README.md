# E2Recomp.exe Reconstruction

This directory contains a first-pass Ghidra decompilation of `C:\ecstatica2\E2Recomp.exe`.

## What Was Recovered

- `src/E2Recomp_decompiled.c`: Ghidra C-like output for 839 discovered functions.
- `src/e2recomp_types.h`: type shim for Ghidra primitive types.
- `reconstructed/E2Recomp_recon.c`: compileable normalized reconstruction.
- `reconstructed/E2Recomp_rebuilt.exe`: linked 32-bit rebuilt executable.
- `metadata/functions.tsv`: function address, generated name, body size, and decompile status.
- `metadata/symbols.tsv`: all symbols recovered by Ghidra, including imports and data labels.
- `metadata/references.tsv`: address references from the analyzed program.
- `../ghidra_project/E2RecompProject`: saved Ghidra project for interactive cleanup.
- `../ghidra_scripts/ExportDecomp.java`: reproducible headless export script.

## Binary Facts

- Format: 32-bit native PE executable.
- Image base: `0x00400000`.
- Entry RVA: `0x0006030e`.
- Entry VA: `0x0046030e`.
- Timestamp: `1997-10-09 19:10:32 UTC`.
- Subsystem: Windows GUI.
- CLI/.NET metadata: none.

Imported libraries observed by Ghidra:

- `COMDLG32.DLL`
- `DDRAW.DLL`
- `DSOUND.DLL`
- `GDI32.DLL`
- `KERNEL32.DLL`
- `MSACM32.DLL`
- `SIMD_W95.DLL`
- `USER32.DLL`
- `WINMM.DLL`

## Regenerate The Decompilation

From `C:\ecstatica2`:

```powershell
.\reverse\E2Recomp\tools\ReExport.ps1
```

Equivalent direct Ghidra command:

```powershell
& 'C:\Users\patte\QeffectsGL\reverse\ghidra_12.1_PUBLIC\support\analyzeHeadless.bat' `
  'C:\ecstatica2\reverse\ghidra_project' E2RecompProject `
  -import 'C:\ecstatica2\E2Recomp.exe' `
  -overwrite `
  -scriptPath 'C:\ecstatica2\reverse\ghidra_scripts' `
  -postScript ExportDecomp.java 'C:\ecstatica2\reverse\E2Recomp'
```

## Rebuild Status

The reconstruction compiles and links to a 32-bit Windows executable.

On Windows, from this repo:

```powershell
.\E2Recomp\reconstructed\Build-Reconstructed.ps1
.\E2Recomp\reconstructed\E2Recomp_rebuilt.exe
```

If Visual Studio is not installed, that script downloads a portable MinGW GCC into `E2Recomp/.tools` (not committed). On Ubuntu 24.04 the same exe can be cross-built with `reconstructed/build.sh`, which downloads MinGW the same way when `i686-w64-mingw32-gcc` is not already on `PATH`. The executable itself runs on Windows and uses only standard OS DLLs.

This is still not a clean original-source rebuild. Native PE decompilation recovers control flow and expressions, but not original headers, structs, source file layout, local names, comments, or exact runtime imports.

The current linked executable uses isolated stubs for unresolved x87, I/O-port, SIMD, and decompiler-helper symbols. Replace those stubs with real implementations/import bindings to move from "buildable" toward behavior-equivalent.

To make this rebuildable as maintainable C, the next reconstruction pass should:

1. Rename high-confidence functions using strings, imports, and call sites.
2. Recover global structs around dense regions such as `DAT_00479*`, `DAT_0047a*`, and `DAT_0063*`.
3. Replace absolute `DAT_` and `s_` labels with typed globals or resource blobs.
4. Add real prototypes before the first function body.
5. Split runtime/library-looking functions away from game code.
6. Compile frequently with a 32-bit Windows C compiler and fix type mismatches function by function.

The saved Ghidra project is the best place to do that cleanup because renames and types can then be exported repeatedly.
