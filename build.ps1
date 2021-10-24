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
    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [Parameter(Mandatory=$False, ParameterSetName="preparepackage")]
    [ValidateSet('Release', 'Debug')]
    [string]$BuildType = 'Release',

    [Parameter(Mandatory=$True, ParameterSetName="config")]
	[ValidateScript({Test-Path $_})]
    [string]$VcpkgPath,

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
    [bool]$PostCleanup = $False
)

enum Arch {
    x86
    x64
    arm
    arm64
}

enum ExitCodes {
    Ok = 0
    DownloadChecksumFailure = 1
    VcpkgInstallPortsFailure = 2
    CMakeGenerationFailure = 3
    CMakeBuildFailure = 4
    CMakeInstallFailure = 5
    NsisFailure = 6
    DownloadExtractFailure = 7
    GitCloneFailure = 8
    EnsurePip = 9
    WxPythonRequirements = 10
    GitResetFailure = 11
    GitCleanFailure = 12
    GitPullRebaseFailure = 13
    UnsupportedSwitch = 14
    InkscapeSvgConversion = 15
    InvalidMsixVersion = 16
    MakePriFailure = 17
    MakeAppxFailure = 18
    SignFail = 19
    PdbPackageFail = 20
    PythonManifestPatchFailure = 21
}

# Load the .NET compression library, powershell's expand-archive is horrid in performance
Add-Type -Assembly 'System.IO.Compression.FileSystem'

###
## Base setup
###

$cmakeFolder = 'cmake-3.16.6-win64-x64'
$cmakeDownload = 'https://github.com/Kitware/CMake/releases/download/v3.16.6/cmake-3.16.6-win64-x64.zip'
$cmakeChecksum = "9C06EEFCCD9B4B24B386573C05EAABEF6AFD756DC692E896C415EB0CD1FB132D"

$vswhereDownload = 'https://github.com/microsoft/vswhere/releases/download/2.8.4/vswhere.exe'
$vswhereChecksum = "E50A14767C27477F634A4C19709D35C27A72F541FB2BA5C3A446C80998A86419"

$swigwinFolder = "swigwin-4.0.2"
$swigwinDownload = "https://sourceforge.net/projects/swig/files/swigwin/$swigwinFolder/$swigwinFolder.zip/download?use_mirror=pilotfiber"
$swigwinChecksum = "DAADB32F19FE818CB9B0015243233FC81584844C11A48436385E87C050346559"

$nsisDownload = "https://sourceforge.net/projects/nsis/files/NSIS%203/3.06.1/nsis-3.06.1.zip/download"
$nsisChecksum = "D463AD11AA191AB5AE64EDB3A439A4A4A7A3E277FCB138254317254F7111FBA7"

$gettextFolderName = "gettext0.21-iconv1.16-static-64"
$gettextDownload = "https://github.com/mlocati/gettext-iconv-windows/releases/download/v0.21-v1.16/gettext0.21-iconv1.16-static-64.zip"
$gettextChecksum = "721395C2E057EEED321F0C793311732E57CB4FA30D5708672A13902A69A77D43"

$doxygenDownload = "https://doxygen.nl/files/doxygen-1.9.1.windows.x64.bin.zip"
$doxygenChecksum = "DEB8E6E5F21C965EC07FD32589D0332EFF047F2C8658B5C56BE4839A5DD43353"
$doxygenFolderName = "doxygen-1.9.1.windows.x64.bin"

$7zaFolderName = "7z2102-extra"

$downloadsPathRoot = ($PSScriptRoot+"/.downloads/")
$supportPathRoot = ($PSScriptRoot+"/.support/")
$buildPathRoot = ($PSScriptRoot+"/.build/")
$outPathRoot = ($PSScriptRoot+"/.out/")

if( -not (Test-Path $downloadsPathRoot) )
{
    New-Item $downloadsPathRoot -ItemType "directory"
}

if( -not (Test-Path $supportPathRoot ) )
{
    New-Item $supportPathRoot -ItemType "directory"
}

if( -not (Test-Path $buildPathRoot ) )
{
    New-Item $buildPathRoot -ItemType "directory"
}

if( -not (Test-Path $outPathRoot ) )
{
    New-Item $outPathRoot -ItemType "directory"
}


$swigWinPath = ($supportPathRoot+"/$swigwinFolder")
$gettextPath = ($supportPathRoot+"/$gettextFolderName/bin")
$doxygenPath = ($supportPathRoot+"/$doxygenFolderName")
$nsisPath = Join-Path -Path $supportPathRoot -ChildPath "nsis/bin/"

$env:Path = $swigWinPath+";"+$gettextPath+";"+$nsisPath+";"+$doxygenPath+";"+$env:PATH


# Use TLS1.2 by force in case of older powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Force git output to go to stdout or else powershell eats it and doesn't show us it
$env:GIT_REDIRECT_STDERR='2>&1'


###
# Load and handle Config
###
$settingsPath = $PSScriptRoot + "\settings.json";

