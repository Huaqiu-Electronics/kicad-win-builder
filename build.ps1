##
# KiCad Powershell Windows Build Assistant
#
#  Usage:
#   Configure/set the vcpkg path
#   ./build.ps1 -Config -VcpkgPath="path to vcpkg"
#
#   Checkout any required tools
#   ./build.ps1 -Setup
#   
#   Rebuilds vcpkg dependencies (if updated)
#   ./build.ps1 -Vcpkg
#   
#   Triggers a build
#   ./build.ps1 -Build -Latest
#   
#   Triggers a package operation
#   ./build.ps1 -Package
#
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
    [Switch]$Latest,

    [Parameter(Mandatory=$True, ParameterSetName="build")]
    [Parameter(Mandatory=$True, ParameterSetName="vcpkg")]
    [ValidateSet('x86', 'x64')]
    [string]$Arch,

    [Parameter(Mandatory=$True, ParameterSetName="build")]
    [ValidateSet('Release', 'Debug')]
    [string]$BuildType = 'Release',
	
    [Parameter(Mandatory=$True, ParameterSetName="config")]
	[ValidateScript({Test-Path $_})]
    [string]$VcpkgPath
)

enum Arch {
    x86
    x64
}

### 
## Base setup
### 

$cmakeDownload = 'https://github.com/Kitware/CMake/releases/download/v3.19.2/cmake-3.19.2-win64-x64.zip';
$vswhereDownload = 'https://github.com/microsoft/vswhere/releases/download/2.8.4/vswhere.exe'
$swigwinDownload = "https://sourceforge.net/projects/swig/files/swigwin/swigwin-4.0.2/swigwin-4.0.2.zip/download?use_mirror=pilotfiber"

$downloadsPathRoot = ($PSScriptRoot+"/.downloads/")
$supportPathRoot = ($PSScriptRoot+"/.support/")

$swigWinPath = ($supportPathRoot+"/swigwin")

# Use TLS1.2 by force in case of older powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$env:Path = $swigWinPath+";"+$env:PATH

### 
# Load and handle Config
###
$settingsPath = $PSScriptRoot + "\settings.json";

$settingDefault = @{
	VcpkgPath = ''
}

$settingsSaved = @{}
if ( Test-Path $settingsPath ) {
    $settingsObj = Get-Content -Path $settingsPath | ConvertFrom-Json

    $settingsObj.psobject.properties | Foreach { $settingsSaved[$_.Name] = $_.Value }
}

$settings = Merge-HashTable -default $settingDefault -uppend $settingsSaved

### 
# Setup aliases to shorten accessing tools
##
$vcpkgPath = Join-Path -Path $settings.VcpkgPath -ChildPath "vcpkg.exe"

Set-Alias vcpkg $vcpkgPath -Option AllScope
Set-Alias 7zip ./tools/7zip/7za.exe -Option AllScope
Set-Alias vswhere ($supportPathRoot+"vswhere.exe") -Option AllScope
Set-Alias cmake ($supportPathRoot+"cmake/bin/cmake.exe") -Option AllScope


function Find-VS()
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [Arch]$Arch = [Arch]::x64,
        [Parameter()]
        [Arch]$HostArch = [Arch]::x64,
        [Parameter(ValueFromRemainingArguments=$true)]
        $Arguments
    )

    $installDir = vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($installDir) {
        $path = join-path $installDir 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt'
        if (test-path $path) {
            $version = gc -raw $path
            if ($version) {
                $version = $version.Trim()
                $path = join-path $installDir "VC\Tools\MSVC\$version\bin\Host$HostArch\$Arch\cl.exe"
                & $path $Arguments
            }
        }
    }
}

