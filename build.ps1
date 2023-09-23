#  Copyright (C) 2021-2022 Mark Roszko <mark.roszko@gmail.com>
#  Copyright (C) 2021-2022 KiCad Developers
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#  MA 02110-1301, USA.

##
# KiCad Powershell Windows Build Assistant
#
# Note, options in brackets [] are optional
#  Usage:
#   Configure/set the vcpkg path, OPTIONAL
#   Otherwise will checkout vcpkg inside the win-builder folder
#   ./build.ps1 -Config -VcpkgPath="path to vcpkg"
#
#   Checkout any required tools
#   ./build.ps1 -Init
#
#   Checkout any required tools, setup build environment variables
#   ./build.ps1 -Env [-Arch x64]
#
#   Rebuilds vcpkg dependencies (if updated)
#   ./build.ps1 -Vcpkg [-Latest] [-Arch x64]
#
#   Triggers a build
#   ./build.ps1 -Build [-Latest] [-Arch x64] [-BuildType Release]
#
#   Triggers a package operation
#   ./build.ps1 -PreparePackage [-Arch x64] [-BuildType Release] [-Lite] [-IncludeDebugSymbols]
#
#   Triggers a package operation
#   ./build.ps1 -Package [-PackType Nsis] [-Arch x64] [-BuildType Release] [-Lite] [-IncludeDebugSymbols]
#
#   Triggers a msix assets generation
#   ./build.ps1 -MsixAssets
#
#   IncludeDebugSymbols will include PDBs (off by default)
#   Lite will build the light version of the installer (no libraries)
##

param(
    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="config")]
    [Switch]$Config,

    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="init")]
    [Switch]$Init,

    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="env")]
    [Switch]$Env,

    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="build")]
    [Switch]$Build,

    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="vcpkg")]
    [Switch]$Vcpkg,

    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="package")]
    [Switch]$Package,
    
    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="preparepackage")]
    [Switch]$PreparePackage,

    [Parameter(Position = 0, Mandatory=$True, ParameterSetName="msixassets")]
    [Switch]$MsixAssets,

    [Parameter(Mandatory=$True, ParameterSetName="msixassets")]
    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [string]$Version,

    [Parameter(Mandatory=$False, ParameterSetName="build")]
    [Parameter(Mandatory=$False, ParameterSetName="vcpkg")]
    [Switch]$Latest,

    [Parameter(Mandatory=$False, ParameterSetName="env")]
    [Parameter(Mandatory=$False, ParameterSetName="build")]
    [Parameter(Mandatory=$False, ParameterSetName="vcpkg")]
    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [Parameter(Mandatory=$False, ParameterSetName="preparepackage")]
    [ValidateSet('x86', 'x64', 'arm64', 'arm')]
    [string]$Arch = 'x64',

    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [ValidateSet('nsis', 'msix')]
    [string]$PackType = 'nsis',
    
    [Parameter(Mandatory=$False, ParameterSetName="build")]
    [Parameter(Mandatory=$False, ParameterSetName="vcpkg")]
    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [Parameter(Mandatory=$False, ParameterSetName="preparepackage")]
    [string]$BuildConfigName = 'kicad-nightly',

    [Parameter(Mandatory=$False, ParameterSetName="build")]
    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [Parameter(Mandatory=$False, ParameterSetName="preparepackage")]
    [ValidateSet('Release', 'Debug')]
    [string]$BuildType = 'Release',

    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [switch]$DebugSymbols,

    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [Parameter(Mandatory=$False, ParameterSetName="preparepackage")]
    [switch]$IncludeVcpkgDebugSymbols,

    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [Parameter(Mandatory=$False, ParameterSetName="preparepackage")]
    [switch]$Lite,
    
    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [bool]$Prepare = $True,
    
    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [Parameter(Mandatory=$False, ParameterSetName="preparepackage")]
    [switch]$Sign,
    
    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [Parameter(Mandatory=$False, ParameterSetName="preparepackage")]
    [bool]$SignAKV = $False,
    
    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [Parameter(Mandatory=$False, ParameterSetName="preparepackage")]
    [string]$AKVAppId = "",

    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [Parameter(Mandatory=$False, ParameterSetName="preparepackage")]
    [string]$AKVAppSecret = "",

    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [Parameter(Mandatory=$False, ParameterSetName="preparepackage")]
    [string]$AKVTenantId = "",

    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [Parameter(Mandatory=$False, ParameterSetName="preparepackage")]
    [string]$AKVCertName = "",

    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [Parameter(Mandatory=$False, ParameterSetName="preparepackage")]
    [string]$AKVUrl = "",
    
    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [bool]$PostCleanup = $False,
    
    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [Parameter(Mandatory=$False, ParameterSetName="preparepackage")]
    [bool]$SentryArtifact = $False,
    
    [Parameter(Mandatory=$False, ParameterSetName="config")]
    [string]$VcpkgPath = "",
    
    [Parameter(Mandatory=$False, ParameterSetName="config")]
    [bool]$UseMsvcCmake = $True,
    
    [Parameter(Mandatory=$False, ParameterSetName="config")]
    [string]$SentryDsn = ""
)

Import-Module $PSScriptRoot\KiBuild -Force -DisableNameChecking


###
## Base setup
###

$vcpkgCommit = "c6928dfb9eb7f333f988d2ce70d1e771b7606849";

$cmakeFolder = 'cmake-3.27.1-windows-x86_64'
$cmakeDownload = 'https://github.com/Kitware/CMake/releases/download/v3.27.1/cmake-3.27.1-windows-x86_64.zip'
$cmakeChecksum = "664FE1655999F0B693D1E64DDB430191C727AB0A03DC1DA7278F291172E1E04E"

$ninjaFolder = 'ninja-win'
$ninjaDownload = 'https://github.com/ninja-build/ninja/releases/download/v1.11.1/ninja-win.zip'
$ninjaChecksum = "524B344A1A9A55005EAF868D991E090AB8CE07FA109F1820D40E74642E289ABC"

$vswhereDownload = 'https://github.com/microsoft/vswhere/releases/download/2.8.4/vswhere.exe'
$vswhereChecksum = "E50A14767C27477F634A4C19709D35C27A72F541FB2BA5C3A446C80998A86419"

$swigwinFolder = "swigwin-4.1.1"
$swigwinDownload = "https://sourceforge.net/projects/swig/files/swigwin/$swigwinFolder/$swigwinFolder.zip/download?use_mirror=pilotfiber"
$swigwinChecksum = "2EC3107E24606DB535D77EF3DBF246DC6ECCBF1D5C868DCE365D7F7FB19A1A51"

$nsisFolderName = "nsis-3.08"
$nsisDownload = "https://sourceforge.net/projects/nsis/files/NSIS%203/3.08/nsis-3.08.zip/download"
$nsisChecksum = "1BB9FC85EE5B220D3869325DBB9D191DFE6537070F641C30FBB275C97051FD0C"

$gettextFolderName = "gettext0.21-iconv1.16-static-64"
$gettextDownload = "https://github.com/mlocati/gettext-iconv-windows/releases/download/v0.21-v1.16/gettext0.21-iconv1.16-static-64.zip"
$gettextChecksum = "721395C2E057EEED321F0C793311732E57CB4FA30D5708672A13902A69A77D43"

$doxygenDownload = "https://sourceforge.net/projects/doxygen/files/rel-1.9.3/doxygen-1.9.3.windows.x64.bin.zip/download?use_mirror=pilotfiber"
$doxygenChecksum = "575B1A27CB907675D24F2C348A4D95D9CDD6A2000F6A8D8BFC4C3A20B2E120F5"
$doxygenFolderName = "doxygen-1.9.3.windows.x64.bin"