$settingDefault = @{
    VcpkgPath = ''
    VcpkgPlatformToolset = 'v142'
    VsVersion = '16.0'
    SignSubjectName = 'KiCad Services Corporation'
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

function Merge-HashTable {
    param(
        [hashtable] $default,
        [hashtable] $uppend
    )

    # Clone for idempotence
    $defaultClone = $default.Clone();

    # Remove keys that exist in both uppend and default from default
    foreach ($key in $uppend.Keys) {
        if ($defaultClone.ContainsKey($key)) {
            $defaultClone.Remove($key);
        }
    }

    # Union both sets
    return $defaultClone + $uppend;
}

$settings = Merge-HashTable -default $settingDefault -uppend $settingsSaved


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
        $tmp = Join-Path -Path $supportPathRoot -ChildPath "vswhere.exe"
        Set-Alias vswhere $tmp -Option AllScope -Scope Global
    }

    if( -not (Test-Path alias:cmake ) )
    {
        $tmp = Join-Path -Path $supportPathRoot -ChildPath "$cmakeFolder/bin/cmake.exe"
        Set-Alias cmake $tmp -Option AllScope -Scope Global
    }

    if( -not (Test-Path alias:makensis ) )
    {
        $tmp = Join-Path -Path $supportPathRoot -ChildPath "nsis/bin/makensis.exe"
        Set-Alias makensis $tmp -Option AllScope -Scope Global
    }
    
    if( -not (Test-Path alias:7za ) )
    {
        $tmp = Join-Path -Path $supportPathRoot -ChildPath "$7zaFolderName/7za.exe"
        Set-Alias 7za $tmp -Option AllScope -Scope Global
    }
}

## Invoke it
Set-Aliases

###
# General functions
##

function Get-MSVC-Arch()
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [Arch]$Arch
    )

    $msvc = "amd64"
    switch ($Arch)
    {
        ([Arch]::x64) {
            $msvc = "amd64"
            break
        }
        ([Arch]::x86) {
            $msvc = "x86"
            break
        }
        ([Arch]::arm) {
            $msvc = "arm"
            break
        }
        ([Arch]::arm64) {
            $msvc = "arm64"
            break
        }
    }

    return $msvc
}

function Get-NSIS-Arch()
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [Arch]$Arch
    )

    $nsis = ""
    switch ($Arch)
    {
        ([Arch]::x64) {
            $nsis = "x86_64"
            break
        }
        ([Arch]::x86) {
            $nsis = "i686"
            break
        }
        ([Arch]::arm) {
            $nsis = "arm"
            break
        }
        ([Arch]::arm64) {
            $nsis = "arm64"
            break
        }
    }

    return $nsis
}

function Set-VC-Environment()
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [Arch]$Arch = [Arch]::x64,
        [Parameter()]
        [Arch]$HostArch = [Arch]::x64,
        [string[]]
        [Parameter(ValueFromRemainingArguments=$true)]
        $Arguments
    )

    if($env:VSCMD_VER)
    {
        Write-Host "VS Environment already configured" -ForegroundColor Yellow
        return
    }

    $msvcArch = Get-MSVC-Arch -Arch $Arch
    $msvcHostArch = Get-MSVC-Arch -Arch $HostArch

    # prepare the arguments array with the arch info
    $Arguments = @("-arch=$msvcArch") + @("-host_arch=$msvcHostArch") + $Arguments

    $version = $settings.VsVersion
    $installDir = vswhere -version "$version" -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath

    $installDir = $installDir | Select-Object -first 1
    if ($installDir) {
        $path = join-path $installDir 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt'
        if (test-path $path) {
            $version = gc -raw $path
            if ($version) {
                $version = $version.Trim()
                $path = join-path $installDir "Common7\tools\VsDevCmd.bat"
                $argString = $Arguments -join ' '

                Write-Host "Selecting MSVC $version found at $installDir" -ForegroundColor Yellow

                # what is this scary thing?
                # We need to capture the environment variables set by vsdevcmd.bat
                # We use json as an intermediate or else it may get broken by environment variables with spaces in them, json keeps the variables in tact
                $json = $(& "${env:COMSPEC}" /s /c "`"$path`" -no_logo $argString && powershell -Command `"Get-ChildItem env: | Select-Object Key,Value | ConvertTo-Json`"")
                if  (!$?) {
                    Write-Error "Error extracting vsdevcmd.bat environment variables: $LASTEXITCODE"
                } else {
                    $($json | ConvertFrom-Json) | ForEach-Object {
                        $k, $v = $_.Key, $_.Value
                        Set-Content env:\"$k" "$v"
                    }
                }
            }
        }
    }

}

function Get-Absolute-Path($relativePath)
{
  $path = Resolve-Path -Path $relativePath | Select-Object -ExpandProperty Path

  return $path
}

function Reset-Env {
    Set-Item `
        -Path (('Env:', $args[0]) -join '') `
        -Value ((
            [System.Environment]::GetEnvironmentVariable($args[0], "Machine"),
            [System.Environment]::GetEnvironmentVariable($args[0], "User")
        ) -match '.' -join ';')
}

