@echo off
REM ===========================================================================
REM  KiCad Huaqiu - stable `dsh` CLI shim
REM
REM  Installed to <Common Files>\KiCad\bin\dsh.cmd (or %LOCALAPPDATA%\KiCad\bin
REM  for per-user installs) by the KiCad installer. This shim is the stable
REM  public CLI contract: it resolves the edge-headless runtime bundled with the
REM  installed KiCad / HQ Edge distribution and forwards every argument to its
REM  bin\dsh.cmd, so that a fresh terminal can run:
REM
REM      dsh --help
REM
REM  Resolution order (deterministic, "last installed version wins"):
REM    1. Registry value EdgeHeadlessBin under SOFTWARE\KiCad\DSH
REM       (HKLM for machine-wide installs, HKCU for per-user installs), written
REM       by the installer. The most recently installed/upgraded version owns it.
REM    2. Fallback: the most recently installed/upgraded KiCad version under
REM       %ProgramW6432%\KiCad\ that bundles an edge-headless runtime (used when
REM       the registry value is missing or stale, e.g. after uninstalling the
REM       version that owned the registry value while an older version remains).
REM ===========================================================================
setlocal EnableExtensions

set "EDGE_HEADLESS_BIN="

REM 1) Authoritative resolution: registry value written by the installer
for /f "skip=2 tokens=2*" %%A in ('reg query "HKLM\SOFTWARE\KiCad\DSH" /v EdgeHeadlessBin 2^>nul') do if /i "%%A"=="REG_SZ" set "EDGE_HEADLESS_BIN=%%B"
if not defined EDGE_HEADLESS_BIN (
    for /f "skip=2 tokens=2*" %%A in ('reg query "HKCU\SOFTWARE\KiCad\DSH" /v EdgeHeadlessBin 2^>nul') do if /i "%%A"=="REG_SZ" set "EDGE_HEADLESS_BIN=%%B"
)
if defined EDGE_HEADLESS_BIN if exist "%EDGE_HEADLESS_BIN%\dsh.cmd" goto :run

REM 2) Fallback: newest installed KiCad version with a bundled runtime
for /f "delims=" %%D in ('dir /b /ad /o-d "%ProgramW6432%\KiCad" 2^>nul') do (
    if exist "%ProgramW6432%\KiCad\%%D\bin\edge-headless\bin\dsh.cmd" (
        set "EDGE_HEADLESS_BIN=%ProgramW6432%\KiCad\%%D\bin\edge-headless\bin"
        goto :run
    )
)

echo dsh: no KiCad / HQ Edge runtime with a bundled DSH CLI was found. 1>&2
echo dsh: reinstall KiCad Huaqiu, or register the runtime via the installer. 1>&2
exit /b 1

:run
call "%EDGE_HEADLESS_BIN%\dsh.cmd" %*
exit /b %ERRORLEVEL%