function Set-VC-Vars($vcvarsname)
{
    Push-Location "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build"
    cmd /c "$vcvarsname.bat&set" |
    Foreach-Object {
      if ($_ -match "=") {
        $v = $_.split("="); set-item -force -path "ENV:\$($v[0])"  -value "$($v[1])"
      }
    }
    Pop-Location
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

function Build-Kicad {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch,
        [Parameter(Mandatory=$False)]
        [ValidateSet('Release', 'Debug')]
        [string]$buildType = 'Release'
    )

    Reset-Env-Path

    #step down into kicad folder
    Push-Location kicad

    $generator = "Ninja";
    if($arch -eq [Arch]::x64)
    {
        $cmakeBuildFolder = "build64";
        Set-VC-Vars("vcvars64")
    }
    elseif($arch -eq [Arch]::x86)
    {
        $cmakeBuildFolder = "build32";
        Set-VC-Vars("vcvars32")
    }
    #delete the old build folder
    Remove-Item $cmakeBuildFolder -Recurse

    
    $installPath = "$PSScriptRoot/.out/$triplet/"
    $toolchainPath = ($settings["VcpkgPath"]+"scripts/buildsystems/vcpkg.cmake")

    cmake -G $generator `
        -B $cmakeBuildFolder `
        -S .  `
        -DCMAKE_BUILD_TYPE="$buildType" `
        -DCMAKE_TOOLCHAIN_FILE="$toolchainPath" `
        -DCMAKE_INSTALL_PREFIX="$installPath" `
        -DKICAD_SPICE="ON" `
        -DKICAD_USE_OCE="OFF" `
        -DKICAD_SCRIPTING="OFF" `
        -DKICAD_SCRIPTING_WXPYTHON="OFF" `
        -DKICAD_SCRIPTING_MODULES="ON"

    if (!$?) {
        Write-Error "Failure generating cmake"
    } else {
        Write-Host "Invoking cmake build" -ForegroundColor Yellow
        cmake --build $cmakeBuildFolder -j 16
        
        if (!$?) {
            Write-Error "Failure with cmake build"
        } else {
            Write-Host "Invoking cmake install" -ForegroundColor Yellow
            cmake --install $cmakeBuildFolder
            
            if (!$?) {
                Write-Error "Failure with cmake install"
            } else {
                Write-Host "Build complete" -ForegroundColor Green
            }
        }
    }

    #restore path
    Pop-Location
}

function Unzip([string] $zip, [string] $dest) {
    $dest = "-o"+$dest;
    7zip x $zip "$dest" -y
}

function Start-Init {
    # The progress bar slows down download performance by absurd amounts, turn it off
    $ProgressPreference = 'SilentlyContinue'

    if(![System.IO.Directory]::Exists( $supportPathRoot+"cmake" ))
    {
        Write-Host "Downloading CMake..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $cmakeDownload -OutFile ($downloadsPathRoot+"cmake.zip")
        Write-Host "Extracting Cmake" -ForegroundColor Yellow
        unzip ($downloadsPathRoot+"cmake.zip") $supportPathRoot

        $folder = Get-ChildItem ($supportPathRoot+'cmake-*/') -Directory
        Move-Item $folder ($supportPathRoot+'cmake/')
    }
    else
    {
        Write-Host "Cmake already exists";
    }

    if(![System.IO.File]::Exists( $supportPathRoot+"vswhere.exe" ))
    {
        Write-Host "Downloading Vswhere..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $vswhereDownload -OutFile ($supportPathRoot+"vswhere.exe")
    }
    else
    {
        Write-Host "vswhere already exists";
    }

    if(![System.IO.Directory]::Exists( $supportPathRoot+"swigwin" ))
    {
        Write-Host "Downloading Swigwin..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $swigwinDownload -OutFile ($downloadsPathRoot+"swigwin.zip") -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
        
        Write-Host "Extracting Cmake" -ForegroundColor Yellow
        unzip ($downloadsPathRoot+"swigwin.zip") $supportPathRoot

        
        $folder = Get-ChildItem ($supportPathRoot+'swigwin-*/') -Directory
        Move-Item $folder ($supportPathRoot+'swigwin/')
    }
    else
    {
        Write-Host "Cmake already exists";
    }

    ### Download Kicad
    if(![System.IO.Directory]::Exists($PSScriptRoot+'kicad/'))
    {
        Write-Host "Cloning kicad repo";
        git clone https://gitlab.com/kicad/code/kicad.git kicad
    }

    # Restore progress bar
    $ProgressPreference = 'Continue'
}

function Get-Vcpkg-Triplet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch
    )

    $triplet = "$arch-windows"
    return $triplet;
}


function Build-Vcpkg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch
    )

    # Bootstrap vcpkg
    Push-Location $settings["VcpkgPath"]
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
                        "ngspice",
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

    Pop-Location
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

function Start-Package {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [Arch]$arch
    )

    $triplet = Get-Vcpkg-Triplet -Arch $arch
    $vcpkgInstalled = ("$settings.VcpkgPath\installed\$triplet\")
    $destPath = ("$PSScriptRoot\.out\$triplet\")

    $vcpkgBinCopy = @( "boost*",
                        "TK*",
                        "wx*"
                    )

    for ($i = 0; $i -lt $vcpkgBinCopy.Count; $i++) {
        Copy-Item ("$vcpkgInstalled\bin\$vcpkgBinCopy[$i]") -Destination "$destPath\bin\" -Recurse
    }

    ## now python3
    Copy-Item ("$vcpkgInstalled\python3\*") -Destination "$destPath\lib\python3" -Recurse
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

function Get-Latest-Kicad {
    Push-Location ($PSScriptRoot+"kicad")
    git reset --hard origin/master
    git clean -f
    git pull --rebase
    Pop-Location
}

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
    Build-Vcpkg -arch $Arch
}

if( $Latest )
{
    Get-Latest-Kicad
}

if( $Build )
{
    Build-KiCad -arch $Arch -buildType $BuildType
}

if( $Package )
{
    Start-Package
}