function Reset-Env-Path {
    Reset-Env Path
}

enum SourceType {
    git
    tar
}

function Get-Source {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$url,
        [Parameter(Mandatory=$True)]
        [string]$dest,
        [Parameter(Mandatory=$True)]
        [SourceType]$sourceType,
        [Parameter(Mandatory=$False)]
        [bool]$latest = $False
    )

    if(![System.IO.Directory]::Exists($dest))
    {
        if($sourceType -eq [SourceType]::git)
        {
            & git clone "$url" "$dest"

            if ($LastExitCode -ne 0) {
                Write-Error "Error cloning kicad repo"
                Exit [ExitCodes]::GitCloneFailure
            }
        }
        elseif($sourceType -eq [SourceType]::tar)
        {

        }
    }
    elseif($latest)
    {
        if($sourceType -eq [SourceType]::git)
        {
            git -C "$dest" reset --hard
            if ($LastExitCode -ne 0) {
                Write-Error "Error git reset"
                Exit [ExitCodes]::GitResetFailure
            }

            git -C "$dest" clean -f
            
            if ($LastExitCode -ne 0) {
                Write-Error "Error git clean"
                Exit [ExitCodes]::GitCleanFailure
            }

            git -C "$dest" pull --rebase

            if ($LastExitCode -ne 0) {
                Write-Error "Error pull rebase"
                Exit [ExitCodes]::GitPullRebaseFailure
            }
        }
        elseif($sourceType -eq [SourceType]::tar)
        {

        }
    }


}

function Get-Source-Path([string]$subfolder) {
    return Join-Path -Path $buildPathRoot -ChildPath $subfolder
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

    $buildName = Get-Build-Name -Arch $arch -BuildType $buildType
    $installPath = Join-Path -Path $outPathRoot -ChildPath "$buildName/"

    $cmakeBuildFolder = "build/$buildName"
    $generator = "Ninja"

    & {
        $ErrorActionPreference = 'SilentlyContinue'
        cmake -G $generator `
            -B $cmakeBuildFolder `
            -S .  `
            -DCMAKE_INSTALL_PREFIX="$installPath" `
            -DCMAKE_RULE_MESSAGES:BOOL="OFF" `
            -DCMAKE_VERBOSE_MAKEFILE:BOOL="OFF" `
            2>&1 | % ToString
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
        [string]$buildType = 'Release'
    )

    $buildName = Get-Build-Name -Arch $arch -BuildType $buildType

    #step down into kicad folder
    Push-Location (Get-Source-Path kicad)

    $cmakeBuildFolder = "build/$buildName"

    Write-Host "Invoking cmake install" -ForegroundColor Yellow
    & {
        $ErrorActionPreference = 'SilentlyContinue'
        cmake --install $cmakeBuildFolder > $null
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

    Set-VC-Environment -Arch $arch

    $cmakeBuildFolder = "build/$buildName"
    $generator = "Ninja"

    #delete the old build folderhttps://gitlab.com/kicad/code/kicad.git
    if($fresh)
    {
        Remove-Item $cmakeBuildFolder -Recurse -ErrorAction SilentlyContinue
    }


    $installPath = Join-Path -Path $outPathRoot -ChildPath "$buildName/"
    $toolchainPath = Join-Path -Path $settings["VcpkgPath"] -ChildPath "/scripts/buildsystems/vcpkg.cmake"
    $installPdbPath = Join-Path -Path $outPathRoot -ChildPath "$buildName-pdb"

    Write-Host "Starting build"
    Write-Host "arch: $arch"
    Write-Host "buildType: $buildType"
    Write-Host "Configured install directory: $installPath"
    Write-Host "Vcpkg Path: $toolchainPath"

    # ignore cmake dumping to stderr
    # the boost warnings will cause it to treat it as a failed command
    & {
        $ErrorActionPreference = 'SilentlyContinue'
        cmake -G $generator `
            -Wno-dev `
            -B $cmakeBuildFolder `
            -S .  `
            -DCMAKE_BUILD_TYPE="$buildType" `
            -DCMAKE_TOOLCHAIN_FILE="$toolchainPath" `
            -DCMAKE_INSTALL_PREFIX="$installPath" `
            -DCMAKE_PDB_OUTPUT_DIRECTORY:PATH="$installPdbPath" `
            -DKICAD_SPICE="ON" `
            -DKICAD_USE_OCC="ON" `
            -DKICAD_SCRIPTING_WXPYTHON="ON" `
            -DKICAD_BUILD_QA_TESTS="OFF" `
            -DKICAD_WIN32_DPI_AWARE="ON" `
            -DKICAD_BUILD_I18N="ON" `
            2>&1 | % ToString
    }

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
               -latest $latest

    Get-Source -url https://gitlab.com/kicad/libraries/kicad-symbols.git `
               -dest (Get-Source-Path kicad-symbols) `
               -sourceType git `
               -latest $latest

    Get-Source -url https://gitlab.com/kicad/libraries/kicad-footprints.git `
               -dest (Get-Source-Path kicad-footprints) `
               -sourceType git `
               -latest $latest

    Get-Source -url https://gitlab.com/kicad/libraries/kicad-packages3D.git `
               -dest (Get-Source-Path kicad-packages3D) `
               -sourceType git `
               -latest $latest

    Get-Source -url https://gitlab.com/kicad/libraries/kicad-templates.git `
               -dest (Get-Source-Path kicad-templates) `
               -sourceType git `
               -latest $latest

    Build-KiCad -arch $arch -buildType $buildType
    Build-Library-Source -arch $arch -buildType $buildType -libraryFolderName kicad-symbols
    Build-Library-Source -arch $arch -buildType $buildType -libraryFolderName kicad-footprints
    Build-Library-Source -arch $arch -buildType $buildType -libraryFolderName kicad-packages3D
    Build-Library-Source -arch $arch -buildType $buildType -libraryFolderName kicad-templates
}

function Unzip([string] $zip, [string] $dest) {
    Write-Host "Extracting $zip to $dest"
    Try
    {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $dest)
    }
    Catch
    {
        Write-Error "Error trying to extract $zip"
        Exit [ExitCodes]::DownloadExtractFailure
    }
}

