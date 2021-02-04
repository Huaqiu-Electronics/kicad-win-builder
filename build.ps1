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
#   ./build.ps1 -Vcpkg [-Latest] [-Arch x64] [-BuildType Release]
#   
#   Triggers a build
#   ./build.ps1 -Build [-Latest] [-Arch x64] [-BuildType Release]
#   
#   Triggers a package operation
#   ./build.ps1 -Package [-Arch x64] [-BuildType Release] [-Lite] [-IncludeDebugSymbols]
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

    [Parameter(Mandatory=$False, ParameterSetName="build")]
    [Parameter(Mandatory=$False, ParameterSetName="vcpkg")]
    [Switch]$Latest,

    [Parameter(Mandatory=$False, ParameterSetName="build")]
    [Parameter(Mandatory=$False, ParameterSetName="vcpkg")]
    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [ValidateSet('x86', 'x64', 'arm64', 'arm')]
    [string]$Arch = 'x64',

    [Parameter(Mandatory=$False, ParameterSetName="build")]
    [ValidateSet('Release', 'Debug')]
    [string]$BuildType = 'Release',
	
    [Parameter(Mandatory=$True, ParameterSetName="config")]
	[ValidateScript({Test-Path $_})]
    [string]$VcpkgPath,
    
    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [switch]$IncludeDebugSymbols,
    
    [Parameter(Mandatory=$False, ParameterSetName="package")]
    [switch]$Lite
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
}

# Load the .NET compression library, powershell's expand-archive is horrid in performance
Add-Type -Assembly 'System.IO.Compression.FileSystem'


### 
## Base setup
### 

$cmakeDownload = 'https://github.com/Kitware/CMake/releases/download/v3.19.2/cmake-3.19.2-win64-x64.zip'
$cmakeChecksum = "A6FDF509D7A39F1C08B429EAA3EA0012744365A731D00FB770AE88B4D6549FF3"

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
$nsisPath = Join-Path -Path $supportPathRoot -ChildPath "nsis/bin/"

$env:Path = $swigWinPath+";"+$gettextPath+";"+$nsisPath+";"+$env:PATH


# Use TLS1.2 by force in case of older powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$env:GIT_REDIRECT_STDERR='2>&1'


### 
# Load and handle Config
###
$settingsPath = $PSScriptRoot + "\settings.json";

$settingDefault = @{
    VcpkgPath = ''
    VcpkgPlatformToolset = 'v142'
    VsVersion = '16.0'
}