$s5cmdDownload = "https://github.com/peak/s5cmd/releases/download/v1.4.0/s5cmd_1.4.0_Windows-64bit.zip"
$s5cmdChecksum = "085CCD677662C0B4EEA00325AAF04CE62B920D2A37F313AF9616ACE7DDDA537E"
$s5cmdFolderName = "s5cmd_1.4.0_Windows-64bit"

$sentryCliDownload = 'https://github.com/getsentry/sentry-cli/releases/download/1.74.3/sentry-cli-Windows-x86_64.exe'
$sentryCliChecksum = "0D2F372D98F53EA4D4DF26161F1F821D5322B00A0227CE84EC939BF271C720AD"


$7zaFolderName = "7z2201-extra"

Init-Paths $PSScriptRoot
$BuilderPaths = Get-BuilderPaths

$swigWinPath = Join-Path -Path $BuilderPaths.SupportRoot -ChildPath $swigwinFolder
$gettextPath = Join-Path -Path $BuilderPaths.SupportRoot -ChildPath "/$gettextFolderName/bin"
$doxygenPath = Join-Path -Path $BuilderPaths.SupportRoot -ChildPath $doxygenFolderName
$nsisPath = Join-Path -Path (Join-Path -Path $BuilderPaths.SupportRoot -ChildPath $nsisFolderName) -ChildPath "bin/"

$azureSignToolVersion = "3.0.0"
$azureSignToolPath = Join-Path -Path $BuilderPaths.SupportRoot -ChildPath "azuresigntool-$azureSignToolVersion"

$env:Path = $swigWinPath+";"+$gettextPath+";"+$nsisPath+";"+$doxygenPath+";"+$env:PATH


# Use TLS1.2 by force in case of older powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Force git output to go to stdout or else powershell eats it and doesn't show us it
$env:GIT_REDIRECT_STDERR='2>&1'


###
# Load and handle Config
###
$settingsPath = Join-Path -Path $PSScriptRoot -ChildPath "settings.json"

$settingDefault = @{
    VcpkgPath = ''
    VcpkgPlatformToolset = 'v142'
    VsVersionMin = '16.0'
    VsVersionMax = '17.99'
    SignSubjectName = 'KiCad Services Corporation'
    UseMsvcCmake = $True
    SentryDsn = ''
}

$settingsSaved = @{}
if ( Test-Path $settingsPath ) {
    Write-Host "Loading settings from $settingsPath"

    $settingsObj = Get-Content -Path $settingsPath | ConvertFrom-Json

    Write-Host "-----"
    $settingsObj.psobject.properties | Foreach {
        $settingsSaved[$_.Name] = $_.Value
        Write-Host "$($_.Name): $($_.Value)"
    }
    Write-Host "-----"
} else {
    Write-Host "Existing settings not found" -ForegroundColor DarkYellow
}


###
# Load release if set
###

$buildConfigured = $false
$buildConfig = @{}
$buildConfigsPath = Join-Path -Path $PSScriptRoot -ChildPath "\build-configs"

if( $BuildConfigName ) {
    $buildConfigPath = Join-Path -Path $buildConfigsPath -ChildPath "$BuildConfigName.json"
    
    if ( -Not (Test-Path $buildConfigPath) ) {
        Write-Error "Build Config ""$BuildConfigName"" not found"
        Exit [ExitCodes]::ReleaseDoesNotExit
    }
    
    $buildConfig = Get-Content -Path $buildConfigPath | ConvertFrom-Json
    $BuildConfigName = $true

    Write-Host "Loaded release config $($buildConfig.name)" -ForegroundColor Yellow
}


$settings = Merge-HashTable -Default $settingDefault -Uppend $settingsSaved


# Set VCPKG Platform Toolset
$env:VCPKG_PLATFORM_TOOLSET = $settings.VcpkgPlatformToolset


###
# Setup aliases to shorten accessing tools
##

function Set-Aliases()
{
    Write-Host "Configuring tool aliases"
    if( -not (Test-Path alias:vcpkg ) )
    {
        if( $settings.VcpkgPath -ne "" )
        {
            $tmp = Join-Path -Path $settings.VcpkgPath -ChildPath "vcpkg.exe"
            Set-Alias vcpkg $tmp -Option AllScope -Scope Global
        }
    }

    if( -not (Test-Path alias:vswhere ) )
    {
        $tmp = Join-Path -Path $BuilderPaths.SupportRoot -ChildPath "vswhere.exe"
        Set-Alias vswhere $tmp -Option AllScope -Scope Global
    }
    
    if( -not $settings.UseMsvcCmake )
    {
        if( -not (Test-Path alias:cmake ) )
        {
            $cmakeBin = Join-Path -Path $BuilderPaths.SupportRoot -ChildPath "$cmakeFolder/bin"
            $cmakeExe = Join-Path -Path $cmakeBin -ChildPath "cmake.exe"
            $env:Path = $cmakeBin+";"+$env:Path;
            Set-Alias cmake $cmakeExe -Option AllScope -Scope Global
        }
        
        if( -not (Test-Path alias:ninja ) )
        {
            $ninjaBin = Join-Path -Path $BuilderPaths.SupportRoot -ChildPath "$ninjaFolder"
            $ninjaExe = Join-Path -Path $BuilderPaths.SupportRoot -ChildPath "$ninjaFolder/ninja.exe"
            $env:NINJA_PATH = $ninjaExe;
            $env:Path = $ninjaBin+";"+$env:Path;
            Set-Alias ninja $ninjaExe -Option AllScope -Scope Global
        }
    }


    if( -not (Test-Path alias:makensis ) )
    {
        $tmp = Join-Path -Path (Join-Path -Path $BuilderPaths.SupportRoot -ChildPath $nsisFolderName) -ChildPath "bin/makensis.exe"
        Set-Alias makensis $tmp -Option AllScope -Scope Global
    }
    
    if( -not (Test-Path alias:7za ) )
    {
        $tmp = Join-Path -Path $BuilderPaths.SupportRoot -ChildPath "$7zaFolderName/7za.exe"
        Set-Alias 7za $tmp -Option AllScope -Scope Global
    }

    if( -not (Test-Path alias:sentry-cli ) )
    {
        $tmp = Join-Path -Path $BuilderPaths.SupportRoot -ChildPath "sentry-cli.exe"
        Set-Alias sentry-cli $tmp -Option AllScope -Scope Global
    }
    
    if( -not (Test-Path alias:azuresigntool ) )
    {
        $tmp = Join-Path -Path $azureSignToolPath -ChildPath "azuresigntool.exe"
        Set-Alias azuresigntool $tmp -Option AllScope -Scope Global
    }
    
    if( -not (Test-Path alias:s5cmd ) )
    {
        $tmp = Join-Path -Path (Join-Path -Path $BuilderPaths.SupportRoot -ChildPath $s5cmdFolderName) -ChildPath "s5cmd.exe"
        Set-Alias s5cmd $tmp -Option AllScope -Scope Global
    }
}

## Invoke it
Set-Aliases

###
# General functions
##
function Get-Source-Path([string]$subfolder) {
    return Join-Path -Path $BuilderPaths.BuildRoot -ChildPath $subfolder
}