function Extract-Tool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$ToolName,
        [Parameter(Mandatory=$True)]
        [string]$SourcePath,
        [Parameter(Mandatory=$True)]
        [string]$DestPath,
        [Parameter(Mandatory=$False)]
        [bool]$ZipRelocate = $False,
        [Parameter(Mandatory=$False)]
        [string]$ZipRelocateFilter = "",
        [Parameter(Mandatory=$False)]
        [bool]$ExtractInSupportRoot = $False
    )

    if( -not (Test-Path $DestPath) )
    {
        Write-Host "Extracting $ToolName" -ForegroundColor Yellow
        if( $ExtractInSupportRoot )
        {
            Unzip $SourcePath $supportPathRoot
        }
        else
        {
            Unzip $SourcePath $DestPath
        }

        if (!$?) {
            Write-Error "Unable to extract $ToolName"
            Exit 2
        }

        if( $ZipRelocate )
        {
            $folders = Get-ChildItem $ZipRelocateFilter -Directory
            Move-Item $folders $DestPath
        }
    }
    else
    {
        Write-Host "$ToolName already exists" -ForegroundColor Green
    }
}

function Get-Tool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$ToolName,
        [Parameter(Mandatory=$True)]
        [string]$Url,
        [Parameter(Mandatory=$True)]
        [string]$DestPath,
        [Parameter(Mandatory=$True)]
        [string]$DownloadPath,
        [Parameter(Mandatory=$True)]
        [string]$Checksum,
        [Parameter(Mandatory=$False)]
        [bool]$ExtractZip = $False,
        [Parameter(Mandatory=$False)]
        [bool]$ZipRelocate = $False,
        [Parameter(Mandatory=$False)]
        [string]$ZipRelocateFilter = "",
        [Parameter(Mandatory=$False)]
        [bool]$ExtractInSupportRoot = $False
    )

    if( -not (Test-Path $DestPath) )
    {
        Write-Host "Downloading $ToolName..." -ForegroundColor Yellow

        Invoke-WebRequest -Uri $Url -OutFile $DownloadPath -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox

        $calculatedChecksum = ( Get-FileHash -Algorithm SHA256 $DownloadPath ).Hash
        if( $calculatedChecksum -ne $Checksum )
        {
            Remove-Item -Path $DownloadPath -ErrorAction SilentlyContinue
            Write-Error "Invalid checksum for $ToolName, expected: $cmakeChecksum actual: $calculatedChecksum"

            Exit [ExitCodes]::DownloadChecksumFailure
        }

        if( $ExtractZip )
        {
            Write-Host "Extracting $ToolName" -ForegroundColor Yellow
            if( $ExtractInSupportRoot )
            {
                Unzip $DownloadPath $supportPathRoot
            }
            else
            {
                Unzip $DownloadPath $DestPath
            }

            if (!$?) {
                Write-Error "Unable to extract $ToolName"
                Exit 2
            }

            if( $ZipRelocate )
            {
                $folders = Get-ChildItem $ZipRelocateFilter -Directory
                Move-Item $folders $DestPath
            }
        }
        else
        {
            Move-Item $DownloadPath $DestPath
        }
    }
    else
    {
        Write-Host "$ToolName already exists" -ForegroundColor Green
    }
}