$settingsSaved = @{}
if ( Test-Path $settingsPath ) {
    $settingsObj = Get-Content -Path $settingsPath | ConvertFrom-Json

    $settingsObj.psobject.properties | Foreach { $settingsSaved[$_.Name] = $_.Value }
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
        $tmp = Join-Path -Path $supportPathRoot -ChildPath "cmake/bin/cmake.exe"
        Set-Alias cmake $tmp -Option AllScope -Scope Global
    }

    if( -not (Test-Path alias:makensis ) )
    {
        $tmp = Join-Path -Path $supportPathRoot -ChildPath "nsis/bin/makensis.exe"
        Set-Alias makensis $tmp -Option AllScope -Scope Global
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
        {[Arch]::x64} {
            $msvc = "amd64"
            break   
        }
        {[Arch]::x86} {
            $msvc = "x86"
            break   
        }
        {[Arch]::arm} {
            $msvc = "arm"
            break   
        }
        {[Arch]::arm64} {
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
        {[Arch]::x64} {
            $nsis = "x86_64"
            break
        }
        {[Arch]::x86} {
            $nsis = "i686"
            break   
        }
        {[Arch]::arm} {
            $nsis = "arm"
            break   
        }
        {[Arch]::arm64} {
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
            
            if (!$?)
            {
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
            git -C "$dest" reset `@`{upstream`}
            git -C "$dest" clean -f
            git -C "$dest" pull --rebase
            
            if (!$?)
            {
                Write-Error "Error cloning kicad repo"
                Exit [ExitCodes]::GitCloneFailure
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

    cmake -G $generator `
        -B $cmakeBuildFolder `
        -S .  `
        -DCMAKE_INSTALL_PREFIX="$installPath" `
        -DCMAKE_RULE_MESSAGES:BOOL="OFF" `
        -DCMAKE_VERBOSE_MAKEFILE:BOOL="OFF"

    if (!$?) {
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
    cmake --install $cmakeBuildFolder > $null
    if (!$?) {
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
    cmake --install $cmakeBuildFolder > $null
    
    if (!$?) {
        Write-Error "Failure with cmake install"
        Pop-Location
        Exit [ExitCodes]::CMakeInstallFailure
    } else {
        Write-Host "Build complete" -ForegroundColor Green
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

    Write-Host "Starting build"
    Write-Host "arch: $arch"
    Write-Host "buildType: $buildType"
    Write-Host "Configured install directory: $installPath"
    Write-Host "Vcpkg Path: $toolchainPath"

    cmake -G $generator `
        -B $cmakeBuildFolder `
        -S .  `
        -DCMAKE_BUILD_TYPE="$buildType" `
        -DCMAKE_TOOLCHAIN_FILE="$toolchainPath" `
        -DCMAKE_INSTALL_PREFIX="$installPath" `
        -DKICAD_SPICE="ON" `
        -DKICAD_USE_OCE="OFF" `
        -DKICAD_USE_OCC="ON" `
        -DKICAD_SCRIPTING="ON" `
        -DKICAD_SCRIPTING_PYTHON3="ON" `
        -DKICAD_SCRIPTING_WXPYTHON="ON" `
        -DKICAD_SCRIPTING_WXPYTHON_PHOENIX="ON" `
        -DKICAD_SCRIPTING_MODULES="ON" `
        -DKICAD_BUILD_QA_TESTS="OFF" `
        -DKICAD_WIN32_DPI_AWARE="ON" `
        -DKICAD_BUILD_I18N="ON"

    if (!$?) {
        Write-Error "Failure generating cmake"
        Pop-Location
        Exit [ExitCodes]::CMakeGenerationFailure
    } else {
        Write-Host "Invoking cmake build" -ForegroundColor Yellow
        cmake --build $cmakeBuildFolder -j 16
        
        if (!$?) {
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
             -DestPath ($supportPathRoot+'cmake/') `
             -DownloadPath ($downloadsPathRoot+"cmake.zip") `
             -Checksum $cmakeChecksum `
             -ExtractZip $true `
             -ZipRelocate $True `
             -ZipRelocateFilter ($supportPathRoot+'cmake-*/') `
             -ExtractInSupportRoot $True

    Get-Tool -ToolName "swigwin" `
             -Url $swigwinDownload `
             -DestPath ($supportPathRoot+"$swigwinFolder/") `
             -DownloadPath ($downloadsPathRoot+"$swigwinFolder.zip") `
             -Checksum $swigwinChecksum `
             -ExtractZip $true `
             -ExtractInSupportRoot $True

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
             -ExtractZip $true `

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
        [bool]$latest = $false
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
        & git pull --rebase
    }
    
    .\bootstrap-vcpkg.bat

    # Setup dependencies
    $triplet = Get-Vcpkg-Triplet -Arch $arch


    $dependencies = @( "boost",
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
                        "openssl",
                        "python3",
                        "wxwidgets",
                        "wxpython",
                        "zlib")

    # Format the dependencies with the triplet
    for ($i = 0; $i -lt $dependencies.Count; $i++) {
        $dependencies[$i] = $dependencies[$i]+":$triplet"
    }
    
    vcpkg install $dependencies
    
    if (!$?) {
        Write-Error "Failure installing vcpkg ports"
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

function Start-Package {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch,
        [Parameter(Mandatory=$False)]
        [ValidateSet('Release', 'Debug')]
        [string]$buildType = "Release",
        [Parameter(Mandatory=$False)]
        [bool]$includeDebugSymbols = $False,
        [Parameter(Mandatory=$False)]
        [bool]$lite = $False
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
                        "libxslt*",
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

        if(!$includeDebugSymbols)
        {
            $source += ".dll";
        }
        
        Write-Host "Copying $source"
        Copy-Item $source -Destination $destBin -Recurse
    }

    ## ngspice related
    $ngspiceLib = Join-Path -Path $vcpkgInstalledRoot -ChildPath "lib\ngspice"
    Write-Host "Copying ngspice lib $ngspiceLib to $destLib"
    Copy-Item $ngspiceLib -Destination $destLib -Recurse -Container  -Force

    $ngspiceShare = Join-Path -Path $vcpkgInstalledRoot -ChildPath "share\ngspice"
    Write-Host "Copying ngspice share $ngspiceShare to $destLib"
    Copy-Item $ngspiceShare -Destination $destLib -Recurse -Container  -Force

    ## now python3
    $python3Source = "$vcpkgInstalledRootPrimary\tools\python3\"
    Write-Host "Copying python3 $python3Source to $destLib"
    Copy-Item $python3Source -Destination $destLib -Recurse -Container  -Force
    
    ## now libxslt
    $xsltprocSource = "$vcpkgInstalledRootPrimary\tools\libxslt\xsltproc.exe"
    Write-Host "Copying $xsltprocSource to $destBin"
    Copy-Item $xsltprocSource -Destination $destBin -Recurse  -Force

    ## now nsis
    $nsisSource = Join-Path -Path $PSScriptRoot -ChildPath "nsis\"
    Write-Host "Copying nsis $nsisSource to $nsisDest"
    Copy-Item $nsisSource -Destination $destRoot -Recurse -Container -Force

    ## Run NSIS
    $nsisScript = Join-Path -Path $destRoot -ChildPath "nsis\install.nsi"

    Write-Host "Copying LICENSE.README as copyright.txt"

    $readmeSrc = Join-Path -Path (Get-Source-Path kicad) -ChildPath "LICENSE.README"
    Copy-Item $readmeSrc -Destination "$destRoot\COPYRIGHT.txt" -Force


    if( $lite )
    {
        $liteGitTag = "master"
        $found = $packageVersion -match '^\d+\.\d+\.\d+'
        if ($found) {
            $liteGitTag = $matches[0]
        }
        
        makensis /DPACKAGE_VERSION=$packageVersion `
            /DKICAD_VERSION=$kicadVersion `
            /DOUTFILE="..\kicad-$packageVersion-$nsisArch-lite.exe" `
            /DARCH="$nsisArch" `
            /DLIBRARIES_TAG="$liteGitTag" `
            /DMSVC `
            "$nsisScript"
    }
    else
    {
        makensis /DPACKAGE_VERSION=$packageVersion `
            /DKICAD_VERSION=$kicadVersion `
            /DOUTFILE="..\kicad-$packageVersion-$nsisArch.exe" `
            /DARCH="$nsisArch" `
            /DMSVC `
            "$nsisScript"
    }

        
    if (!$?) {
        Write-Error "Error building nsis package"
        Exit [ExitCodes]::NsisFailure
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
    Build-Vcpkg -arch $Arch -latest $Latest
}

if( $Build )
{
    Start-Build -arch $Arch -buildType $BuildType -latest $Latest
}

if( $Package )
{
    Start-Package -arch $Arch -includeDebugSymbols $IncludeDebugSymbols -lite $Lite
}