function Build-Library-Source {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch,
        [Parameter(Mandatory=$False)]
        [ValidateSet('Release', 'Debug')]
        [string]$buildType = 'Release',
        [string]$libraryFolderName
    )

    Push-Location (Get-Source-Path $libraryFolderName)

    Set-MSVCEnvironment -Arch $arch -VersionMin $settings.VsVersionMin -VersionMax $settings.VsVersionMax

    $buildName = Get-Build-Name -Arch $arch -BuildType $buildType
    $installPath = Join-Path -Path $BuilderPaths.OutRoot -ChildPath "$buildName/"

    $cmakeBuildFolder = "build/$buildName"
    $generator = "Ninja"

    & {
        $ErrorActionPreference = 'SilentlyContinue'
        cmake -G $generator `
            -B $cmakeBuildFolder `
            -S .  `
            -DCMAKE_INSTALL_PREFIX="$installPath" `
            -DCMAKE_RULE_MESSAGES:BOOL="OFF" `
            -DCMAKE_VERBOSE_MAKEFILE:BOOL="OFF"
    }

    if ($LastExitCode -ne 0) {
        Write-Error "Failure generating cmake"
        Pop-Location
        Exit [ExitCodes]::CMakeGenerationFailure
    }

    Write-Host "Configured $libraryFolderName" -ForegroundColor Green
    Pop-Location
}


function Install-Library {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch,
        [Parameter(Mandatory=$False)]
        [ValidateSet('Release', 'Debug')]
        [string]$buildType = 'Release',
        [string]$libraryFolderName
    )

    Push-Location (Get-Source-Path $libraryFolderName)
    
    Set-MSVCEnvironment -Arch $arch -VersionMin $settings.VsVersionMin -VersionMax $settings.VsVersionMax

    $buildName = Get-Build-Name -Arch $arch -BuildType $buildType

    $cmakeBuildFolder = "build/$buildName"

    Write-Host "Installing $libraryFolderName to output" -ForegroundColor Yellow
    & {
        $ErrorActionPreference = 'SilentlyContinue'
        cmake --install $cmakeBuildFolder > $null
    }

    if ($LastExitCode -ne 0) {
        Write-Error "Failure with cmake install"
        Pop-Location
        Exit [ExitCodes]::CMakeInstallFailure
    }

    Pop-Location
}

function Install-Kicad {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch,
        [Parameter(Mandatory=$False)]
        [ValidateSet('Release', 'Debug')]
        [string]$buildType = 'Release',
        [Parameter(Mandatory=$False)]
        [string]$installPath = ''
    )

    Set-MSVCEnvironment -Arch $arch -VersionMin $settings.VsVersionMin -VersionMax $settings.VsVersionMax

    $buildName = Get-Build-Name -Arch $arch -BuildType $buildType

    #step down into kicad folder
    Push-Location (Get-Source-Path kicad)

    $cmakeBuildFolder = "build/$buildName"

    Write-Host "Invoking cmake install" -ForegroundColor Yellow
    & {
        $ErrorActionPreference = 'SilentlyContinue'
        if( $installPath ) {
            cmake --install $cmakeBuildFolder --prefix $installPath > $null
        } else {
            cmake --install $cmakeBuildFolder > $null
        }
    }

    if ($LastExitCode -ne 0) {
        Write-Error "Failure with cmake install"
        Pop-Location
        Exit [ExitCodes]::CMakeInstallFailure
    } else {
        Write-Host "Install success" -ForegroundColor Green
    }

    #restore path
    Pop-Location
}

function Build-Kicad {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch,
        [Parameter(Mandatory=$False)]
        [ValidateSet('Release', 'Debug')]
        [string]$buildType = 'Release',
        [Parameter(Mandatory=$False)]
        [bool]$fresh = $False
    )

    $buildName = Get-Build-Name -Arch $arch -BuildType $buildType

    #step down into kicad folder
    Push-Location (Get-Source-Path kicad)

    Set-MSVCEnvironment -Arch $arch -VersionMin $settings.VsVersionMin -VersionMax $settings.VsVersionMax

    $cmakeBuildFolder = "build/$buildName"
    $generator = "Ninja"

    #delete the old build folderhttps://gitlab.com/kicad/code/kicad.git
    if($fresh) {
        Remove-Item $cmakeBuildFolder -Recurse -ErrorAction SilentlyContinue
    }


    $installPath = Join-Path -Path $BuilderPaths.OutRoot -ChildPath "$buildName/"
    $toolchainPath = Join-Path -Path $settings["VcpkgPath"] -ChildPath "/scripts/buildsystems/vcpkg.cmake"
    $installPdbPath = Join-Path -Path $BuilderPaths.OutRoot -ChildPath "$buildName-pdb"

    Write-Host "Starting build"
    Write-Host "arch: $arch"
    Write-Host "buildType: $buildType"
    Write-Host "Configured install directory: $installPath"
    Write-Host "Vcpkg Path: $toolchainPath"

    $cmakeArgs = @(
        '-G',
        $generator,
        '-B',
        $cmakeBuildFolder,
        '-Wno-dev',
        '--fresh',
        "-DCMAKE_BUILD_TYPE=$buildType",
        "-DCMAKE_TOOLCHAIN_FILE=$toolchainPath",
        "-DCMAKE_INSTALL_PREFIX=$installPath",
        "-DCMAKE_PDB_OUTPUT_DIRECTORY=$installPdbPath",
        "-DCMAKE_MAKE_PROGRAM=$env:NINJA_PATH",
        '-DKICAD_BUILD_QA_TESTS=OFF',
        '-DKICAD_BUILD_I18N=ON',
        '-DKICAD_WIN32_DPI_AWARE=ON'
    )

    if( $arch -ne [Arch]::arm64 ) {
        $cmakeArgs += '-DKICAD_SCRIPTING_WXPYTHON=ON';
        if( $settings.SentryDsn -ne "" ) {
            $cmakeArgs += '-DKICAD_USE_SENTRY=ON';
            $cmakeArgs += "-DKICAD_SENTRY_DSN=$($settings.SentryDsn)";
        }
    }
    else {
        $hostArch = Get-HostArch

        if( $hostArch -ne $arch ) {
            # this is a hack required to cross compile arm64
            # since lemon.exe in the build tree must be run to generate the compilable grammer
            # so you must run a native compile first
            # TODO consider doing a offshoot targeted compile of the lemon target on the host arch
            $hostArchBuildName = Get-Build-Name -Arch $hostArch -BuildType $buildType
            $hostArchcmakeBuildFolder = "build/$hostArchBuildName"
            $lemonPath = Join-Path -Path $hostArchcmakeBuildFolder -ChildPath "thirdparty/lemon/lemon.exe"
            $cmakeArgs += "-DLEMON_EXE=$lemonPath";
        }
    }

    $cmakeArgs += '-S';
    $cmakeArgs += '.';
    # ignore cmake dumping to stderr
    # the boost warnings will cause it to treat it as a failed command
    & cmake $cmakeArgs  2>&1

    if ($LastExitCode -ne 0) {
        Write-Error "Failure generating cmake"
        Pop-Location
        Exit [ExitCodes]::CMakeGenerationFailure
    } else {
        Write-Host "Invoking cmake build" -ForegroundColor Yellow

        & {
            $ErrorActionPreference = 'SilentlyContinue'
            cmake --build $cmakeBuildFolder -j 2>&1 | % ToString
        }

        if ($LastExitCode -ne 0) {
            Write-Error "Failure with cmake build"
            Pop-Location
            Exit [ExitCodes]::CMakeBuildFailure
        } else {
            Write-Host "Build complete" -ForegroundColor Green
        }
    }

    #restore path
    Pop-Location
}

function script:Get-Source-Ref ([string] $sourceKey) {
    if(  $buildConfig.sources.PSObject.Properties.Match($sourceKey) )
    {
        return $buildConfig.sources.$sourceKey.ref
    }
    else {
        return ""
    }
}

function Start-Build {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch,
        [Parameter(Mandatory=$False)]
        [ValidateSet('Release', 'Debug')]
        [string]$buildType = 'Release',
        [Parameter(Mandatory=$False)]
        [bool]$latest = $False
    )

    Get-Source -url https://gitlab.com/kicad/code/kicad.git `
               -dest (Get-Source-Path kicad) `
               -sourceType git `
               -latest $latest `
               -ref (Get-Source-Ref -sourceKey "kicad")

    Get-Source -url https://gitlab.com/kicad/libraries/kicad-symbols.git `
               -dest (Get-Source-Path kicad-symbols) `
               -sourceType git `
               -latest $latest `
               -ref (Get-Source-Ref -sourceKey "symbols")

    Get-Source -url https://gitlab.com/kicad/libraries/kicad-footprints.git `
               -dest (Get-Source-Path kicad-footprints) `
               -sourceType git `
               -latest $latest `
               -ref (Get-Source-Ref -sourceKey "footprints")

    Get-Source -url https://gitlab.com/kicad/libraries/kicad-packages3D.git `
               -dest (Get-Source-Path kicad-packages3D) `
               -sourceType git `
               -latest $latest `
               -ref (Get-Source-Ref -sourceKey "3dmodels")

    Get-Source -url https://gitlab.com/kicad/libraries/kicad-templates.git `
               -dest (Get-Source-Path kicad-templates) `
               -sourceType git `
               -latest $latest `
               -ref (Get-Source-Ref -sourceKey "templates")

    Build-KiCad -arch $arch -buildType $buildType
    Build-Library-Source -arch $arch -buildType $buildType -libraryFolderName kicad-symbols
    Build-Library-Source -arch $arch -buildType $buildType -libraryFolderName kicad-footprints
    Build-Library-Source -arch $arch -buildType $buildType -libraryFolderName kicad-packages3D
    Build-Library-Source -arch $arch -buildType $buildType -libraryFolderName kicad-templates
}


function Start-Init {
    # The progress bar slows down download performance by absurd amounts, turn it off
    $ProgressPreference = 'SilentlyContinue'

    if( -Not $settings.UseMsvcCmake )
    {
        Get-Tool -ToolName "CMake" `
                 -Url $cmakeDownload `
                 -DestPath (Join-Path -Path $BuilderPaths.SupportRoot -ChildPath $cmakeFolder) `
                 -DownloadPath (Join-Path -Path $BuilderPaths.DownloadsRoot -ChildPath "cmake.zip") `
                 -Checksum $cmakeChecksum `
                 -ExtractZip $true `
                 -ZipRelocate $False `
                 -ExtractInSupportRoot $True

        Get-Tool -ToolName "Ninja" `
                 -Url $ninjaDownload `
                 -DestPath (Join-Path -Path $BuilderPaths.SupportRoot -ChildPath $ninjaFolder) `
                 -DownloadPath (Join-Path -Path $BuilderPaths.DownloadsRoot -ChildPath "ninja.zip") `
                 -Checksum $ninjaChecksum `
                 -ExtractZip $true `
                 -ZipRelocate $False `
                 -ExtractInSupportRoot $False
    }

    Get-Tool -ToolName "swigwin" `
             -Url $swigwinDownload `
             -DestPath (Join-Path -Path $BuilderPaths.SupportRoot -ChildPath $swigwinFolder) `
             -DownloadPath (Join-Path -Path $BuilderPaths.DownloadsRoot -ChildPath "$swigwinFolder.zip") `
             -Checksum $swigwinChecksum `
             -ExtractZip $true `
             -ExtractInSupportRoot $True

    Get-Tool -ToolName "doxygen" `
             -Url $doxygenDownload `
             -DestPath (Join-Path -Path $BuilderPaths.SupportRoot -ChildPath $doxygenFolderName) `
             -DownloadPath (Join-Path -Path $BuilderPaths.DownloadsRoot -ChildPath "$doxygenFolderName.zip") `
             -Checksum $doxygenChecksum `
             -ExtractZip $true `
             -ExtractInSupportRoot $False

    Get-Tool -ToolName "nsis" `
             -Url $nsisDownload `
             -DestPath (Join-Path -Path $BuilderPaths.SupportRoot -ChildPath $nsisFolderName) `
             -DownloadPath (Join-Path -Path $BuilderPaths.DownloadsRoot -ChildPath "nsis.zip") `
             -Checksum $nsisChecksum `
             -ExtractZip $true `
             -ExtractInSupportRoot $True

    Get-Tool -ToolName "vswhere" `
             -Url $vswhereDownload `
             -DestPath ($BuilderPaths.SupportRoot+'vswhere.exe') `
             -DownloadPath (Join-Path -Path $BuilderPaths.DownloadsRoot -ChildPath "vswhere.exe") `
             -Checksum $vswhereChecksum `
             -ExtractZip $False
             
    Get-Tool -ToolName "sentry-cli" `
            -Url $sentryCliDownload `
            -DestPath ($BuilderPaths.SupportRoot+'sentry-cli.exe') `
            -DownloadPath (Join-Path -Path $BuilderPaths.DownloadsRoot -ChildPath "sentry-cli.exe") `
            -Checksum $sentryCliChecksum `
            -ExtractZip $False

    Get-Tool -ToolName "gettext" `
             -Url $gettextDownload `
             -DestPath ($BuilderPaths.SupportRoot+"$gettextFolderName/") `
             -DownloadPath (Join-Path -Path $BuilderPaths.DownloadsRoot -ChildPath "$gettextFolderName.zip") `
             -Checksum $gettextChecksum `
             -ExtractZip $true

    Get-Tool -ToolName "s5cmd" `
             -Url $s5cmdDownload `
             -DestPath (Join-Path -Path $BuilderPaths.SupportRoot -ChildPath $s5cmdFolderName) `
             -DownloadPath (Join-Path -Path $BuilderPaths.DownloadsRoot -ChildPath "s5cmd.zip") `
             -Checksum $s5cmdChecksum `
             -ExtractZip $true `
             -ZipRelocate $False `
             -ExtractInSupportRoot $False
    
    if( -not (Test-Path $azureSignToolPath ) ) {
        if (Get-Command "dotnet.exe" -ErrorAction SilentlyContinue) { 
            dotnet tool install AzureSignTool --version $azureSignToolVersion --tool-path $azureSignToolPath
        }
        else {
            Write-Warning "Missing dotnet executable to install azure sign tool"
        }
    }

    $7zaSource = Join-Path -Path $PSScriptRoot -ChildPath "\support\7z2201-extra.zip"
    Expand-Tool -ToolName "7za" `
             -SourcePath $7zaSource `
             -DestPath (Join-Path -Path $BuilderPaths.SupportRoot -ChildPath "$7zaFolderName/")

    # Restore progress bar
    $ProgressPreference = 'Continue'
}

function Get-Vcpkg-Triplet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$Arch
    )

    $triplet = "$Arch-windows"
    return $triplet;
}


function Get-Build-Name {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$Arch,
        [Parameter(Mandatory=$True)]
        [ValidateSet('Release', 'Debug')]
        [string]$BuildType
    )

    return "$Arch-windows-$BuildType";
}


function Build-Vcpkg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch,
        [Parameter(Mandatory=$False)]
        [bool]$latest = $True
    )
    

    $vcpkgPath = $settings["VcpkgPath"]
    if( $vcpkgPath -eq "" ) {
        Write-Host "No vcpkg path provided" -ForegroundColor DarkYellow

        $vcpkgPath = Join-Path -Path $PSScriptRoot -ChildPath vcpkg

        # for now, destroy the folder if it isnt configured on our side
        if( Test-Path $vcpkgPath ) {
            Remove-Item $vcpkgPath -Recurse -Force
        }

        Write-Host "Checking out vcpkg to $vcpkgPath" -ForegroundColor Yellow
        
        if($buildConfig.vcpkg.manifest_mode) {
            git clone https://github.com/microsoft/vcpkg.git $vcpkgPath
        } else {
            git clone https://gitlab.com/kicad/packaging/vcpkg.git $vcpkgPath
        }

        Set-Config -VcpkgPath $vcpkgPath

        # get vcpkg alias updated
        Set-Aliases
    }

    # Bootstrap vcpkg
    Push-Location $vcpkgPath

    if( $latest ) {
        Write-Host "Updating vcpkg git repo" -ForegroundColor Yellow

        git fetch
        if($buildConfig.vcpkg.manifest_mode) {
            git checkout master
            git reset --hard $vcpkgCommit
        } else {
            git checkout kicad
            git reset --hard origin/kicad
        }
    }

    .\bootstrap-vcpkg.bat

    if(-Not $buildConfig.vcpkg.manifest_mode) {
        # Setup dependencies
        $triplet = Get-Vcpkg-Triplet -Arch $arch

        $dependencies = @()
        $dependencies = $dependencies + $buildConfig.vcpkg.dependencies

        # Format the dependencies with the triplet
        for ($i = 0; $i -lt $dependencies.Count; $i++) {
            $dependencies[$i] = $dependencies[$i]+":$triplet"
        }

        vcpkg install $dependencies --recurse 2>&1

        if ($LastExitCode -ne 0) {
            Write-Error "Failure installing vcpkg ports"
            Exit [ExitCodes]::VcpkgInstallPortsFailure
        } else {
            Write-Host "vcpkg ports installed/updated" -ForegroundColor Green
        }

        # Unforunately, theres no "install or upgrade" command
        # We can safely however run ugprade and install and it'll just do nothing in the worse case
        vcpkg upgrade $dependencies --no-dry-run 2>&1

        if ($LastExitCode -ne 0) {
            Write-Error "Failure upgrading vcpkg ports"
            Exit [ExitCodes]::VcpkgInstallPortsFailure
        } else {
            Write-Host "vcpkg ports installed/updated" -ForegroundColor Green
        }
    }

    Pop-Location
}

function Get-KiCad-CommitHash {

    Push-Location (Get-Source-Path kicad)

    $commitHash = (git rev-parse --verify HEAD)

    Pop-Location

    return $commitHash
}

function Get-KiCad-PackageVersion {

    if( $buildConfig.train -eq "stable" )
    {
        return $buildConfig.package_version
    }
    else
    {
        Push-Location (Get-Source-Path kicad)
    
        $revCount = (git describe --long --tags | %{$_ -replace "-","."} )
    
        Pop-Location
    
        return "$revCount"
    }
}

function Get-KiCad-Version {
    $srcFile = Join-Path -Path (Get-Source-Path kicad) -ChildPath "CMakeModules\KiCadVersion.cmake"
    if( -not (Test-Path $srcFile ) )
    {
        # new path in master
        $srcFile = Join-Path -Path (Get-Source-Path kicad) -ChildPath "cmake\KiCadVersion.cmake"
    }


    $result = Select-String -Path $srcFile -Pattern '(?<=KICAD_SEMANTIC_VERSION\s")([0-9]+).([0-9])+' -AllMatches | % { $_.Matches } | % { $_.Value } | Select-Object -First 1

    return $result
}

function Get-KiCad-PackageVersion-Msix {

    $base = Get-KiCad-Version
    
    Push-Location (Get-Source-Path kicad)
    $revCount = (git describe --long --tags | %{$_ -replace "-","."} )
    Pop-Location

    # SPECIAL REQUIREMENT
    # MSIX package version must always end with .0
    return "${base}.${revCount}.0"
}


function Sign-File {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$File
    )

    Write-Host "Signing file: $File" -ForegroundColor Blue

    if( $SignAKV ) {
        azuresigntool sign -kvt "$AKVTenantId" -fd sha256 `
                            -td sha256 -kvu "$AKVUrl" -kvi "$AKVAppId" `
                            -kvs "$AKVAppSecret" -kvc "$AKVCertName" `
                            -tr http://timestamp.digicert.com -q "$File"
                        
        if ($LastExitCode -ne 0) {
            Write-Error "Error signing file $File, exit code $LastExitCode"
            Exit [ExitCodes]::SignFail
        }
    } 
    else {
        signtool.exe sign /a /n "$($settings.SignSubjectName)" /fd sha256 /tr http://timestamp.sectigo.com /td sha256 /q $File
    
        if ($LastExitCode -ne 0) {
            Write-Error "Error signing file $File, exit code $LastExitCode"
            Exit [ExitCodes]::SignFail
        }
    }
}