function Start-Init {
    # The progress bar slows down download performance by absurd amounts, turn it off
    $ProgressPreference = 'SilentlyContinue'

    Get-Tool -ToolName "CMake" `
             -Url $cmakeDownload `
             -DestPath ($supportPathRoot+"$cmakeFolder/") `
             -DownloadPath ($downloadsPathRoot+"cmake.zip") `
             -Checksum $cmakeChecksum `
             -ExtractZip $true `
             -ZipRelocate $False `
             -ExtractInSupportRoot $True

    Get-Tool -ToolName "swigwin" `
             -Url $swigwinDownload `
             -DestPath ($supportPathRoot+"$swigwinFolder/") `
             -DownloadPath ($downloadsPathRoot+"$swigwinFolder.zip") `
             -Checksum $swigwinChecksum `
             -ExtractZip $true `
             -ExtractInSupportRoot $True

    Get-Tool -ToolName "doxygen" `
             -Url $doxygenDownload `
             -DestPath ($supportPathRoot+"$doxygenFolderName/") `
             -DownloadPath ($downloadsPathRoot+"$doxygenFolderName.zip") `
             -Checksum $doxygenChecksum `
             -ExtractZip $true `
             -ExtractInSupportRoot $False

    Get-Tool -ToolName "nsis" `
             -Url $nsisDownload `
             -DestPath ($supportPathRoot+'nsis/') `
             -DownloadPath ($downloadsPathRoot+"nsis.zip") `
             -Checksum $nsisChecksum `
             -ExtractZip $true `
             -ZipRelocate $True `
             -ZipRelocateFilter ($supportPathRoot+'nsis-*/') `
             -ExtractInSupportRoot $True

    Get-Tool -ToolName "vswhere" `
             -Url $vswhereDownload `
             -DestPath ($supportPathRoot+'vswhere.exe') `
             -DownloadPath ($downloadsPathRoot+"vswhere.exe") `
             -Checksum $vswhereChecksum `
             -ExtractZip $False

    Get-Tool -ToolName "gettext" `
             -Url $gettextDownload `
             -DestPath ($supportPathRoot+"$gettextFolderName/") `
             -DownloadPath ($downloadsPathRoot+"$gettextFolderName.zip") `
             -Checksum $gettextChecksum `
             -ExtractZip $true

    $7zaSource = Join-Path -Path $PSScriptRoot -ChildPath "\support\7z2102-extra.zip"
    Extract-Tool -ToolName "7za" `
             -SourcePath $7zaSource `
             -DestPath ($supportPathRoot+"$7zaFolderName/")

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
    if( $vcpkgPath -eq "" )
    {
        Write-Host "No vcpkg path provided" -ForegroundColor DarkYellow

        $vcpkgPath = Join-Path -Path $PSScriptRoot -ChildPath vcpkg

        # for now, destroy the folder if it isnt configured on our side
        if( Test-Path $vcpkgPath )
        {
            Remove-Item $vcpkgPath -Recurse -Force
        }

        Write-Host "Checking out vcpkg to $vcpkgPath" -ForegroundColor Yellow
        git clone https://gitlab.com/kicad/packaging/vcpkg.git $vcpkgPath

        Set-Config -VcpkgPath $vcpkgPath

        # get vcpkg alias updated
        Set-Aliases
    }

    # Bootstrap vcpkg
    Push-Location $vcpkgPath

    if( $latest )
    {
        Write-Host "Updating vcpkg git repo" -ForegroundColor Yellow

        git fetch
        git checkout kicad
        git reset --hard origin/kicad
    }

    .\bootstrap-vcpkg.bat

    # Setup dependencies
    $triplet = Get-Vcpkg-Triplet -Arch $arch


    $dependencies = @( "boost",
                        "pixman", # required for cairo
                        "cairo",
                        "curl",
                        "glew",
                        "gettext",
                        "glm",
                        "icu",
                        "libxslt",
                        "ngspice",
                        "opencascade",
                        "opengl",
                        "python3",
                        "wxwidgets",
                        "wxpython",
                        "zlib")

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

    Pop-Location
}

function Get-KiCad-PackageVersion {
    Push-Location (Get-Source-Path kicad)

    $revCount = (git rev-list --count --first-parent HEAD)
    $commitHash = (git rev-parse --short HEAD)

    Pop-Location

    return "msvc.r$revCount.$commitHash"
}

function Get-KiCad-Version {
    $srcFile = Join-Path -Path (Get-Source-Path kicad) -ChildPath "CMakeModules\KiCadVersion.cmake"
    $result = Select-String -Path $srcFile -Pattern '(?<=KICAD_SEMANTIC_VERSION\s")([0-9]+).([0-9])+' -AllMatches | % { $_.Matches } | % { $_.Value } | Select-Object -First 1

    return $result
}

function Get-KiCad-PackageVersion-Msix {

    $base = Get-KiCad-Version
    
    Push-Location (Get-Source-Path kicad)
    $revCount = (git rev-list --count --first-parent HEAD)
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

    signtool.exe sign /a /n "$($settings.SignSubjectName)" /fd sha256 /tr http://timestamp.sectigo.com /td sha256 /q $File

    if ($LastExitCode -ne 0) {
        Write-Error "Error signing file $File"
        Exit [ExitCodes]::SignFail
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
        [bool]$sign = $False
    )
    # Required for signing
    Set-VC-Environment -Arch $arch

    $packageVersion = Get-KiCad-PackageVersion
    $kicadVersion = Get-KiCad-Version

    $nsisArch = Get-NSIS-Arch -Arch $arch

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

    $vcpkgInstalledRoot = Join-Path -Path $settings["VcpkgPath"] -ChildPath "installed\$triplet\"
    $vcpkgInstalledRootPrimary = $vcpkgInstalledRoot
    $destRoot = Join-Path -Path $PSScriptRoot -ChildPath ".out\$buildName\"

    # Now delete the existing output content
    if( Test-Path $destRoot )
    {
        Remove-Item $destRoot -Recurse -Force
    }

    Install-Kicad -arch $arch -buildType $buildType

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

    # All libraries to copy _should use a wildcard at the end
    # This is to copy both the .dll and .pdb
    # Or only .dll based on switch
    $vcpkgBinCopy = @( "boost*",
                        "TK*",
                        "wx*",
                        "jpeg62*",
                        "libpng16*",
                        "tiff*",
                        "zlib*",
                        "libcurl*",
                        "python*",
                        "glew32*",
                        "cairo*",
                        "libexpat*",
                        "libexslt*", #xsltproc
                        "libxslt*",  #xsltproc
                        "libxml*",
                        "lzma*",
                        "fontconfig*",
                        "freetype*",
                        "bz2*",
                        "brotli*",
                        "charset*",
                        "libwebpmux*",
                        "libcrypto*",
                        "libssl*",
                        "libffi*",
                        "ngspice*",
                        "pthread*",
                        "turbojpeg*",
                        "zstd*",
                        "sqlite*",
                        "icu*",
                        "iconv*",
                        "intl*"
                    )


    $vcpkgInstalledBin = Join-Path -Path $vcpkgInstalledRoot -ChildPath "bin\"
    $destBin = Join-Path -Path $destRoot -ChildPath "bin\"
    $destLib = Join-Path -Path $destRoot -ChildPath "lib\"

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

    ## ngspice related
    $ngspiceLib = Join-Path -Path $vcpkgInstalledRoot -ChildPath "lib\ngspice"
    $ngspiceDestLib = Join-Path -Path $destLib -ChildPath "ngspice\"
    Write-Host "Copying ngspice lib $ngspiceLib to $destLib"
    Copy-Item $ngspiceLib -Destination $ngspiceDestLib -Recurse -Container  -Force

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
    Remove-Item (Join-Path -Path $destBin -ChildPath "\Scripts\") -Recurse

    $siteCustomizeSource = Join-Path -Path $PSScriptRoot -ChildPath "\support\sitecustomize.py"
    $siteCustomizeDest = Join-Path -Path $destBin -ChildPath "Lib/site-packages"
    Copy-Item $siteCustomizeSource -Destination $siteCustomizeDest -Force

    ### lets setup pip
    Write-Host "Ensuring pip is bundled and installed"
    $pythonBin = Join-Path -Path $destBin -ChildPath "python.exe"
    $wxRequirements = Join-Path -Path $PSScriptRoot -ChildPath "\support\wxrequirements.txt"
    & $pythonBin -m ensurepip --upgrade
    if ($LastExitCode -ne 0) {
        Write-Error "Error ensuring pip"
        Exit [ExitCodes]::EnsurePip
    }

    Write-Host "Making sure the wxPython requirements are included"
    & $pythonBin -m pip install -r $wxRequirements
    if ($LastExitCode -ne 0) {
        Write-Error "Error installing wxpython requirements"
        Exit [ExitCodes]::WxPythonRequirements
    }

    ### patch python manifest
    Patch-Python-Manifest -PythonRoot $destBin

    ## now libxslt
    $xsltprocSource = "$vcpkgInstalledRootPrimary\tools\libxslt\xsltproc.exe"
    Write-Host "Copying $xsltprocSource to $destBin"
    Copy-Item $xsltprocSource -Destination $destBin -Recurse  -Force

    if( $sign ) {
        Sign-File -File (Join-Path -Path $destBin -ChildPath "kicad.exe")
        Sign-File -File (Join-Path -Path $destBin -ChildPath "eeschema.exe")
        Sign-File -File (Join-Path -Path $destBin -ChildPath "pcbnew.exe")
        Sign-File -File (Join-Path -Path $destBin -ChildPath "gerbview.exe")
        Sign-File -File (Join-Path -Path $destBin -ChildPath "pl_editor.exe")
        Sign-File -File (Join-Path -Path $destBin -ChildPath "bitmap2component.exe")
        Sign-File -File (Join-Path -Path $destBin -ChildPath "pcb_calculator.exe")
        Sign-File -File (Join-Path -Path $destBin -ChildPath "kicad2step.exe")
    }

    Write-Host "Package prep complete" -ForegroundColor Green
}

function Patch-Python-Manifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$PythonRoot
    )

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

    $nsisArch = Get-NSIS-Arch -Arch $arch

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
    $nsisScript = Join-Path -Path $destRoot -ChildPath "nsis\install.nsi"

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

    $outFileName = "kicad-$packageVersion-$nsisArch$outTags.exe"
    
    $destKicadShare = Join-Path -Path $destRoot -ChildPath "share\kicad"

    if( $lite )
    {
        # needed for lite mode to enable footprints and symbols, why? who knows for now
        New-Item -ItemType "directory" -Path (Join-Path -Path $destKicadShare -ChildPath "\footprints")
        New-Item -ItemType "directory" -Path (Join-Path -Path $destKicadShare -ChildPath "\symbols")
        $liteGitTag = "master"
        $found = $packageVersion -match '^\d+\.\d+\.\d+'
        if ($found) {
            $liteGitTag = $matches[0]
        }

        makensis /DPACKAGE_VERSION=$packageVersion `
            /DKICAD_VERSION=$kicadVersion `
            /DOUTFILE="..\..\$outFileName" `
            /DARCH="$nsisArch" `
            /DLIBRARIES_TAG="$liteGitTag" `
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
        Sign-File -File (Join-Path -Path $outPathRoot -ChildPath $outFileName)
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
    
    $buildName = Get-Build-Name -Arch $arch -BuildType $buildType
    $sourceFolder = Join-Path -Path $PSScriptRoot -ChildPath ".out\$buildName-pdb\"

    $packageVersion = Get-KiCad-PackageVersion
    $kicadVersion = Get-KiCad-Version

    $nsisArch = Get-NSIS-Arch -Arch $arch
    $outFileName = "kicad-$packageVersion-$nsisArch-pdbs.zip"

    $outPath = Join-Path -Path $outPathRoot -ChildPath $outFileName

    7za a -tzip -mm=lzma -bsp0 $outPath $sourceFolder
    
    if ($LastExitCode -ne 0) {
        Write-Error "Error packaging PDBs"
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
    Set-VC-Environment -Arch $arch
    
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

    $destRoot = Join-Path -Path $outPathRoot -ChildPath "\msix-$buildName"
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
    $outFileName = "kicad-$packageVersion-$arch.msix"
    $outFilePath = Join-Path -Path $outPathRoot -ChildPath $outFileName
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

function Convert-Svg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$Svg,
        [Parameter(Mandatory=$True)]
        [int]$Width,
        [Parameter(Mandatory=$True)]
        [int]$Height,
        [Parameter(Mandatory=$True)]
        [string]$Out
    )

    Write-Host "Converting $Svg to $Out, w: $Width, h: $Height"

    inkscape --export-area-snap --export-type=png "$Svg" --export-filename "$Out" -w $Width -h $Height 2>$null

    if( $LastExitCode -ne 0 )
    {
        Write-Error "Error generating png from svg"
        Exit [ExitCodes]::InkscapeSvgConversion
    }
}

