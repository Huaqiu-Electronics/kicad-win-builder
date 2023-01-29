@REM This program source code file is part of KiCad, a free EDA CAD application.
@REM
@REM Copyright (c) 2021 Mark Roszko <mark.roszko@gmail.com>
@REM Copyright (c) 2021 KiCad Developer Team
@REM
@REM This program is free software; you can redistribute it and/or
@REM modify it under the terms of the GNU General Public License
@REM as published by the Free Software Foundation; either version 3
@REM of the License, or (at your option) any later version.
@REM
@REM This program is distributed in the hope that it will be useful, but
@REM WITHOUT ANY WARRANTY; without even the implied warranty of
@REM MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
@REM General Public License for more details.
@REM
@REM You should have received a copy of the GNU General Public License along
@REM with this program.  If not, see <http://www.gnu.org/licenses/>.

@echo off

@REM We assume this script is located in the bin directory
set _BIN_DIR=%~dp0
set _KICAD_EXE_PATH=%_BIN_DIR%kicad.exe

set KICAD_VERSION=

@REM Get KiCad exe version to reproduce
for /f "USEBACKQ" %%a in (`powershell -NoProfile -NoLogo "&{(Get-Item '%_KICAD_EXE_PATH%').VersionInfo | %% {write-host ('{0}.{1}' -f $_.ProductMajorPart,$_.ProductMinorPart)}}"`) do (
    set KICAD_VERSION=%%a
)

:header

@echo ************************************
@echo * KiCad %KICAD_VERSION% Command Prompt
@echo ************************************

@REM dig up from registry the user documents folder because it might be redirected
for /f "skip=2 tokens=2,*" %%A IN ('reg.exe query "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" /v "Personal"') do (
@REM grab the registry value and use call to expand the key that might contain a variable
    call set "_USER_DOCUMENTS_PATH=%%B"
)

set _PYTHON_SCRIPTS_DIR=%_BIN_DIR%Scripts
set _PYTHON_USER_SCRIPTS_DIR=%_USER_DOCUMENTS_PATH%\KiCad\%KICAD_VERSION%\3rdparty\Python39\Scripts

@REM Now adjust PATH to gurantee our python/pip executables are found first
set PATH=%_BIN_DIR%;%_PYTHON_USER_SCRIPTS_DIR%;%_PYTHON_SCRIPTS_DIR%;%PATH%
set PYTHONHOME=%_BIN_DIR%

@REM We patch python into utf8 mode by default because kicad is utf8 heavy
@REM But let's just add extra insurance
set PYTHONUTF8=1

@echo You may now invoke python or pip targeting kicad's install

if defined KIPRJMOD (cd /d %KIPRJMOD%) else (cd /d %_USER_DOCUMENTS_PATH%\KiCad\%KICAD_VERSION%)

set _BIN_DIR=
set _PYTHON_SCRIPTS_DIR=
set _KICAD_EXE_PATH=
set _USER_DOCUMENTS_PATH=

exit /B 0