function Start-Prepare-Package {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch,
        [Parameter(Mandatory=$False)]
        [ValidateSet('Release', 'Debug')]
        [string]$buildType = "Release",
        [Parameter(Mandatory=$False)]
        [bool]$includeVcpkgDebugSymbols = $False,
        [Parameter(Mandatory=$False)]
        [bool]$lite = $False,
        [Parameter(Mandatory=$False)]
        [bool]$sign = $False,
        [Parameter(Mandatory=$False)]
        [bool]$sentryArtifact = $false
    )
    # Required for signing
    Set-MSVCEnvironment -Arch $arch -VersionMin $settings.VsVersionMin -VersionMax $settings.VsVersionMax

    # Save commit hash to a file
    $commitHashPath = Join-Path -Path $BuilderPaths.OutRoot -ChildPath "commit-hash"
    Get-KiCad-CommitHash | Out-File -FilePath $commitHashPath -Encoding ascii

    $packageVersion = Get-KiCad-PackageVersion
    $kicadVersion = Get-KiCad-Version

    $nsisArch = Get-NSISArch -Arch $arch

    Write-Host "Package Version: $packageVersion"
    Write-Host "KiCad Version: $kicadVersion"
    if($lite) {
        Write-Host "Lite package"
    }
    else {
        Write-Host "Full package"
    }

    $triplet = Get-Vcpkg-Triplet -Arch $arch
    $buildName = Get-Build-Name -Arch $arch -BuildType $buildType

    if($buildConfig.vcpkg.manifest_mode) {
        $kiPath = Get-Source-Path kicad
        $vcpkgInstalledRoot = Join-Path -Path $kiPath -ChildPath "build/$buildName/vcpkg_installed/$triplet/"
    } else {
        $vcpkgInstalledRoot = Join-Path -Path $settings["VcpkgPath"] -ChildPath "installed\$triplet\"
    }
    $vcpkgInstalledRootPrimary = $vcpkgInstalledRoot
    $destRoot = Join-Path -Path $PSScriptRoot -ChildPath ".out\$buildName\"
    $destBin = Join-Path -Path $destRoot -ChildPath "bin\"
    $destLib = Join-Path -Path $destRoot -ChildPath "lib\"
    $destEtc = Join-Path -Path $destRoot -ChildPath "etc\"

    # Now delete the existing output content
    if( Test-Path $destRoot )
    {
        Remove-Item $destRoot -Recurse -Force
    }

    Install-Kicad -arch $arch -buildType $buildType

    # Perfect time to create the sentry artifact
    if( $sentryArtifact ) {
        $outFileName = "$($buildConfig.output_prefix)$packageVersion-$nsisArch-sentry.zip"

        $sentryOutPath = Join-Path -Path $BuilderPaths.OutRoot -ChildPath $outFileName

        7za a -tzip -mm=lzma -bsp0 $sentryOutPath -x!*\ ($destBin+"\*") -r0

                
        # Now create source bundles for sentry
        $srcBundleArchiveFileName = "$($buildConfig.output_prefix)$packageVersion-$nsisArch-sentry-src.zip"

        $sentrySrcOutPath = Join-Path -Path $BuilderPaths.OutRoot -ChildPath $srcBundleArchiveFileName
        
        $pdbsFolder = Join-Path -Path $PSScriptRoot -ChildPath ".out\$buildName-pdb\"
        $bundleOutFolder = Join-Path -Path $PSScriptRoot -ChildPath ".out\$buildName-sentry-src\"
        
        $files = Get-ChildItem -Path $pdbsFolder -Filter *.pdb
        foreach ($file in $files) {
            sentry-cli difutil bundle-sources $file.FullName -o $bundleOutFolder
        }
        
        7za a -tzip -mm=lzma -bsp0 $sentrySrcOutPath -x!*\ ($bundleOutFolder+"\*") -r0
    }

    if( -not $lite )
    {
        Install-Library -arch $arch -buildType $buildType -libraryFolderName kicad-symbols
        Install-Library -arch $arch -buildType $buildType -libraryFolderName kicad-footprints
        Install-Library -arch $arch -buildType $buildType -libraryFolderName kicad-packages3D
        Install-Library -arch $arch -buildType $buildType -libraryFolderName kicad-templates
    }

    if( $buildType -eq 'Debug' )
    {
        $vcpkgInstalledRoot = Join-Path -Path $vcpkgInstalledRoot -ChildPath "debug"
    }

    
    if($buildConfig.vcpkg.manifest_mode) {
        $vcpkgInstalledBin = Join-Path -Path $vcpkgInstalledRoot -ChildPath "bin\"

        Write-Host "Copying from $vcpkgInstalledBin to $destBin" -ForegroundColor Yellow
        Copy-Item "$vcpkgInstalledBin*" -Destination $destBin -Filter *.dll -Recurse
    } else {
        # All libraries to copy _should use a wildcard at the end
        # This is to copy both the .dll and .pdb
        # Or only .dll based on switch
        $vcpkgBinCopy = @()
        $vcpkgBinCopy = $vcpkgBinCopy + $buildConfig.vcpkg.package_globs
    
        $vcpkgInstalledBin = Join-Path -Path $vcpkgInstalledRoot -ChildPath "bin\"
    
        Write-Host "Copying from $vcpkgInstalledBin to $destBin" -ForegroundColor Yellow
        foreach( $copyFilter in $vcpkgBinCopy )
        {
            $source = "$vcpkgInstalledBin\$copyFilter"
    
            if(!$includeVcpkgDebugSymbols)
            {
                $source += ".dll";
            }
    
            Write-Host "Copying $source"
            Copy-Item $source -Destination $destBin -Recurse
        }
    }

    ## etc
    ## For now the etc folder should be harmless to copy over entirely
    $srcEtc = Join-Path -Path $vcpkgInstalledRoot -ChildPath "etc\"
    Copy-Item $srcEtc -Destination $destEtc -Recurse -Container  -Force

    ## ngspice related
    $ngspiceLib = Join-Path -Path $vcpkgInstalledRoot -ChildPath "lib\ngspice"
    $ngspiceDestLib = Join-Path -Path $destLib -ChildPath "ngspice\"
    Write-Host "Copying ngspice lib $ngspiceLib to $destLib"
    Copy-Item $ngspiceLib -Destination $ngspiceDestLib -Recurse -Container -Force

    ### fixup for 64-bit....ngspice appends "64" to the end of the code model names wrongly
    if( $arch -eq [Arch]::x64 )
    {
        Get-ChildItem $ngspiceDestLib -Filter *64.cm |
        Foreach-Object {
            $newName = $_.Name -replace '64.cm','.cm'

            Rename-Item -Path $_.FullName -NewName $newName
        }
    }

    ## now python3
    $python3Source = "$vcpkgInstalledRootPrimary\tools\python3\*"
    Write-Host "Copying python3 $python3Source to $destBin"
    Copy-Item $python3Source -Destination $destBin -Recurse -Force

    ### but delete the scripts folder as this stuff is mostly host based paths
    ### We will create these later
    Remove-Item (Join-Path -Path $destBin -ChildPath "\Scripts\") -Recurse -ErrorAction SilentlyContinue

    $siteCustomizeSource = Join-Path -Path $PSScriptRoot -ChildPath "\support\sitecustomize.py"
    $siteCustomizeDest = Join-Path -Path $destBin -ChildPath "Lib/site-packages"
    Copy-Item $siteCustomizeSource -Destination $siteCustomizeDest -Force
    
    $kicadCmdSource = Join-Path -Path $PSScriptRoot -ChildPath "\support\kicad-cmd.bat"
    Copy-Item $kicadCmdSource -Destination $destBin -Force

    ### lets setup pip
    $hostArch = Get-HostArch
    if( $arch -eq $hostArch ) {
        # we can't run this if the python.exe compiled isn't the same arch
        Write-Host "Ensuring pip is bundled and installed"
        $pythonBin = Join-Path -Path $destBin -ChildPath "python.exe"
        & $pythonBin -m ensurepip --upgrade
        if ($LastExitCode -ne 0) {
            Write-Error "Error ensuring pip"
            Exit [ExitCodes]::EnsurePip
        }
    }

    if( $arch -ne [Arch]::arm64) {
        # no wxpython on arm64 due to reqs not existing for the arch
        $wxRequirements = Join-Path -Path $PSScriptRoot -ChildPath "\support\wxrequirements.txt"

        Write-Host "Making sure the wxPython requirements are included"
        & $pythonBin -m pip install -r $wxRequirements
        if ($LastExitCode -ne 0) {
            Write-Error "Error installing wxpython requirements"
            Exit [ExitCodes]::WxPythonRequirements
        }

        $extraRequirements = Join-Path -Path $PSScriptRoot -ChildPath "\support\extrarequirements.txt"

        Write-Host "Making sure the wxPython requirements are included"
        & $pythonBin -m pip install -r $extraRequirements
        if ($LastExitCode -ne 0) {
            Write-Error "Error installing extra requirements"
            Exit [ExitCodes]::ExtraRequirements
        }
    }

    ### patch python manifest
    Patch-Python-Manifest -PythonRoot $destBin

    ## now libxslt
    $xsltprocSource = "$vcpkgInstalledRootPrimary\tools\libxslt\xsltproc.exe"
    Write-Host "Copying $xsltprocSource to $destBin"
    Copy-Item $xsltprocSource -Destination $destBin -Recurse  -Force

    if( $sign ) {
        Get-ChildItem $destBin -Recurse -Filter *.exe |
        Foreach-Object {
            Sign-File -File $_.FullName
        }
        
        Get-ChildItem $destBin -Recurse -Filter *.dll |
        Foreach-Object {
            Sign-File -File $_.FullName
        }
        
        Get-ChildItem $destBin -Recurse -Filter *.kiface |
        Foreach-Object {
            Sign-File -File $_.FullName
        }
        
        # python
        Get-ChildItem $destBin -Recurse -Filter *.pyd |
        Foreach-Object {
            Sign-File -File $_.FullName
        }
        
        # ngspice
        Get-ChildItem $ngspiceDestLib -Recurse -Filter *.cm |
        Foreach-Object {
            Sign-File -File $_.FullName
        }
    }

    Write-Host "Package prep complete" -ForegroundColor Green
}