function Generate-Target-Size-Icon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$Svg,
        [Parameter(Mandatory=$True)]
        [int]$Size,
        [Parameter(Mandatory=$True)]
        [string]$OutBase
    )

    $out = "${OutBase}.targetsize-${Size}.png"
    Convert-Svg -Svg $svg -Width $Size -Height $Size -Out $out

    $out = "${OutBase}.targetsize-${Size}_altform-unplated.png"
    Convert-Svg -Svg $svg -Width $Size -Height $Size -Out $out
}


# Target size are specific 16,24,32,48,256
function Generate-Target-Size-Icons {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$Svg,
        [Parameter(Mandatory=$True)]
        [string]$OutBase
    )

    Generate-Target-Size-Icon -Svg $Svg -OutBase $OutBase -Size 16
    Generate-Target-Size-Icon -Svg $Svg -OutBase $OutBase -Size 24
    Generate-Target-Size-Icon -Svg $Svg -OutBase $OutBase -Size 32
    Generate-Target-Size-Icon -Svg $Svg -OutBase $OutBase -Size 48
    Generate-Target-Size-Icon -Svg $Svg -OutBase $OutBase -Size 256
}


$imageHelper = @"
    using System;
    using System.Drawing;
    using System.Drawing.Imaging;

    public class ImageHelper
    {
        public static void TilizeIcon(string sourcePath, int finalWidth, int finalHeight, string finalPath)
        {
            using (var finalImage = new Bitmap(finalWidth, finalHeight))
            {
                using (var source = new Bitmap(sourcePath))
                {
                    if(source.Width > finalWidth)
                    {
                        throw new ArgumentOutOfRangeException("Source width is larger than the final width");
                    }

                    if (source.Height > finalHeight)
                    {
                        throw new ArgumentOutOfRangeException("Source height is larger than the final height");
                    }

                    using (Graphics g = Graphics.FromImage(finalImage))
                    {
                        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                        g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                        g.DrawImage(source, (finalWidth-source.Width)/2, (finalHeight-source.Height)/2, source.Width, source.Height);
                    }
                }

                finalImage.Save(finalPath, ImageFormat.Png);
            }
        }
    }
