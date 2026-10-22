# Build E2Recomp_rebuilt.exe on Windows.
# Uses MSVC x86 when Visual Studio is installed. Otherwise downloads a portable
# MinGW GCC into ..\.tools (no system install) and cross-compiles the same way.
# The result is a 32-bit Windows GUI executable. Run it with .\E2Recomp_rebuilt.exe
param(
    [string]$VcVars32 = ""
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$e2 = Split-Path -Parent $root
$srcRoot = Join-Path $e2 "src"
$tools = Join-Path $e2 ".tools"
$out = Join-Path $root "E2Recomp_rebuilt.exe"

function Find-VcVars32 {
    if ($VcVars32 -and (Test-Path $VcVars32)) { return $VcVars32 }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { return $null }
    $install = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $install) { return $null }
    $candidate = Join-Path $install "VC\Auxiliary\Build\vcvars32.bat"
    if (Test-Path $candidate) { return $candidate }
    return $null
}

function Build-Msvc([string]$vars) {
    Write-Host "using MSVC: $vars"
    $units = @("E2Recomp_recon", "E2Recomp_globals", "E2Recomp_data_init", "E2Recomp_stubs")
    foreach ($unit in $units) {
        cmd /c "call `"$vars`" >nul && cl /nologo /w /std:clatest /TC /c `"$root\$unit.c`" /I `"$root`" /I `"$srcRoot`" /Fo:`"$root\$unit.obj`""
        if ($LASTEXITCODE -ne 0) { throw "cl failed on $unit.c" }
    }
    $objs = ($units | ForEach-Object { "`"$root\$_.obj`"" }) -join " "
    cmd /c "call `"$vars`" >nul && link /nologo /SUBSYSTEM:WINDOWS /ENTRY:entry /BASE:0x10000000 /DYNAMICBASE:NO /NXCOMPAT:NO /MAP:`"$root\E2Recomp_rebuilt.map`" /OUT:`"$out`" $objs user32.lib gdi32.lib kernel32.lib winmm.lib comdlg32.lib dsound.lib ddraw.lib msacm32.lib"
    if ($LASTEXITCODE -ne 0) { throw "link failed" }
}

function Ensure-Winlibs {
    $gcc = Join-Path $tools "winlibs\mingw32\bin\i686-w64-mingw32-gcc.exe"
    if (Test-Path $gcc) { return $gcc }
    New-Item -ItemType Directory -Force -Path $tools | Out-Null
    $zip = Join-Path $tools "winlibs-i686.zip"
    $url = "https://github.com/brechtsanders/winlibs_mingw/releases/download/13.2.0posix-17.0.6-11.0.1-msvcrt-r5/winlibs-i686-posix-dwarf-gcc-13.2.0-mingw-w64msvcrt-11.0.1-r5.zip"
    if (-not (Test-Path $zip)) {
        Write-Host "Downloading portable MinGW i686 (no Visual Studio required)..."
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    }
    $dest = Join-Path $tools "winlibs"
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    Expand-Archive -Path $zip -DestinationPath $dest
    if (-not (Test-Path $gcc)) { throw "MinGW gcc not found at $gcc" }
    return $gcc
}

function Build-Mingw([string]$gcc) {
    Write-Host "using MinGW: $gcc"
    $units = @("E2Recomp_recon", "E2Recomp_globals", "E2Recomp_data_init", "E2Recomp_stubs")
    foreach ($unit in $units) {
        & $gcc -c -w -std=gnu11 -I"$root" -I"$srcRoot" "$root\$unit.c" -o "$root\$unit.o"
        if ($LASTEXITCODE -ne 0) { throw "gcc failed on $unit.c" }
    }
    $objs = $units | ForEach-Object { "$root\$_.o" }
    & $gcc -o $out @objs -nostartfiles -Wl,--subsystem,windows -Wl,-e,_entry -Wl,--image-base,0x10000000 -luser32 -lgdi32 -lkernel32 -lwinmm -lcomdlg32 -ldsound -lddraw -lmsacm32
    if ($LASTEXITCODE -ne 0) { throw "gcc link failed" }
}

$vars = Find-VcVars32
if ($vars) {
    Build-Msvc $vars
} else {
    $gcc = Ensure-Winlibs
    Build-Mingw $gcc
}

Write-Host "built $out"
Write-Host "Run on Windows: .\$([IO.Path]::GetFileName($out))"