function script:Patch-Python-Manifest([string]$PythonRoot) {
    $pythonManifest = Join-Path -Path $PSScriptRoot -ChildPath "\support\python.manifest"

    & mt.exe -nologo -manifest $pythonManifest -outputresource:"$PythonRoot\python.exe;#1"
    if ($LastExitCode -ne 0) {
        Write-Error "Error patching python manifest"
        Exit [ExitCodes]::PythonManifestPatchFailure
    }
}

function Start-Package-Nsis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch,
        [Parameter(Mandatory=$False)]
        [ValidateSet('Release', 'Debug')]
        [string]$buildType = "Release",
        [Parameter(Mandatory=$False)]
        [bool]$includeVcpkgDebugSymbols = $False,
        [Parameter(Mandatory=$False)]
        [bool]$lite = $False,
        [Parameter(Mandatory=$False)]
        [bool]$postCleanup = $False,
        [Parameter(Mandatory=$False)]
        [bool]$sign = $False
    )

    $packageVersion = Get-KiCad-PackageVersion
    $kicadVersion = Get-KiCad-Version

    $nsisArch = Get-NSISArch -Arch $arch

    Write-Host "Package Version: $packageVersion"
    Write-Host "KiCad Version: $kicadVersion"
    if($lite) {
        Write-Host "Lite package"
    }
    else {
        Write-Host "Full package"
    }

    $buildName = Get-Build-Name -Arch $arch -BuildType $buildType

    $destRoot = Join-Path -Path $PSScriptRoot -ChildPath ".out\$buildName\"

    ## now nsis
    $nsisSource = Join-Path -Path $PSScriptRoot -ChildPath "nsis\"
    Write-Host "Copying nsis $nsisSource to $nsisDest"
    Copy-Item $nsisSource -Destination $destRoot -Recurse -Container -Force

    ## Run NSIS
    $nsisScript = Join-Path -Path $destRoot -ChildPath "nsis\$($buildConfig.nsis.file)"

    Write-Host "Copying LICENSE.README as copyright.txt"

    $readmeSrc = Join-Path -Path (Get-Source-Path kicad) -ChildPath "LICENSE.README"
    Copy-Item $readmeSrc -Destination "$destRoot\COPYRIGHT.txt" -Force

    $outTags = ""
    if( $buildType -eq 'Debug' )
    {
        $outTags = '-dbg'
    }

    if( $lite ) {
        $outTags = "$outTags-lite"
    }

    $outFileName = "$($buildConfig.output_prefix)$packageVersion-$nsisArch$outTags.exe"
    
    $destKicadShare = Join-Path -Path $destRoot -ChildPath "share\kicad"

    if( $lite )
    {
        # needed for lite mode to enable footprints and symbols, why? who knows for now
        New-Item -ItemType "directory" -Path (Join-Path -Path $destKicadShare -ChildPath "\footprints")
        New-Item -ItemType "directory" -Path (Join-Path -Path $destKicadShare -ChildPath "\symbols")
        
        $libRefName = "master";
        # out of laziness we will just use the symbol ref as the ref for all libraries download in the lite
        if( $buildConfig.sources.symbols.ref ) {
            if( $buildConfig.sources.symbols.ref.StartsWith("branch/") ) {
                $libRefName = $buildConfig.sources.symbols.ref.Replace("branch/", "")
            }
            elseif ( $buildConfig.sources.symbols.ref.StartsWith("tag/") ) {
                $libRefName = $buildConfig.sources.symbols.ref.Replace("tag/", "")
            }
        }

        makensis /DPACKAGE_VERSION=$packageVersion `
            /DKICAD_VERSION=$kicadVersion `
            /DOUTFILE="..\..\$outFileName" `
            /DARCH="$nsisArch" `
            /DLIBRARIES_TAG="$libRefName" `
            /DMSVC `
            "$nsisScript"
    }
    else
    {
        makensis /DPACKAGE_VERSION=$packageVersion `
            /DKICAD_VERSION=$kicadVersion `
            /DOUTFILE="..\..\$outFileName" `
            /DARCH="$nsisArch" `
            /DMSVC `
            "$nsisScript"
    }

    if($postCleanup) {
        $nsisFolder = Join-Path -Path $destRoot -ChildPath "nsis"
        Remove-Item $nsisFolder -Recurse -Force
    }

    if($sign) {
        Sign-File -File (Join-Path -Path $BuilderPaths.OutRoot -ChildPath $outFileName)
    }

    if ($LastExitCode -ne 0) {
        Write-Error "Error building nsis package"
        Exit [ExitCodes]::NsisFailure
    }

}

function Start-Package-Pdb() {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch,
        [Parameter(Mandatory=$False)]
        [ValidateSet('Release', 'Debug')]
        [string]$buildType = "Release"
    )
    
    $triplet = Get-Vcpkg-Triplet -Arch $arch
    $buildName = Get-Build-Name -Arch $arch -BuildType $buildType
    $sourceFolder = Join-Path -Path $PSScriptRoot -ChildPath ".out\$buildName-pdb\"
    
    $sourceFolder = Join-Path -Path $PSScriptRoot -ChildPath ".out\$buildName-pdb\"

    $packageVersion = Get-KiCad-PackageVersion
    $kicadVersion = Get-KiCad-Version

    $nsisArch = Get-NSISArch -Arch $arch
    $programPdbOutFileName = "$($buildConfig.output_prefix)$packageVersion-$nsisArch-pdbs.zip"

    $programPdbOutPath = Join-Path -Path $BuilderPaths.OutRoot -ChildPath $programPdbOutFileName

    7za a -tzip -mm=lzma -bsp0 $programPdbOutPath $sourceFolder
    
    if ($LastExitCode -ne 0) {
        Write-Error "Error packaging PDBs"
        Exit [ExitCodes]::PdbPackageFail
    }

    $vcpkgPdbSource = Join-Path -Path (Get-Source-Path kicad) -ChildPath "build/$buildName/vcpkg_installed/$triplet/"
    if($buildType -eq 'Release') {
        $vcpkgPdbSource = Join-Path -Path $vcpkgPdbSource -ChildPath "bin";
    } else {
        $vcpkgPdbSource = Join-Path -Path $vcpkgPdbSource -ChildPath "debug/bin";
    }

    $vcpkgPdbOutFileName = "$($buildConfig.output_prefix)$packageVersion-$nsisArch-vcpkg-pdbs.zip"
    $vcpkgPdbOutPath = Join-Path -Path $BuilderPaths.OutRoot -ChildPath $vcpkgPdbOutFileName

    7za a -tzip -mm=lzma -bsp0 $vcpkgPdbOutPath $vcpkgPdbSource
    
    if ($LastExitCode -ne 0) {
        Write-Error "Error packaging vcpkg PDBs"
        Exit [ExitCodes]::PdbPackageFail
    }

}

function Create-AppxManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$SourcePath,
        [Parameter(Mandatory=$True)]
        [string]$DestPath,
        [Parameter(Mandatory=$True)]
        [string]$KiCadVersion,
        [Parameter(Mandatory=$True)]
        [string]$Arch,
        [Parameter(Mandatory=$True)]
        [string]$PackageVersion,
        [Parameter(Mandatory=$True)]
        [string]$IdentityPublisher,
        [Parameter(Mandatory=$True)]
        [string]$IdentityName,
        [Parameter(Mandatory=$True)]
        [string]$PublisherDisplayName
    )

    $manifest = Get-Content -Path $SourcePath

    $manifest = $manifest.replace("[PACKAGE_VERSION]", $PackageVersion)
    $manifest = $manifest.replace("[ARCH]", $Arch)
    $manifest = $manifest.replace("[KICAD_VERSION]", $KiCadVersion)
    

    $manifest = $manifest.replace("[IDENTITY_PUBLISHER]", $IdentityPublisher)
    $manifest = $manifest.replace("[IDENTITY_NAME]", $IdentityName)
    $manifest = $manifest.replace("[PUBLISHER_DISPLAY_NAME]", $PublisherDisplayName)
    Set-Content -Path $DestPath -Value $manifest
}

function Start-Package-Msix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch,
        [Parameter(Mandatory=$False)]
        [ValidateSet('Release', 'Debug')]
        [string]$buildType = "Release",
        [Parameter(Mandatory=$False)]
        [bool]$includeVcpkgDebugSymbols = $False,
        [Parameter(Mandatory=$False)]
        [bool]$lite = $False,
        [Parameter(Mandatory=$False)]
        [bool]$postCleanup = $False,
        [Parameter(Mandatory=$False)]
        [string]$version = ""
    )

    # need msix packaging tools
    Set-MSVCEnvironment -Arch $arch -VersionMin $settings.VsVersionMin -VersionMax $settings.VsVersionMax
    
    # TODO handle this better for nightlies
    $packageVersion = Get-KiCad-PackageVersion-Msix
    $kicadVersion = Get-KiCad-Version

    Write-Host "Package Version: $packageVersion"
    Write-Host "KiCad Version: $kicadVersion"
    if($lite) {
        Write-Host "Lite package"
    }
    else {
        Write-Host "Full package"
    }

    $buildName = Get-Build-Name -Arch $arch -BuildType $buildType

    $buildSource = Join-Path -Path $PSScriptRoot -ChildPath ".out\$buildName\"

    $destRoot = Join-Path -Path $BuilderPaths.OutRoot -ChildPath "\msix-$buildName"
    $destRootVfs = Join-Path -Path $destRoot -ChildPath "\VFS\ProgramFilesX64\KiCad\5.99\"

    if( -not (Test-Path $destRootVfs) )
    {
        New-Item -Path $destRootVfs -ItemType "directory"
    }

    Copy-Item "${buildSource}\*" -Destination $destRootVfs -Recurse -Force


    ## now nsis
    $msixSource = Join-Path -Path $PSScriptRoot -ChildPath "msix\$version"
    Write-Host "Copying msix $msixSource to $destRoot"
    Copy-Item "${msixSource}\*" -Exclude "*.template" -Destination $destRoot -Recurse -Force

    $msixManifestSource = Join-Path -Path $PSScriptRoot -ChildPath "msix\$version\AppxManifest.xml.template"
    $msixManifestDest= Join-Path -Path $destRoot -ChildPath "AppxManifest.xml" 
    Create-AppxManifest -SourcePath $msixManifestSource `
                        -DestPath $msixManifestDest `
                        -KiCadVersion $kicadVersion `
                        -PackageVersion $packageVersion `
                        -Arch "x64" `
                        -IdentityPublisher "CN=069DD09B-C97F-4C04-9248-7A7FA0D53E48" `
                        -IdentityName "KiCad.KiCad" `
                        -PublisherDisplayName "KiCad Services Corporation"

    $priFilePath = Join-Path -Path $destRoot -ChildPath "priconfig.xml"
    #makepri createconfig /cf priconfig.xml /dq en-US
    Push-Location $destRoot
    Write-Host "Running makepri"
    makepri new /pr "$destRoot" /cf "$priFilePath" /o
    if( $LastExitCode -ne 0 )
    {
        Write-Error "Error generating resource pack"
        Exit [ExitCodes]::MakePriFailure
    }
    Pop-Location
    
    Write-Host "Running makeappx"
    $outFileName = "$($buildConfig.output_prefix)$packageVersion-$arch.msix"
    $outFilePath = Join-Path -Path $BuilderPaths.OutRoot -ChildPath $outFileName
    makeappx pack /d "$destRoot" /p "$outFilePath" /o 
    if( $LastExitCode -ne 0 )
    {
        Write-Error "Error generating appx package"
        Exit [ExitCodes]::MakeAppxFailure
    }

    Write-Host "Msix built!" -ForegroundColor Green
    if( $postCleanup )
    {
        Write-Host "Cleanup: Removing intermediate build folder $destRoot"
        Remove-Item $destRoot -Recurse -ErrorAction SilentlyContinue
    }
}