"@

$assemblies = ("System.Drawing")
Add-Type -ReferencedAssemblies $assemblies -TypeDefinition $imageHelper -Language CSharp 

function Generate-Tile-Icon-Sub {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$Svg,
        [Parameter(Mandatory=$True)]
        [int]$Width,
        [Parameter(Mandatory=$True)]
        [int]$Height,
        [Parameter(Mandatory=$True)]
        [string]$OutBase,
        [Parameter(Mandatory=$True)]
        [int]$Scale,
        [Parameter(Mandatory=$False)]
        [bool]$Padding = $False
    )

    $shape = 'Square';
    if( $Width -ne $Height )
    {
        $shape = 'Wide';
    }

    $OutBase = "${OutBase}-${shape}${Width}x${Height}Logo";

    $out = "${OutBase}.scale-${Scale}.png"
    $finalWidth = $Width * ($Scale/100.0)
    $finalHeight = $Height* ($Scale/100.0)
    if( $Padding )
    {
        $iconWidth = $finalWidth*0.66
        $iconHeight = $finalHeight*0.50
        $iconDim = [math]::Min($iconHeight,$iconWidth)
        $iconDim = [math]::Round($iconDim, 0)
        
        Convert-Svg -Svg $svg -Width $iconDim -Height $iconDim -Out $out
        [ImageHelper]::TilizeIcon($out, $finalWidth, $finalHeight, $out)
    }
    else {
        Convert-Svg -Svg $svg -Width $finalHeight -Height $finalHeight -Out $out
        if( $finalWidth -eq 44 )
        {
            Generate-Target-Size-Icons -Svg $f.FullName -OutBase $OutBase
        }
    }
}