function Generate-Msix-Assets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$version
    )


    $iconSources = Join-Path -Path $PSScriptRoot -ChildPath "msix\$version\bundleassets\sources\"

    if( -not (Test-Path $iconSources) )
    {
        Write-Error "Version icon msix icon sources do not exist"
        Exit [ExitCodes]::InvalidMsixVersion
    }

    
    $iconDest = Join-Path -Path $PSScriptRoot -ChildPath "msix\$version\bundleassets\png\"

    Remove-Item $iconDest -Recurse -ErrorAction SilentlyContinue
    New-Item $iconDest -ItemType "directory"

    $kicadStoreIconSource = Join-Path -Path $iconSources -ChildPath "icon_kicad.svg"
    $kicadStoreIconDest = Join-Path -Path $iconSources -ChildPath "icon_kicad_store.svg"
    Convert-Svg -Svg $kicadStoreIconSource -Width 300 -Height 300 -Out "$iconDest/icon_kicad_store.png"

    $icons = Get-ChildItem $iconSources -Filter icon*.svg
    foreach ($f in $icons){
        $basePath = "$iconDest/$($f.BaseName)"
        New-TileIcons  -Svg $f.FullName -Out $basePath
    }
    
}


function Set-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$False)]
        [string]$VcpkgPath,
        [Parameter(Mandatory=$False)]
        [bool]$UseMsvcCmake,
        [Parameter(Mandatory=$False)]
        [string]$SentryDsn
    )

    if( $VcpkgPath -ne "" ) {
        $settings.VcpkgPath = $VcpkgPath
        if ( -Not (Test-Path $VcpkgPath) ) {
            Write-Error "Invalid vcpkg path"
            Exit [ExitCodes]::ConfigError
        }
    }

    $settings.UseMsvcCmake = $UseMsvcCmake

    if( $VcpkgPath -ne "" ) {
        $settings.SentryDsn = $SentryDsn
    }

    $settings | ConvertTo-Json -Compress | Set-Content -Path $settingsPath
}