function Generate-Tile-Icon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$Svg,
        [Parameter(Mandatory=$True)]
        [int]$Width,
        [Parameter(Mandatory=$True)]
        [int]$Height,
        [Parameter(Mandatory=$True)]
        [string]$OutBase,
        [Parameter(Mandatory=$False)]
        [bool]$Padding = $False
    )


    Generate-Tile-Icon-Sub -Svg $Svg -Width $Width -Height $Height -OutBase $OutBase -Padding $Padding -Scale 100
    Generate-Tile-Icon-Sub -Svg $Svg -Width $Width -Height $Height -OutBase $OutBase -Padding $Padding -Scale 125
    Generate-Tile-Icon-Sub -Svg $Svg -Width $Width -Height $Height -OutBase $OutBase -Padding $Padding -Scale 150
    Generate-Tile-Icon-Sub -Svg $Svg -Width $Width -Height $Height -OutBase $OutBase -Padding $Padding -Scale 200
    Generate-Tile-Icon-Sub -Svg $Svg -Width $Width -Height $Height -OutBase $OutBase -Padding $Padding -Scale 400
}

function Generate-Tile-Icons {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$Svg,
        [Parameter(Mandatory=$True)]
        [string]$OutBase
    )

    Generate-Tile-Icon -Svg $Svg -OutBase $OutBase -Width 44 -Height 44
    Generate-Tile-Icon -Svg $Svg -OutBase $OutBase -Width 71 -Height 71 -Padding $True
    Generate-Tile-Icon -Svg $Svg -OutBase $OutBase -Width 150 -Height 150 -Padding $True
    Generate-Tile-Icon -Svg $Svg -OutBase $OutBase -Width 310 -Height 310 -Padding $True
    Generate-Tile-Icon -Svg $Svg -OutBase $OutBase -Width 310 -Height 150 -Padding $True
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
        Generate-Tile-Icons  -Svg $f.FullName -Out $basePath
    }
    
}


function Set-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]$VcpkgPath
    )

    $settings.VcpkgPath = $VcpkgPath

    $settings | ConvertTo-Json -Compress | Set-Content -Path $settingsPath
}


###
# Decode and execute the selected script stage
###

if( $Config )
{
    Set-Config -VcpkgPath $VcpkgPath
}

if( $Init )
{
    Start-Init
}

if( $Vcpkg )
{
    Build-Vcpkg -arch $Arch -latest $True
}

if( $Build )
{
    Start-Build -arch $Arch -buildType $BuildType -latest $Latest
}

if( $MsixAssets )
{
    Generate-Msix-Assets -version $Version
}

if( $PreparePackage -or ($Package -and $Prepare) )
{
    Start-Prepare-Package -arch $Arch -buildType $BuildType -includeVcpkgDebugSymbols $IncludeVcpkgDebugSymbols.IsPresent -lite $Lite -sign $Sign
}

if( $Package )
{
    if( $PackType -eq 'nsis' )
    {
        Start-Package-Nsis -arch $Arch -buildType $BuildType -includeVcpkgDebugSymbols $IncludeVcpkgDebugSymbols -lite $Lite -postCleanup $PostCleanup -sign $Sign
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
        Start-Package-Pdb -arch $Arch -buildType $BuildType
    }
}