function Start-Env {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch
    )

    Write-Host "Setting up build environment" -ForegroundColor Green

    Start-Init

    Set-MSVCEnvironment -Arch $arch -VersionMin $settings.VsVersionMin -VersionMax $settings.VsVersionMax
}



###
# Decode and execute the selected script stage
###

if( $Config )
{
    Set-Config -VcpkgPath $VcpkgPath -UseMsvcCmake $UseMsvcCmake -SentryDsn $SentryDsn
}

if( $Init )
{
    Start-Init
}

if( $Env )
{
    Start-Env -arch $Arch
}

if( $Vcpkg )
{
    Build-Vcpkg -arch $Arch -latest $True
}

if( $Build )
{
    Start-Build -arch $Arch -buildType $buildConfig.build_mode -latest $Latest
}

if( $MsixAssets )
{
    Generate-Msix-Assets -version $Version
}

if( $PreparePackage -or ($Package -and $Prepare) )
{
    Start-Prepare-Package -arch $Arch -buildType $buildConfig.build_mode -includeVcpkgDebugSymbols $false -lite $Lite -sign $Sign -sentryArtifact $SentryArtifact
}

if( $PackageSentry )
{
    Start-Bundle-Sentry -arch $Arch -buildType $buildConfig.build_mode
}

if( $Package )
{
    if( $PackType -eq 'nsis' )
    {
        Start-Package-Nsis -arch $Arch -buildType $buildConfig.build_mode -includeVcpkgDebugSymbols $false -lite $Lite -postCleanup $PostCleanup -sign $Sign
    }
    elseif( $PackType -eq 'msix' )
    {
        if( $Lite )
        {
            Write-Error "-Lite switched not supported for Msix build types"
            Exit [ExitCodes]::UnsupportedSwitch
        }

        Start-Package-Msix -arch $Arch -buildType $BuildType -includeVcpkgDebugSymbols $IncludeVcpkgDebugSymbols -version $Version -postCleanup $PostCleanup
    }
    
    if( $DebugSymbols )
    {
        Start-Package-Pdb -arch $Arch -buildType $buildConfig.build_mode
    }
}
